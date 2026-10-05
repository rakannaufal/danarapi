<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue';
import { attachments, client, state, uploadPosted, message } from '../store.ts';
import { validateFile, sanitizeImage } from '../import.ts';
const props = defineProps<{ kind: 'transaction' | 'bill'; targetID: string }>();
const rows = ref<{ id: string; name: string; mime: string; storageKey?: string; file?: File }[]>([]);
const loading = ref(false), saving = ref(false), error = ref(''), preview = ref<{ url: string; name: string; mime: string }>();
function closePreview() { if (preview.value) URL.revokeObjectURL(preview.value.url); preview.value = undefined; }
onBeforeUnmount(closePreview);
async function load() {
  loading.value = true; error.value = '';
  try {
    if (state.mode === 'demo') rows.value = [...attachments].filter(([key]) => key.startsWith(`${props.kind}:${props.targetID}:`)).map(([key, file]) => ({ id: key, name: file.name, mime: file.type, file }));
    else {
      if (!client) throw new Error('Sesi diperlukan.');
      const result = await client.from('attachments').select('id,storage_key,mime').eq(props.kind === 'transaction' ? 'transaction_id' : 'split_bill_id', props.targetID).order('created_at');
      if (result.error) throw result.error;
      rows.value = result.data.map(row => ({ id: row.id, name: `Bukti ${row.id.slice(0, 8)}`, mime: row.mime, storageKey: row.storage_key }));
    }
  } catch (cause) { error.value = message(cause); }
  finally { loading.value = false; }
}
onMounted(load);
async function add(event: Event) {
  const input = event.target as HTMLInputElement, file = input.files?.[0];
  if (!file) return;
  saving.value = true; error.value = '';
  try {
    await validateFile(file);
    await uploadPosted(props.kind, props.targetID, await sanitizeImage(file));
    await load(); state.notice = 'Lampiran tersimpan; nominal dan saldo tidak berubah.';
  } catch (cause) { error.value = message(cause); }
  finally { saving.value = false; input.value = ''; }
}
async function view(row: typeof rows.value[number]) {
  closePreview(); error.value = '';
  try {
    let blob: Blob | undefined = row.file;
    if (!blob) {
      if (!client || !row.storageKey) throw new Error('Lampiran tidak tersedia.');
      const result = await client.storage.from('attachments').download(row.storageKey);
      if (result.error) throw result.error;
      blob = result.data;
    }
    preview.value = { url: URL.createObjectURL(blob), name: row.name, mime: row.mime };
  } catch (cause) { error.value = message(cause); }
}
async function remove(row: typeof rows.value[number]) {
  if (!window.confirm(`Hapus lampiran ${row.name}? Catatan transaksi dan saldo tetap tersimpan.`)) return;
  saving.value = true; error.value = '';
  try {
    if (state.mode === 'demo') attachments.delete(row.id);
    else {
      if (!client || !row.storageKey) throw new Error('Lampiran tidak tersedia.');
      const removed = await client.storage.from('attachments').remove([row.storageKey]);
      if (removed.error) throw removed.error;
      const deleted = await client.from('attachments').delete().eq('id', row.id).select('id');
      if (deleted.error) throw deleted.error;
      if (!deleted.data.length) throw new Error('Lampiran berubah. Muat ulang sebelum menghapus.');
    }
    closePreview(); await load(); state.notice = 'Lampiran dihapus; saldo tidak berubah.';
  } catch (cause) { error.value = message(cause); }
  finally { saving.value = false; }
}
</script>
<template><section class="entry-form attachment-panel"><h3>Lampiran bukti</h3><p class="fine-print">Berkas ditautkan ke catatan ini. Tidak mengekstrak atau mengubah transaksi. JPEG, PNG, PDF; maksimal 5 MB.</p><p v-if="loading" role="status">Memuat lampiran…</p><p v-else-if="!rows.length" class="muted">Belum ada lampiran.</p><div v-for="row in rows" :key="row.id" class="button-row"><button type="button" class="secondary" @click="view(row)">Lihat {{ row.name }}</button><button type="button" class="text-button danger-text" :disabled="saving || loading || (state.mode !== 'demo' && !state.online)" @click="remove(row)">Hapus lampiran</button></div><label>Tambahkan lampiran<input type="file" accept="image/jpeg,image/png,application/pdf" :disabled="saving || loading || (state.mode !== 'demo' && !state.online)" @change="add"></label><p v-if="saving" role="status">Menyimpan lampiran…</p><p v-if="error" role="alert" class="error-text">{{ error }}</p><button v-if="error && !saving" class="secondary" type="button" @click="load">Muat ulang lampiran</button><section v-if="preview" class="attachment-preview"><div class="section-heading"><h4>{{ preview.name }}</h4><button class="secondary" type="button" @click="closePreview">Tutup pratinjau</button></div><iframe v-if="preview.mime === 'application/pdf'" :src="preview.url" title="Pratinjau PDF" sandbox=""></iframe><img v-else :src="preview.url" :alt="`Bukti ${preview.name}`"></section></section></template>
