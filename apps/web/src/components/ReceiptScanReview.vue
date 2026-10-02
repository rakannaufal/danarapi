<script setup lang="ts">
import MoneyInput from './MoneyInput.vue';
import { computed, onBeforeUnmount, ref } from 'vue';
import { normalizeReceipt, validateReceipt, scanMessages, type ReceiptData } from '../receipt.ts';
import { scanReceiptImages } from '../store.ts';
import { compressReceiptImage } from '../receipt-image.ts';
const emit = defineEmits<{ apply: [data: ReceiptData]; dirty: [] }>();
const props = defineProps<{ initialReceipt?: ReceiptData; applyLabel?: string }>();
const busy = ref(false); const message = ref(''); const receipt = ref<ReceiptData | undefined>(props.initialReceipt ? normalizeReceipt(props.initialReceipt) : undefined); const previews = ref<string[]>([]); const zoom = ref(false); const visible = ref(!!props.initialReceipt);
let controller: AbortController | undefined; let generation = 0;
const normalized = computed(() => receipt.value ? normalizeReceipt(receipt.value) : null);
const validation = computed(() => normalized.value ? validateReceipt(normalized.value) : null);
const costs = [{ key: 'subtotal', label: 'Subtotal struk' }, { key: 'service_charge', label: 'Service (Rp)' }, { key: 'tax', label: 'Pajak (Rp)' }, { key: 'discount', label: 'Diskon (Rp)' }, { key: 'rounding', label: 'Pembulatan (Rp)' }, { key: 'grand_total', label: 'Total struk' }] as const;
function clearImages() { for (const preview of previews.value) URL.revokeObjectURL(preview); previews.value = []; }
function cancel() { generation++; controller?.abort(); busy.value = false; message.value = 'Scan dibatalkan. Isi manual tetap tersedia.'; }
function manual() { cancel(); clearImages(); receipt.value = undefined; visible.value = false; }
function corrected(field: string) { if (receipt.value) receipt.value.unreadable_fields = receipt.value.unreadable_fields.filter(value => value !== field); emit('dirty'); }
async function scan(event: Event) {
  const input = event.target as HTMLInputElement; const files = [...(input.files ?? [])]; input.value = '';
  if (!files.length) return;
  if (files.length > 3) { message.value = scanMessages.invalid_image; return; }
  cancel(); const current = generation; clearImages(); receipt.value = undefined; busy.value = true; message.value = ''; visible.value = true; controller = new AbortController();
  try {
    const images = await Promise.all(files.map(compressReceiptImage));
    if (current !== generation) return;
    previews.value = images.map(image => URL.createObjectURL(image.preview));
    const result = await scanReceiptImages(images.map(({ mimeType, data }) => ({ mimeType, data })), controller.signal);
    if (current !== generation) return;
    message.value = scanMessages[result.status] ?? scanMessages.service_error;
    if (result.status === 'ok' && result.data) { receipt.value = normalizeReceipt(result.data); emit('dirty'); }
  } catch (error) { if (current === generation) message.value = error instanceof Error ? error.message : scanMessages.service_error; }
  finally { if (current === generation) busy.value = false; }
}
function proceed() {
  if (!normalized.value) return;
  if (!validation.value?.lolos && !window.confirm('Data struk belum cocok. Lanjut dengan angka yang sudah Anda periksa? Hitungan akhir tetap perlu dicocokkan dengan struk.')) return;
  emit('apply', normalized.value); receipt.value = undefined; clearImages(); visible.value = false; message.value = '';
}
onBeforeUnmount(() => { cancel(); clearImages(); });
</script>
<template>
  <section class="scan-card" aria-label="Scan dan review struk">
    <h3>Pindai struk</h3><div class="scan-actions"><label class="scan-upload">Foto struk<input type="file" accept="image/jpeg,image/png,image/webp" capture="environment" :disabled="busy" @change="scan"></label><label class="scan-upload">Pilih dari galeri<input type="file" accept="image/jpeg,image/png,image/webp" multiple :disabled="busy" @change="scan"></label><button type="button" class="secondary" @click="manual">Isi manual</button></div><p v-if="busy" role="status">Membaca struk… <button type="button" class="secondary" @click="cancel">Batal</button></p><p v-if="message" role="status">{{ message }}</p>
    <div v-if="visible && previews.length" class="scan-previews" :class="{ zoom }"><button v-for="preview in previews" :key="preview" type="button" :aria-label="zoom ? 'Perkecil foto struk' : 'Perbesar foto struk'" @click="zoom = !zoom"><img :src="preview" alt="Foto struk untuk diperiksa"></button></div>
    <div v-if="receipt" class="scan-review">
      <h3>Periksa hasil scan</h3><div class="form-grid"><label>Nama toko<input v-model="receipt.merchant" maxlength="160" @input="corrected('merchant')"></label><label>Tanggal struk<input v-model="receipt.date" type="date" @input="corrected('date')"></label></div>
      <div v-for="(item, index) in receipt.items" :key="index" class="scan-line" :class="{ problematic: validation?.baris_bermasalah.includes(index) }"><strong>Menu {{ index + 1 }}{{ validation?.baris_bermasalah.includes(index) ? ' · Perlu diperiksa' : '' }}</strong><label>Nama<input v-model="item.name" maxlength="160" @input="corrected(`items[${index}].name`)"></label><div class="scan-numbers"><label>Qty<input v-model.number="item.qty" type="number" min="1" max="999999" @input="corrected(`items[${index}].qty`)"></label><label>Harga satuan<MoneyInput v-model="item.unit_price" numeric @input="corrected(`items[${index}].unit_price`)" /></label><label>Total baris<MoneyInput v-model="item.line_total" numeric @input="corrected(`items[${index}].line_total`)" /></label></div><label>Catatan menu<input v-model="item.note" maxlength="500"></label><button type="button" class="secondary" @click="receipt.items.splice(index, 1); receipt.unreadable_fields = receipt.unreadable_fields.filter(field => !field.startsWith('items[')); emit('dirty')">Hapus baris</button></div><button type="button" class="secondary" :disabled="receipt.items.length >= 100" @click="receipt.items.push({ name: '', qty: 1, unit_price: null, line_total: null, note: null })">Tambah baris</button>
      <div class="form-grid scan-costs"><label v-for="cost in costs" :key="cost.key">{{ cost.label }}<MoneyInput v-model="receipt[cost.key]" numeric :signed="cost.key === 'rounding'" @input="corrected(cost.key)" /></label></div><label class="checkbox"><input v-model="receipt.tax_included_in_price" type="checkbox" @change="corrected('tax_included_in_price')">Harga sudah termasuk pajak dan service</label>
      <details v-if="validation && (!validation.lolos || validation.peringatan.length)" class="scan-validation"><summary>Perlu dikoreksi</summary><p v-for="(issue, index) in validation.masalah" :key="index">{{ issue.pesan }}</p><p v-for="warning in validation.peringatan" :key="warning">{{ warning }}</p></details><button type="button" class="primary" @click="proceed">{{ props.applyLabel ?? (validation?.lolos ? 'Lanjut pilih pemesan' : 'Lanjut, saya sudah memeriksa') }}</button>
    </div>
  </section>
</template>
<style scoped>
.scan-card{--receipt-card:var(--surface);--receipt-ink:var(--ink);--receipt-mute:var(--muted);--receipt-line:var(--border);--receipt-acc:var(--primary);--receipt-bg:var(--on-primary);padding:20px;border:1px dashed var(--receipt-line);border-radius:16px;background:var(--receipt-card);min-width:0}.scan-card h3{font-size:17px;margin:0 0 10px}.scan-card p{font-size:14px;line-height:1.6;color:var(--receipt-mute)}.scan-actions{display:flex;gap:10px;flex-wrap:wrap}.scan-upload{position:relative;padding:12px 16px;border:1px solid var(--receipt-line);border-radius:12px;min-height:44px;cursor:pointer;color:var(--receipt-ink);font-weight:600}.scan-upload input{position:absolute;inset:0;opacity:0;cursor:pointer;width:100%}.scan-upload:focus-within{outline:2px solid var(--receipt-acc);outline-offset:3px}.scan-previews{display:flex;gap:8px;overflow:auto;margin:16px 0;max-height:220px}.scan-previews button{flex:0 0 auto;background:transparent;padding:0;max-width:100%}.scan-previews img{max-height:200px;max-width:100%;object-fit:contain}.scan-previews.zoom{max-height:600px;display:block}.scan-previews.zoom img{max-height:none;width:100%}.scan-review{display:grid;gap:16px;margin-top:20px}.scan-line{display:grid;gap:12px;padding:16px 0;border-bottom:1px dashed var(--receipt-line)}.scan-numbers{display:grid;grid-template-columns:80px 1fr 1fr;gap:10px}.problematic{border-left:3px solid #b42318;padding-left:12px}.scan-validation{padding:14px;border:1px solid #b42318;border-radius:12px;color:#b42318}.scan-validation.valid{border-color:var(--receipt-acc);color:var(--receipt-acc)}.scan-validation p{color:inherit}.scan-card label{display:flex;flex-direction:column;gap:6px;font-size:14px}.scan-card .checkbox{flex-direction:row;align-items:center}.scan-card .checkbox input{width:18px}.scan-card input{min-width:0;width:100%;background:var(--receipt-card);color:var(--receipt-ink);border-color:var(--field-border)}.scan-card .primary{background:var(--receipt-acc);color:var(--receipt-bg)}.scan-card .secondary{background:transparent;border-color:var(--receipt-line);color:var(--receipt-ink)}
:global([data-theme='dark'] .scan-validation:not(.valid)){color:#ff8a7a;border-color:#ff8a7a}
@media(max-width:600px){.scan-numbers{grid-template-columns:1fr 1fr}.scan-numbers>label:first-child{grid-column:1/-1}.scan-card{padding:16px}}
</style>
