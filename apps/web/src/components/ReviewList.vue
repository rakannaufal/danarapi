<script setup lang="ts">
import { ref, computed, nextTick, onBeforeUnmount } from 'vue';
import { state, demo, client, mutate, attachments, upload, message, scanReceiptImages } from '../store.ts';
import { parseFile, parseText, fingerprint, sanitizeImage } from '../import.ts';
import { duplicateCandidates, money, type Review } from '../domain.ts';
import { needsReceiptScan, receiptImagesForFile, reviewFromReceipt } from '../receipt-import.ts';
import { normalizeReceipt, validateReceipt, scanMessages, type ReceiptData } from '../receipt.ts';
import ReceiptScanReview from './ReceiptScanReview.vue';
import Money from './Money.vue';
import Icon from './Icon.vue';
const emit = defineEmits<{ confirm: [review: Review, split: boolean]; undo: [action: () => Promise<void>, label: string] }>();
const text = ref(''), error = ref(''), importing = ref(false), tab = ref('file'), failedUpload = ref<{ id: string; file: File }>();
const reviews = computed(() => state.data.reviewItems.filter(row => row.status === 'pending'));
const preview = ref<{ url: string; name: string; type: string }>();
const editing = ref<string>();
const receiptDetails = computed(() => Object.fromEntries(reviews.value.filter(review => review.receipt).map(review => {
  const receipt = normalizeReceipt(review.receipt);
  return [review.id, { validation: validateReceipt(receipt) }];
})));
const fileInput = ref<HTMLInputElement>();
const cameraInput = ref<HTMLInputElement>();
const scanMode = ref<'receipt' | 'qris'>('receipt');
const fileAccept = ref('image/jpeg,image/png,application/pdf');
async function chooseSource(source: 'gallery' | 'pdf') {
  fileAccept.value = source === 'pdf' ? 'application/pdf' : 'image/jpeg,image/png';
  await nextTick();
  fileInput.value?.click();
}
const phase = ref('Membaca berkas…');
let controller: AbortController | undefined;
function clearPreview() { if (preview.value) URL.revokeObjectURL(preview.value.url); preview.value = undefined; }
onBeforeUnmount(() => { controller?.abort(); clearPreview(); });
function receiptValidation(review: Review) { return receiptDetails.value[review.id]?.validation; }
function receiptMoney(value: string | null) { return value === null ? 'Belum terbaca' : money(value); }
async function saveCorrection(review: Review, receipt: ReceiptData) {
  const corrected = reviewFromReceipt(review, receipt);
  corrected.rawReference = corrected.rawReference?.replace('Data hasil ekstraksi otomatis (bukan transkripsi mentah):', 'Data hasil ekstraksi otomatis, dikoreksi manual (bukan transkripsi mentah):');
  corrected.amount.evidenceSpan = corrected.amount.evidenceSpan?.replace('hasil pembacaan otomatis', 'hasil koreksi manual') ?? null;
  if (await mutate('update_review_item', corrected as unknown as Record<string, unknown>, 'Koreksi struk tersimpan; saldo belum berubah.')) editing.value = undefined;
}
async function extract(file: File, review: Review) {
  controller = new AbortController(); const active = controller;
  phase.value = 'Menyiapkan foto struk…';
  let images;
  try { images = await receiptImagesForFile(file); }
  catch (cause) {
    if (active.signal.aborted) throw cause;
    error.value = `${message(cause)} Bukti tetap tersedia untuk dilengkapi manual.`;
    return review;
  }
  if (active.signal.aborted) throw new DOMException('Scan dibatalkan.', 'AbortError');
  phase.value = 'Membaca struk…';
  let result;
  try { result = await scanReceiptImages(images.map(({ mimeType, data }) => ({ mimeType, data })), active.signal); }
  catch (cause) { if (active.signal.aborted) throw cause; error.value = `${message(cause)} Bukti tetap tersedia untuk dilengkapi manual.`; return review; }
  if (active.signal.aborted) throw new DOMException('Scan dibatalkan.', 'AbortError');
  if (result.data && ['ok', 'not_a_receipt'].includes(result.status)) {
    if (result.status !== 'ok') error.value = scanMessages[result.status];
    return reviewFromReceipt(review, result.data);
  }
  error.value = `${scanMessages[result.status]} Bukti tetap tersedia untuk dilengkapi manual atau dibaca ulang.`;
  return review;
}
async function add(review: Review, file?: File) {
  if (state.data.reviewItems.some(row => row.fingerprint && row.fingerprint === review.fingerprint)) { error.value = 'Sumber yang sama sudah ada di Perlu Ditinjau.'; return; }
  const candidates = duplicateCandidates(state.data, review, ''); review.duplicateCandidateID = candidates[0]?.id ?? null;
  if (await mutate('add_review_item', review as unknown as Record<string, unknown>, 'Hasil impor masuk Perlu Ditinjau; belum menjadi transaksi.')) {
    if (file) { try { await upload(review.id, file); } catch (cause) { failedUpload.value = { id: review.id, file }; error.value = `Review tersimpan, lampiran belum terunggah: ${message(cause)}`; } }
    text.value = '';
  }
}
async function importText() { importing.value = true; error.value = ''; phase.value = 'Membaca teks…'; try { const item = parseText(text.value); item.fingerprint = await fingerprint(new TextEncoder().encode(text.value.normalize('NFKC').trim())); await add(item); } catch (cause) { error.value = message(cause); } finally { importing.value = false; } }
async function importFile(event: Event) {
  const input = event.target as HTMLInputElement, file = input.files?.[0]; if (!file || importing.value) return;
  importing.value = true; error.value = ''; phase.value = 'Membaca berkas…';
  try {
    let review = await parseFile(file);
    if (scanMode.value === 'qris' && review.source !== 'qris') throw new Error('Kode QRIS belum terbaca. Pilih foto QRIS yang utuh dan jelas.');
    const existing = reviews.value.find(row => row.fingerprint === review.fingerprint);
    if (existing?.receipt) { error.value = 'Sumber yang sama sudah ada di Perlu Ditinjau.'; return; }
    if (needsReceiptScan(review)) review = await extract(file, existing ?? review);
    if (existing) { if (review.receipt) await mutate('update_review_item', review as unknown as Record<string, unknown>, 'Hasil ekstraksi diperbarui; saldo belum berubah.'); }
    else await add(review, await sanitizeImage(file));
  } catch (cause) { error.value = cause instanceof Error && cause.name === 'AbortError' ? 'Scan dibatalkan. Unggah ulang atau isi manual.' : message(cause); }
  finally { importing.value = false; controller = undefined; input.value = ''; }
}
async function rescan(review: Review) {
  if (importing.value) return;
  importing.value = true; error.value = '';
  try {
    const file = await attachmentFile(review);
    const result = await extract(file, review);
    if (result !== review) await mutate('update_review_item', result as unknown as Record<string, unknown>, 'Hasil ekstraksi diperbarui; saldo belum berubah.');
  } catch (cause) { error.value = cause instanceof Error && cause.name === 'AbortError' ? 'Scan dibatalkan.' : message(cause); }
  finally { importing.value = false; controller = undefined; }
}
async function importSample(kind: 'pdf' | 'png') {
  importing.value = true; error.value = ''; phase.value = 'Membaca contoh lokal…';
  try {
    const name = kind === 'pdf' ? 'bukti-teks.pdf' : 'qris-sintetis.png';
    const response = await fetch(`${import.meta.env.BASE_URL}demo/${name}`);
    if (!response.ok) throw new Error('Contoh bukti belum tersedia. Coba lagi.');
    const file = new File([await response.blob()], name, { type: kind === 'pdf' ? 'application/pdf' : 'image/png' });
    await add(await parseFile(file), await sanitizeImage(file));
  } catch (cause) { error.value = message(cause); }
  finally { importing.value = false; }
}
async function retryUpload() { if (!failedUpload.value) return; importing.value = true; try { await upload(failedUpload.value.id, failedUpload.value.file); failedUpload.value = undefined; error.value = ''; state.notice = 'Lampiran terunggah.'; } catch (cause) { error.value = message(cause); } finally { importing.value = false; } }
async function reject(review: Review) { if (await mutate('reject_review_item', { id: review.id }, 'Hasil impor ditolak')) emit('undo', async () => { await mutate('restore_review_item', { id: review.id }, 'Hasil impor dipulihkan'); }, 'Hasil impor ditolak'); }
async function merge(review: Review) { if (!review.duplicateCandidateID || !window.confirm('Gabungkan bukti ke catatan yang sudah ada? Tidak membuat transaksi baru.')) return; const bill = state.data.splitBills.some(row => row.id === review.duplicateCandidateID); await mutate('merge_review_item', { id: review.id, ...(bill ? { bill_id: review.duplicateCandidateID } : { transaction_id: review.duplicateCandidateID }) }, 'Bukti digabung; saldo tidak berubah.'); }
async function viewAttachment(review: Review) {
  clearPreview();
  try { const file = await attachmentFile(review); preview.value = { url: URL.createObjectURL(file), name: file.name, type: file.type }; }
  catch (cause) { error.value = message(cause); }
}
async function attachmentFile(review: Review): Promise<File> {
  const file = attachments.get(review.id);
  if (file) return file;
    if (!client) throw new Error('Lampiran contoh tidak memiliki berkas.');
    const { data, error: queryError } = await client.from('attachments').select('storage_key,mime').eq('review_item_id', review.id).limit(1).single(); if (queryError) throw queryError;
    const { data: signed, error: signedError } = await client.storage.from('attachments').createSignedUrl(data.storage_key, 60); if (signedError) throw signedError;
    const response = await fetch(signed.signedUrl); if (!response.ok) throw new Error('Lampiran tidak dapat diunduh.');
    return new File([await response.blob()], review.attachmentName ?? 'Lampiran', { type: data.mime });
}
</script>
<template>
  <section class="import-panel card">
    <div class="section-heading"><div><h2>Impor bukti</h2></div><div class="segmented compact scan-mode" aria-label="Jenis scan"><button :class="{ active: scanMode === 'receipt' }" :aria-pressed="scanMode === 'receipt'" :disabled="importing" @click="scanMode = 'receipt'; error = ''"><Icon name="file" :size="17" />Struk</button><button :class="{ active: scanMode === 'qris' }" :aria-pressed="scanMode === 'qris'" :disabled="importing" @click="scanMode = 'qris'; tab = 'file'; error = ''"><Icon name="qris" :size="17" />QRIS</button></div></div>
    <div v-if="scanMode === 'receipt'" class="segmented compact import-source-tabs"><button :class="{ active: tab === 'file' }" :aria-pressed="tab === 'file'" :disabled="importing" @click="tab = 'file'">Unggah berkas</button><button :class="{ active: tab === 'text' }" :aria-pressed="tab === 'text'" :disabled="importing" @click="tab = 'text'">Tempel teks</button></div>
    <template v-if="tab === 'file'">
      <input ref="fileInput" class="sr-only" type="file" :accept="fileAccept" aria-label="Unggah gambar atau PDF" @change="importFile">
      <input ref="cameraInput" class="sr-only" type="file" accept="image/jpeg,image/png" capture="environment" aria-label="Ambil foto struk atau QRIS" @change="importFile">
      <div class="scan-source-grid" :class="{ 'qris-sources': scanMode === 'qris' }"><button class="scan-source scan-source-camera" :disabled="importing" @click="cameraInput?.click()"><span class="icon-tile sky"><Icon name="camera" :size="25" /></span><strong>Ambil foto</strong><span>Kamera perangkat</span></button><button class="scan-source" :disabled="importing" @click="chooseSource('gallery')"><span class="icon-tile sky"><Icon name="gallery" :size="25" /></span><strong>Galeri</strong><span>JPEG atau PNG</span></button><button v-if="scanMode === 'receipt'" class="scan-source" :disabled="importing" @click="chooseSource('pdf')"><span class="icon-tile sky"><Icon name="file" :size="25" /></span><strong>PDF</strong><span>Pilih berkas struk</span></button></div>
      <p class="scan-file-hint fine-print">{{ scanMode === 'receipt' ? 'JPEG, PNG, PDF' : 'Foto QRIS · JPEG, PNG' }} · Maks. 5 MB</p>
    </template>
    <form v-else class="entry-form" @submit.prevent="importText"><label>Teks bukti<textarea v-model="text" rows="4" maxlength="200000" required placeholder="TOKO DEMO&#10;Total: Rp75.000&#10;30/09/2026"></textarea></label><button class="secondary" :disabled="importing || !text.trim()">{{ importing ? 'Membaca…' : 'Masukkan ke Perlu Ditinjau' }}</button></form>
    <p v-if="importing" role="status">{{ phase }} <button v-if="controller" class="text-button" @click="controller.abort()">Batalkan scan</button></p>
    <div v-if="demo" class="button-row"><button class="text-button" :disabled="importing" @click="importSample('pdf')">Coba contoh PDF</button><button class="text-button" :disabled="importing" @click="importSample('png')">Coba contoh QRIS</button></div>
    
    <p v-if="error" role="alert" class="error-text">{{ error }}</p><button v-if="failedUpload" class="secondary" :disabled="importing" @click="retryUpload">Coba unggah lampiran lagi</button>
  </section>
  <div class="section-heading"><h2>Perlu Ditinjau ({{ reviews.length }})</h2><span class="muted">Belum masuk saldo</span></div>
  <div v-if="!reviews.length" class="empty card"><Icon name="check" :size="40" /><h3>Sudah rapi hari ini</h3><p>Belum ada bukti yang perlu diperiksa.</p><button class="secondary" :disabled="importing" @click="fileInput?.click()">Impor bukti pertama</button></div>
  <div class="review-grid">
    <article v-for="review in reviews" :key="review.id" class="card review-card">
      <div class="section-heading"><span class="icon-tile sun"><Icon :name="review.source === 'qris' ? 'review' : 'file'" /></span><span class="pill sun">{{ ({ qris: 'QRIS', image: 'Gambar', pdf_text: 'PDF', pasted_text: 'Teks' } as Record<string,string>)[review.source] ?? 'Bukti' }}{{ review.receipt ? ' · Struk' : '' }}</span></div>
      <h3>{{ review.merchant.value ?? 'Merchant belum terbaca' }}</h3><p v-if="review.amount.value" class="receipt-total"><Money :amount="review.amount.value" /></p><p v-else class="callout sun">Jumlah belum terbaca. Isi nominal sebelum menyimpan.</p>
      <p class="muted">Tanggal {{ review.date.value ?? 'perlu dilengkapi' }} · keyakinan {{ review.amount.confidence === 'high' ? 'tinggi' : review.amount.confidence === 'medium' ? 'sedang' : 'rendah' }}</p>
      <section v-if="review.receipt" class="extracted-receipt" aria-label="Rincian hasil ekstraksi">
        <h4>Rincian struk · {{ review.receipt.items.length }} barang / menu</h4>
        <div class="receipt-table-wrap" role="region" aria-label="Daftar menu hasil ekstraksi" tabindex="0"><table class="extracted-items"><thead><tr><th>Menu</th><th>Jumlah</th><th>Harga satuan</th><th>Total tercetak</th></tr></thead><tbody><tr v-for="(item, index) in review.receipt.items" :key="index" :class="{ 'receipt-row-warning': receiptValidation(review)?.baris_bermasalah.includes(index) }"><td>{{ item.name || 'Nama belum terbaca' }}<small v-if="item.note">{{ item.note }}</small><small v-if="receiptValidation(review)?.baris_bermasalah.includes(index)" class="error-text">Perlu diperiksa</small></td><td>{{ item.qty.toLocaleString('id-ID') }}</td><td>{{ receiptMoney(item.unit_price) }}</td><td>{{ receiptMoney(item.line_total) }}</td></tr></tbody></table></div>
        <dl class="extracted-costs"><template v-for="cost in ([['subtotal','Subtotal'],['service_charge','Service'],['tax','Pajak'],['discount','Diskon'],['rounding','Pembulatan'],['grand_total','Total struk']] as const)" :key="cost[0]"><dt>{{ cost[1] }}</dt><dd>{{ receiptMoney(review.receipt[cost[0]]) }}</dd></template></dl>
        <button v-if="editing !== review.id" class="secondary" :disabled="state.saving || importing" @click="editing = review.id">Koreksi rincian struk</button>
        <template v-else><ReceiptScanReview :initial-receipt="normalizeReceipt(review.receipt)" apply-label="Simpan koreksi" @apply="saveCorrection(review, $event)" /><button class="text-button" @click="editing = undefined">Batalkan koreksi</button></template>
      </section>
      <details><summary>Lihat asal ekstraksi</summary><p class="fine-print pre-wrap">{{ (review.rawReference || review.amount.evidenceSpan || 'Belum terbaca. Baca ulang atau isi manual.').replace(/Google\s+Gemini|Gemini/gi, 'AI') }}</p></details>
      <p v-if="review.duplicateCandidateID" class="callout sun">Ditemukan transaksi mirip. Periksa sebelum menyimpan.</p>
      <div class="button-row"><button v-if="review.attachmentName" class="text-button" @click="viewAttachment(review)">Lihat lampiran</button><button v-if="review.attachmentName && ['image','pdf_text'].includes(review.source)" class="text-button" :disabled="importing" @click="rescan(review)">Baca ulang</button></div>
      <div class="button-row"><button class="secondary" :disabled="importing" @click="emit('confirm', review, false)">Periksa &amp; simpan</button><button class="text-button" :disabled="importing" @click="emit('confirm', review, true)">Split bill</button><button class="text-button danger-text" :disabled="state.saving || importing" @click="reject(review)">Tolak</button><button v-if="review.duplicateCandidateID" class="text-button" :disabled="state.saving" @click="merge(review)">Gabung</button><button v-if="review.duplicateCandidateID" class="text-button" :disabled="state.saving" @click="mutate('clear_review_duplicate', { id: review.id }, 'Ditandai bukan duplikat')">Bukan duplikat</button></div>
    </article>
  </div>
  <section v-if="preview" class="card attachment-preview"><div class="section-heading"><h3>{{ preview.name }}</h3><button class="icon-button" aria-label="Tutup pratinjau" @click="clearPreview"><Icon name="close" /></button></div><iframe v-if="preview.type === 'application/pdf'" :src="preview.url" title="Pratinjau PDF" sandbox=""></iframe><img v-else :src="preview.url" :alt="'Bukti ' + preview.name"></section>
</template>
<style scoped>
.review-card:has(.extracted-receipt){grid-column:1/-1}.receipt-row-warning{background:var(--sun)}
.receipt-total{font-size:26px;font-weight:700;margin:12px 0}.extracted-receipt{margin:20px 0;min-width:0}.extracted-receipt h4{margin:0 0 12px}.receipt-table-wrap{overflow-x:auto}.extracted-items{width:100%;border-collapse:collapse;font-size:13px}.extracted-items th,.extracted-items td{padding:10px 6px;border-bottom:1px solid var(--line);text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}.extracted-items th:first-child,.extracted-items td:first-child{text-align:left;white-space:normal;min-width:120px}.extracted-items small{display:block;color:var(--muted);margin-top:4px}.extracted-costs{display:grid;grid-template-columns:1fr auto;gap:8px;margin:16px 0;font-size:14px}.extracted-costs dd{margin:0;text-align:right;font-variant-numeric:tabular-nums}.extracted-costs dt:last-of-type,.extracted-costs dd:last-of-type{font-weight:700}.review-card{min-width:0}
</style>
