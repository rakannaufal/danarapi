import type { Field, Review } from './domain.ts';
import { normalizeReceipt, storeReceipt, validateReceipt, type ReceiptData } from './receipt.ts';
import { compressReceiptImage } from './receipt-image.ts';
import { validateFile } from './import.ts';

export function needsReceiptScan(review: Review) { return review.source === 'image' || review.source === 'pdf_text'; }
export function reviewFromReceipt(review: Review, raw: ReceiptData): Review {
  const data = normalizeReceipt(raw), validation = validateReceipt(data);
  const amount = (value: number | null) => value === null ? 'Belum terbaca' : `Rp ${value.toLocaleString('id-ID')}`;
  const lines = [data.merchant ?? 'Toko belum terbaca', `Tanggal: ${data.date ?? 'Belum terbaca'}`, ...data.items.map(item => `${item.name} · ${item.qty} × ${amount(item.unit_price)} = ${amount(item.line_total)}${item.note ? ` (${item.note})` : ''}`), `Subtotal: ${amount(data.subtotal)}`, `Service: ${amount(data.service_charge)}`, `Pajak: ${amount(data.tax)}`, `Diskon: ${amount(data.discount)}`, `Pembulatan: ${amount(data.rounding)}`, `Total: ${amount(data.grand_total)}`];
  const field = (value: string | null, evidenceSpan: string, high = false): Field => ({ value, confidence: value === null ? 'low' : high ? 'high' : 'medium', evidenceSpan, sourceType: review.source });
  return { ...review, receipt: storeReceipt(data), amount: field(data.grand_total === null ? null : String(data.grand_total), `Total struk: ${amount(data.grand_total)} · hasil pembacaan otomatis, periksa foto.`, validation.lolos), merchant: field(data.merchant, data.merchant ?? 'Nama toko belum terbaca.'), date: field(data.date, `Tanggal tercetak: ${data.date ?? 'Belum terbaca'}`), rawReference: `Data hasil ekstraksi otomatis (bukan transkripsi mentah):\n${lines.join('\n')}` };
}
export async function receiptImagesForFile(file: File) {
  const { bytes, isPDF } = await validateFile(file);
  if (!isPDF) return [await compressReceiptImage(file)];
  const pdf = await import('pdfjs-dist');
  pdf.GlobalWorkerOptions.workerSrc = (await import('pdfjs-dist/build/pdf.worker.min.mjs?url')).default;
  const loading = pdf.getDocument({ data: bytes.slice(), stopAtErrors: true, enableXfa: false });
  try {
    const documentPDF = await loading.promise;
    if (documentPDF.numPages > 3) throw new Error('Scan PDF maksimal tiga halaman. Pisahkan halaman struk lalu unggah ulang.');
    const images = [];
    for (let index = 1; index <= documentPDF.numPages; index++) {
      const page = await documentPDF.getPage(index), original = page.getViewport({ scale: 1 });
      const viewport = page.getViewport({ scale: Math.min(2, 1600 / Math.max(original.width, original.height)) });
      const canvas = document.createElement('canvas'); canvas.width = Math.ceil(viewport.width); canvas.height = Math.ceil(viewport.height);
      await page.render({ canvas, viewport }).promise;
      const blob = await new Promise<Blob>((resolve, reject) => canvas.toBlob(value => value ? resolve(value) : reject(new Error('Halaman PDF tidak dapat dirender.')), 'image/jpeg', .9));
      images.push(await compressReceiptImage(new File([blob], `halaman-${index}.jpg`, { type: 'image/jpeg' })));
      page.cleanup();
    }
    return images;
  } finally { await loading.destroy(); }
}
