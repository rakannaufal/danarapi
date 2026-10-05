export type ReceiptItem = { name: string; qty: number; unit_price: number | null; line_total: number | null; note: string | null };
export type ReceiptData = { merchant: string | null; date: string | null; items: ReceiptItem[]; subtotal: number | null; service_charge: number | null; tax: number | null; discount: number; rounding: number; grand_total: number | null; tax_included_in_price: boolean; unreadable_fields: string[] };
type ReceiptMoneyKey = 'subtotal' | 'service_charge' | 'tax' | 'discount' | 'rounding' | 'grand_total';
export type StoredReceipt = Omit<ReceiptData, ReceiptMoneyKey | 'items'> & { [key in ReceiptMoneyKey]: string | null } & { items: (Omit<ReceiptItem, 'unit_price' | 'line_total'> & { unit_price: string | null; line_total: string | null })[] };
export function storeReceipt(data: ReceiptData): StoredReceipt {
  const decimal = (value: number | null) => value === null ? null : String(value);
  return { ...data, items: data.items.map(item => ({ ...item, unit_price: decimal(item.unit_price), line_total: decimal(item.line_total) })), subtotal: decimal(data.subtotal), service_charge: decimal(data.service_charge), tax: decimal(data.tax), discount: decimal(data.discount), rounding: decimal(data.rounding), grand_total: decimal(data.grand_total) };
}
export type ReceiptIssue = { cek: number; pesan: string; selisih?: number; baris?: number };
export type ReceiptValidation = { lolos: boolean; masalah: ReceiptIssue[]; peringatan: string[]; baris_bermasalah: number[] };
export type ScanStatus = 'ok' | 'quota_exceeded' | 'service_error' | 'config_error' | 'no_result' | 'not_a_receipt' | 'busy' | 'invalid_image';
export type ScanResult = { status: ScanStatus; data?: ReceiptData; validasi?: ReceiptValidation; cached?: boolean; proof?: import('./bank-proof.ts').BankProof };
export const scanMessages: Record<ScanStatus, string> = { ok: 'Struk terbaca. Periksa semua angka sebelum melanjutkan.', quota_exceeded: 'Kuota scan habis. Coba besok atau isi manual.', service_error: 'Layanan pembaca struk sedang bermasalah. Isi manual tetap tersedia.', config_error: 'Scan belum dikonfigurasi. Isi manual atau hubungi pengelola.', no_result: 'Struk belum dapat dibaca. Foto ulang dengan cahaya cukup atau isi manual.', not_a_receipt: 'Menu tidak ditemukan. Pilih foto struk yang lengkap atau isi manual.', busy: 'Scan sedang diproses. Tunggu sebentar, lalu coba lagi.', invalid_image: 'Pilih maksimal tiga gambar JPEG, PNG atau WebP, total maksimal 4 MB.' };

function object(value: unknown): Record<string, unknown> { return typeof value === 'object' && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : {}; }
export function normalizeAmount(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const cleaned = typeof value === 'string' ? value.replace(/rp/gi, '').replace(/[\s.,]/g, '') : value;
  if (typeof cleaned !== 'number' && (typeof cleaned !== 'string' || !/^-?\d+$/.test(cleaned))) return null;
  const number = Number(cleaned);
  return Number.isSafeInteger(number) && Math.abs(number) <= 999999999999 ? number : null;
}
function cleanText(value: unknown, maximum: number): string | null { return typeof value === 'string' ? value.replace(/\s+/g, ' ').trim().slice(0, maximum) || null : null; }
export function normalizeReceipt(raw: unknown): ReceiptData {
  const source = object(raw);
  const unreadable = Array.isArray(source.unreadable_fields) ? source.unreadable_fields.filter((value): value is string => typeof value === 'string').slice(0, 200).map(value => value.slice(0, 160)) : [];
  function amount(value: unknown, field: string, signed = false): number | null {
    const number = normalizeAmount(value);
    if (number === null || (!signed && number < 0)) { unreadable.push(field); return null; }
    return number;
  }
  const items = (Array.isArray(source.items) ? source.items : []).slice(0, 100).map((rawItem, index) => {
    const item = object(rawItem);
    let name = cleanText(item.name, 160) ?? '';
    if (name === name.toLocaleUpperCase('id-ID')) name = name.toLocaleLowerCase('id-ID').replace(/(^|\s)\p{L}/gu, value => value.toLocaleUpperCase('id-ID'));
    const rawQuantity = normalizeAmount(item.qty);
    const qty = rawQuantity ?? 1;
    if (rawQuantity === null || rawQuantity < 1 || rawQuantity > 999999) unreadable.push(`items[${index}].qty`);
    const lineTotal = amount(item.line_total, `items[${index}].line_total`);
    let unitPrice = normalizeAmount(item.unit_price);
    if (unitPrice === null && lineTotal !== null && qty > 0 && qty <= 999999) unitPrice = Math.round(lineTotal / qty);
    if (unitPrice === null || unitPrice < 0) { unitPrice = null; unreadable.push(`items[${index}].unit_price`); }
    if (!name) unreadable.push(`items[${index}].name`);
    return { name, qty, unit_price: unitPrice, line_total: lineTotal, note: cleanText(item.note, 500) };
  });
  const date = cleanText(source.date, 10);
  const validDate = date !== null && /^\d{4}-\d{2}-\d{2}$/.test(date) && Number.isFinite(Date.parse(`${date}T00:00:00Z`)) && new Date(`${date}T00:00:00Z`).toISOString().slice(0, 10) === date;
  if (date && !validDate) unreadable.push('date');
  const discount = amount(source.discount ?? 0, 'discount', true);
  const rounding = amount(source.rounding ?? 0, 'rounding', true);
  if (typeof source.tax_included_in_price !== 'boolean') unreadable.push('tax_included_in_price');
  return { merchant: cleanText(source.merchant, 160), date: validDate ? date : null, items, subtotal: amount(source.subtotal, 'subtotal'), service_charge: source.service_charge == null ? null : amount(source.service_charge, 'service_charge'), tax: source.tax == null ? null : amount(source.tax, 'tax'), discount: Math.abs(discount ?? 0), rounding: rounding ?? 0, grand_total: amount(source.grand_total, 'grand_total'), tax_included_in_price: source.tax_included_in_price === true, unreadable_fields: [...new Set(unreadable)] };
}

export function validateReceipt(data: ReceiptData, tolerance = 100): ReceiptValidation {
  const masalah: ReceiptIssue[] = [];
  const peringatan: string[] = [];
  const bad = new Set<number>();
  const rupiah = (amount: number) => `Rp ${Math.abs(amount).toLocaleString('id-ID')}`;
  data.items.forEach((item, index) => {
    const missing = !item.name.trim() || !Number.isInteger(item.qty) || item.qty < 1 || item.qty > 999999 || item.unit_price === null || item.line_total === null;
    const difference = missing ? 0 : item.qty * item.unit_price! - item.line_total!;
    if (missing || Math.abs(difference) > tolerance || data.unreadable_fields.some(field => field.startsWith(`items[${index}]`))) {
      const label = item.name || `Barang ${index + 1}`;
      masalah.push({ cek: 1, baris: index, pesan: missing ? `${label}: nama, jumlah atau harga belum valid (jumlah 1–999.999).` : `${label}: ${item.qty.toLocaleString('id-ID')} × ${rupiah(item.unit_price!)} = ${rupiah(item.qty * item.unit_price!)}, tetapi total baris tercetak ${rupiah(item.line_total!)} (selisih ${rupiah(difference)}).`, selisih: difference }); bad.add(index);
    }
  });
  if (!data.items.length) masalah.push({ cek: 1, pesan: 'Belum ada menu.' });
  const sum = data.items.reduce((total, item) => total + (item.line_total ?? 0), 0);
  if (data.subtotal !== null && Math.abs(sum - data.subtotal) > tolerance) masalah.push({ cek: 2, pesan: `Jumlah menu ${rupiah(sum)}, subtotal struk ${rupiah(data.subtotal)} (selisih ${rupiah(sum - data.subtotal)}).`, selisih: sum - data.subtotal });
  if (data.grand_total !== null) {
    const base = data.tax_included_in_price ? sum : data.subtotal;
    if (base === null) masalah.push({ cek: 3, pesan: 'Subtotal belum terbaca; isi dari struk.' });
    else {
      const expected = base + (data.tax_included_in_price ? 0 : (data.service_charge ?? 0) + (data.tax ?? 0)) - data.discount + data.rounding;
      if (Math.abs(expected - data.grand_total) > tolerance) masalah.push({ cek: 3, pesan: `Total hitungan ${rupiah(expected)}, total struk ${rupiah(data.grand_total)} (selisih ${rupiah(expected - data.grand_total)}).`, selisih: expected - data.grand_total });
    }
  }
  if (data.unreadable_fields.length) {
    const labels: Record<string, string> = { qty: 'jumlah', name: 'nama', unit_price: 'harga satuan', line_total: 'total baris', merchant: 'nama toko', date: 'tanggal', subtotal: 'subtotal', grand_total: 'total struk', service_charge: 'service', tax: 'pajak', discount: 'diskon', rounding: 'pembulatan', tax_included_in_price: 'status pajak termasuk harga' };
    const fields = data.unreadable_fields.map(field => {
      const match = /^items\[(\d+)\]\.(\w+)$/.exec(field);
      return match ? `${data.items[Number(match[1])]?.name || `Barang ${Number(match[1]) + 1}`}: ${labels[match[2]!] ?? match[2]}` : labels[field] ?? field;
    });
    peringatan.push(`Periksa bagian belum terbaca: ${fields.join('; ')}.`);
  }
  if (data.grand_total === null) peringatan.push('Total struk belum terbaca. Isi untuk mencocokkan tagihan.');
  for (const [label, value] of [['Service', data.service_charge], ['Pajak', data.tax]] as const) {
    if (data.subtotal && value !== null && (value / data.subtotal < 0 || value / data.subtotal > .25)) peringatan.push(`${label} di luar rentang wajar 0–25%.`);
  }
  return { lolos: masalah.length === 0, masalah, peringatan, baris_bermasalah: [...bad] };
}
