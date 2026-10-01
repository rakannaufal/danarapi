import { normalizeReceipt, validateReceipt, type ScanResult } from './receipt.ts';

export type ScanImage = { mimeType: string; data: string };
export type ScanStore = { claim(userID: string, hash: string): Promise<{ state: 'new' | 'cached' | 'busy' | 'quota_exceeded'; result?: ScanResult }>; reserve(userID: string, hash: string): Promise<number>; finish(userID: string, hash: string, result: ScanResult): Promise<void> };
export const receiptPrompt = `Kamu adalah mesin ekstraksi struk restoran/toko di Indonesia.
Baca gambar struk dan keluarkan HANYA data sesuai skema JSON.

Aturan:
1. merchant: nama toko dari bagian atas struk. Jika tidak terbaca, isi null.
2. items: satu objek per menu/produk. Jangan masukkan Subtotal, Service,
   Tax/PB1/PPN, Diskon, Pembulatan, Total, atau metode bayar ke items.
3. Angka rupiah: tulis sebagai bilangan bulat tanpa titik/koma/"Rp".
   Titik pada "30.000" adalah pemisah ribuan, bukan desimal.
4. qty = jumlah pesanan. unit_price = harga satuan.
   line_total = total baris seperti tertulis di struk.
5. Jika nama menu tercetak dua baris, gabungkan jadi satu nama.
6. Baris tambahan seperti "+ Extra Keju" yang punya harga dicatat sebagai
   item terpisah. Yang tidak punya harga masukkan ke "note" pada item di atasnya.
7. Diskon/voucher: isi discount sebagai angka positif.
8. Jika struk menyatakan harga sudah termasuk pajak/service
   ("incl. tax", "sudah termasuk pajak"), set tax_included_in_price = true.
9. Jangan menebak. Jika sebuah angka tidak terbaca jelas, isi null dan
   tambahkan nama field-nya ke unreadable_fields.
10. Jangan menghitung ulang angka; salin apa adanya dari struk.
11. Tanggal harus YYYY-MM-DD dari tanggal tercetak, bukan tanggal hari ini.
12. Jumlah kemasan dan ukuran produk bukan pengali tambahan. Contoh
    "1 lusin x 36,000" dengan total baris 36.000: qty=1, unit_price=36000,
    note="1 lusin". "1 500 ml x 7,000": qty=1, unit_price=7000, note="500 ml".
    Jangan gunakan Total QTY sebagai qty tiap menu.
13. grand_total hanya dari Total/Grand Total, bukan Bayar/Cash/Kembali,
    nomor telepon, nomor transaksi, atau jumlah produk.
14. Biaya service/pajak/diskon/pembulatan yang tidak tercantum di struk = 0.
15. Struk grosir bisa memiliki jumlah ribuan. "4.000 Kg x 12.500" berarti
    qty=4000, unit_price=12500, note="Kg". "8.000 Pcs" berarti qty=8000.
    Salin satuan Kg/Box/Pcs/Klg ke note, bukan ke nama atau harga.
    Jangan membatasi jumlah menjadi 999 atau mengubahnya agar total cocok.
16. Jika qty × harga berbeda dari total baris, pertahankan ketiganya sesuai
    cetakan. Subtotal dan total baris juga tidak harus cocok; jangan perbaiki
    salah hitung pada struk. Jika hanya Subtotal, Bayar, Kembali tercetak,
    gunakan Subtotal sebagai grand_total saat tidak ada biaya tambahan;
    jangan gunakan Bayar atau Kembali sebagai total belanja.
    Subtotal atau grand_total yang tidak terbaca tetap null, jangan ditebak.`;
const moneySchema = { type: 'INTEGER', nullable: true };
export const receiptSchema = { type: 'OBJECT', properties: {
  merchant: { type: 'STRING', nullable: true }, date: { type: 'STRING', nullable: true },
  items: { type: 'ARRAY', items: { type: 'OBJECT', properties: { name: { type: 'STRING' }, qty: { type: 'INTEGER' }, unit_price: moneySchema, line_total: moneySchema, note: { type: 'STRING', nullable: true } }, required: ['name', 'qty', 'unit_price', 'line_total', 'note'] } },
  subtotal: moneySchema, service_charge: moneySchema, tax: moneySchema, discount: { type: 'INTEGER' }, rounding: { type: 'INTEGER' }, grand_total: moneySchema, tax_included_in_price: { type: 'BOOLEAN' }, unreadable_fields: { type: 'ARRAY', items: { type: 'STRING' } },
}, required: ['merchant', 'date', 'items', 'subtotal', 'service_charge', 'tax', 'discount', 'rounding', 'grand_total', 'tax_included_in_price', 'unreadable_fields'] };

export async function readBounded(response: Pick<Response, 'headers' | 'body'>, maximum: number): Promise<Uint8Array> {
  if (Number(response.headers.get('content-length')) > maximum) throw new Error('size_limit');
  const reader = response.body?.getReader();
  if (!reader) throw new Error('empty_body');
  const chunks: Uint8Array[] = []; let size = 0;
  try { while (true) { const { done, value } = await reader.read(); if (done) break; size += value.length; if (size > maximum) throw new Error('size_limit'); chunks.push(value); } }
  finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return bytes;
}
export async function validateImages(raw: unknown): Promise<{ images: ScanImage[]; hash: string }> {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > 3) throw new Error('invalid_image');
  const version = new TextEncoder().encode('danarapi-receipt-v2-wholesale\0');
  let size = 0; const buffers: Uint8Array[] = [version]; const images: ScanImage[] = [];
  for (const image of raw) {
    if (!image || !['image/jpeg', 'image/png', 'image/webp'].includes(image.mimeType) || typeof image.data !== 'string' || image.data.length > 5592408 || !/^[A-Za-z0-9+/]+={0,2}$/.test(image.data)) throw new Error('invalid_image');
    let bytes: Uint8Array;
    try { bytes = Uint8Array.from(atob(image.data), character => character.charCodeAt(0)); } catch { throw new Error('invalid_image'); }
    size += bytes.length; if (size > 4 * 1024 * 1024 || bytes.length < 12) throw new Error('invalid_image');
    const jpeg = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
    const png = [137,80,78,71,13,10,26,10].every((value, index) => bytes[index] === value);
    const webp = new TextDecoder().decode(bytes.slice(0, 4)) === 'RIFF' && new TextDecoder().decode(bytes.slice(8, 12)) === 'WEBP';
    if (!(image.mimeType === 'image/jpeg' ? jpeg : image.mimeType === 'image/png' ? png : webp)) throw new Error('invalid_image');
    const header = new Uint8Array(4); new DataView(header.buffer).setUint32(0, bytes.length);
    buffers.push(header, bytes); images.push({ mimeType: image.mimeType, data: image.data });
  }
  const joined = new Uint8Array(version.length + size + images.length * 4); let offset = 0;
  for (const buffer of buffers) { joined.set(buffer, offset); offset += buffer.length; }
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', joined));
  return { images, hash: [...digest].map(value => value.toString(16).padStart(2, '0')).join('') };
}

export async function scanReceipt(options: { userID: string; hash: string; images: ScanImage[]; apiKey: string; model: string; fallbackModel?: string; store: ScanStore; fetch?: typeof fetch; sleep?: (milliseconds: number) => Promise<void> }): Promise<ScanResult> {
  const { store, userID, hash } = options;
  if (!options.apiKey || !/^[a-zA-Z0-9._-]+$/.test(options.model) || (options.fallbackModel && !/^[a-zA-Z0-9._-]+$/.test(options.fallbackModel))) return { status: 'config_error' };
  const claim = await store.claim(userID, hash);
  if (claim.state === 'cached') return { ...claim.result!, cached: true };
  if (claim.state !== 'new') return { status: claim.state };
  const sleep = options.sleep ?? (milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds)));
  const request = options.fetch ?? fetch;
  let result: ScanResult = { status: 'service_error' }; let correction = ''; let previousStatus = 0;
  for (let attempt = 0; attempt < 2; attempt++) {
    let wait: number;
    try { wait = await store.reserve(userID, hash); } catch { break; }
    await sleep(Math.max(wait, attempt ? previousStatus === 429 ? 2000 : previousStatus >= 500 ? 2000 : 0 : 0));
    const model = attempt && previousStatus === 429 && options.fallbackModel ? options.fallbackModel : options.model;
    try {
      const response = await request(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-goog-api-key': options.apiKey }, signal: AbortSignal.timeout(30000), body: JSON.stringify({ systemInstruction: { parts: [{ text: receiptPrompt }] }, contents: [{ role: 'user', parts: [{ text: correction || 'Ekstrak struk ini sesuai skema.' }, ...options.images.map(image => ({ inlineData: { mimeType: image.mimeType, data: image.data } }))] }], generationConfig: { responseMimeType: 'application/json', responseSchema: receiptSchema, maxOutputTokens: 8192 } }) });
      previousStatus = response.status;
      if (!response.ok) {
        await response.body?.cancel();
        if (response.status === 400 || response.status === 401 || response.status === 403 || response.status === 404) { if (!result.data) result = { status: 'config_error' }; break; }
        if (!result.data) result = { status: response.status === 429 ? 'quota_exceeded' : 'service_error' }; continue;
      }
      const payload = JSON.parse(new TextDecoder().decode(await readBounded(response, 256 * 1024)));
      const candidate = payload.candidates?.[0];
      const parts = Array.isArray(candidate?.content?.parts) ? candidate.content.parts : [];
      const text = parts.filter((part: { thought?: boolean; text?: unknown }) => !part.thought && typeof part.text === 'string').map((part: { text: string }) => part.text).join('');
      if (candidate?.finishReason !== 'STOP' || !text || payload.promptFeedback?.blockReason) { if (!result.data) result = { status: 'no_result' }; break; }
      const data = normalizeReceipt(JSON.parse(text)); const validasi = validateReceipt(data);
      result = { status: data.items.length ? 'ok' : 'not_a_receipt', data, validasi };
      if (!data.items.length || validasi.lolos) break;
      correction = `Hasil ekstraksi sebelumnya tidak konsisten: ${validasi.masalah.map(issue => issue.pesan).join(' ')}. Periksa kembali gambar, cari menu yang terlewat atau angka yang salah baca, lalu keluarkan JSON lengkap yang sudah dikoreksi. Jangan menghitung ulang angka; salin apa adanya. Jika tetap tidak yakin, isi null dan tulis di unreadable_fields.`;
    } catch { previousStatus = 500; if (!result.data) result = { status: 'service_error' }; correction = 'Respons sebelumnya bukan JSON lengkap. Baca ulang gambar, salin apa adanya, keluarkan JSON lengkap sesuai skema.'; }
  }
  await store.finish(userID, hash, result);
  return result;
}
