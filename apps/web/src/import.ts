import { parseMoney } from './contracts.ts';
import { id, type Review, type Field } from './domain.ts';

export function crc16(value: string) {
  let crc = 0xffff;
  for (const byte of new TextEncoder().encode(value)) { crc ^= byte << 8; for (let bit = 0; bit < 8; bit++) crc = (crc & 0x8000) ? (crc << 1) ^ 0x1021 : crc << 1; crc &= 0xffff; }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}
export function parseQR(raw: string) {
  if (!raw.startsWith('000201') || !raw.endsWith(crc16(raw.slice(0, -4))) || raw.slice(-8, -4) !== '6304') throw new Error('QR tidak didukung atau CRC tidak valid.');
  const fields = new Map<string, string>();
  for (let offset = 0; offset < raw.length;) {
    const tag = raw.slice(offset, offset + 2), lengthText = raw.slice(offset + 2, offset + 4);
    if (!/^\d{2}$/.test(tag) || !/^\d{2}$/.test(lengthText) || fields.has(tag)) throw new Error('Struktur QR tidak valid.');
    const length = Number(lengthText), value = raw.slice(offset + 4, offset + 4 + length);
    if (value.length !== length) throw new Error('Struktur QR tidak valid.'); fields.set(tag, value); offset += 4 + length;
  }
  if (![...fields.keys()].some(tag => Number(tag) >= 26 && Number(tag) <= 51) || !fields.get('59')) throw new Error('QR tidak didukung.');
  const amount = fields.get('54')?.replace(/\.00$/, '') ?? null;
  if (amount) parseMoney(amount);
  return { merchant: fields.get('59')!, city: fields.get('60') ?? null, amount };
}
export function parseText(text: string, source = 'pasted_text'): Review {
  if (text.length > 200000) throw new Error('Teks terlalu panjang. Maksimal 200.000 karakter.');
  const field = (value: string | null, confidence: Field['confidence'], evidenceSpan: string | null): Field => ({ value, confidence, evidenceSpan, sourceType: source });
  const lines = text.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  const totals = lines.filter(line => /^(?:total(?: pembayaran| bayar)?|jumlah pembayaran|grand total)\s*[:=]?\s*(?:Rp\s*)?[\d.]+\s*$/i.test(line));
  let amount: string | null = null;
  if (totals.length === 1) { const value = totals[0].match(/[\d.]+\s*$/)?.[0].trim().replaceAll('.', ''); if (value) { try { parseMoney(value); amount = value; } catch { amount = null; } } }
  const rawDate = text.match(/\b(\d{2})\/(\d{2})\/(\d{4})\b/), isoDate = text.match(/\b(\d{4}-\d{2}-\d{2})\b/);
  let date: string | null = null;
  if (rawDate) { const candidate = `${rawDate[3]}-${rawDate[2]}-${rawDate[1]}`; if (Number.isFinite(Date.parse(candidate)) && new Date(candidate).toISOString().slice(0, 10) === candidate) date = candidate; }
  else if (isoDate && Number.isFinite(Date.parse(isoDate[1])) && new Date(isoDate[1]).toISOString().slice(0, 10) === isoDate[1]) date = isoDate[1];
  return { id: id(), source, status: 'pending', amount: field(amount, amount ? 'high' : 'low', totals.length ? totals.join('; ') : null), merchant: field(lines[0] && !/total|\d/i.test(lines[0]) ? lines[0] : null, 'medium', lines[0] ?? null), date: field(date, date ? 'medium' : 'low', rawDate?.[0] ?? isoDate?.[0] ?? null), rawReference: text, createdAt: new Date().toISOString() };
}
export async function fingerprint(bytes: Uint8Array) { const hash = await crypto.subtle.digest('SHA-256', new Uint8Array(bytes)); return [...new Uint8Array(hash)].map(byte => byte.toString(16).padStart(2, '0')).join(''); }
export async function sanitizeImage(file: File) {
  if (file.type === 'application/pdf') return file;
  const bitmap = await createImageBitmap(file);
  try {
    const canvas = document.createElement('canvas'); canvas.width = bitmap.width; canvas.height = bitmap.height;
    const context = canvas.getContext('2d'); if (!context) throw new Error('Konversi gambar tidak tersedia.');
    context.drawImage(bitmap, 0, 0);
    const blob = await new Promise<Blob>((resolve, reject) => canvas.toBlob(value => value ? resolve(value) : reject(new Error('Konversi gambar gagal.')), file.type, 0.92));
    if (blob.size > 5 * 1024 * 1024) throw new Error('Gambar setelah penghapusan metadata melampaui 5 MB.');
    return new File([blob], file.name, { type: file.type });
  } finally { bitmap.close(); }
}
export async function validateFile(file: File) {
  if (file.size > 5 * 1024 * 1024 || file.size === 0) throw new Error('Berkas harus berisi data, maksimal 5 MB.');
  const bytes = new Uint8Array(await file.arrayBuffer());
  const isPDF = new TextDecoder().decode(bytes.slice(0, 5)) === '%PDF-';
  const isPNG = bytes.slice(0, 8).every((byte, index) => byte === [137, 80, 78, 71, 13, 10, 26, 10][index]);
  const isJPEG = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  if (!isPDF && !isPNG && !isJPEG) throw new Error('Jenis berkas tidak didukung. Gunakan JPEG, PNG, atau PDF. Konversikan HEIC ke JPEG terlebih dahulu.');
  if ((isPDF && file.type !== 'application/pdf') || (isPNG && file.type !== 'image/png') || (isJPEG && file.type !== 'image/jpeg')) throw new Error('Isi berkas tidak cocok dengan jenis MIME.');
  return { bytes, isPDF, isPNG, isJPEG };
}
export async function parseFile(file: File): Promise<Review> {
  const { bytes, isPDF } = await validateFile(file);
  let review: Review;
  if (isPDF) {
    const pdf = await import('pdfjs-dist');
    const worker = await import('pdfjs-dist/build/pdf.worker.min.mjs?url');
    pdf.GlobalWorkerOptions.workerSrc = worker.default;
    const loading = pdf.getDocument({ data: bytes.slice(), stopAtErrors: true, enableXfa: false });
    try {
      const document = await loading.promise;
      if (document.numPages > 30) throw new RangeError('PDF maksimal 30 halaman.');
      const lines: string[] = [];
      for (let page = 1; page <= document.numPages; page++) {
        const content = await (await document.getPage(page)).getTextContent();
        let line = '';
        for (const item of content.items) if ('str' in item) { line += `${item.str} `; if (item.hasEOL) { lines.push(line.trim()); line = ''; } }
        if (line) lines.push(line.trim());
        if (lines.join('\n').length > 200000) throw new RangeError('Lapisan teks PDF terlalu panjang.');
      }
      review = parseText(lines.join('\n'), 'pdf_text');
    } catch (error) {
      if (error instanceof RangeError) throw error;
      review = parseText('', 'pdf_text');
    } finally { await loading.destroy(); }
  } else {
    const bitmap = await createImageBitmap(file);
    try {
      if (bitmap.width * bitmap.height > 20000000) throw new Error('Gambar terlalu besar. Maksimal 20 megapiksel.');
      const canvas = document.createElement('canvas'), scale = Math.min(1, 2048 / Math.max(bitmap.width, bitmap.height));
      canvas.width = Math.round(bitmap.width * scale); canvas.height = Math.round(bitmap.height * scale);
      const context = canvas.getContext('2d', { willReadFrequently: true }); if (!context) throw new Error('Pratinjau gambar tidak tersedia.');
      context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
      const jsQR = (await import('jsqr')).default;
      const qr = jsQR(context.getImageData(0, 0, canvas.width, canvas.height).data, canvas.width, canvas.height);
      review = parseText('', 'image');
      if (qr) {
        try {
          const value = parseQR(qr.data); review.source = 'qris';
          review.amount = { value: value.amount, confidence: value.amount ? 'high' : 'low', evidenceSpan: qr.data, sourceType: 'qris' };
          review.merchant = { value: value.merchant, confidence: 'medium', evidenceSpan: value.merchant, sourceType: 'qris' }; review.date.sourceType = 'qris';
        } catch {
          review.amount.evidenceSpan = 'QR tidak didukung atau tidak valid. Isi nominal secara manual.';
        }
      }
    } finally { bitmap.close(); }
  }
  review.fingerprint = await fingerprint(bytes); review.attachmentName = file.name;
  return review;
}
