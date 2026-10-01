<script setup lang="ts">
import { ref } from 'vue';
import { state, client, message } from '../store.ts';
const saving = ref(false), received = ref(false), error = ref('');
const supportEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(import.meta.env.VITE_SUPPORT_EMAIL ?? '') ? import.meta.env.VITE_SUPPORT_EMAIL : '';
async function acknowledge() {
  if (!client || state.mode !== 'authenticated') return;
  saving.value = true; error.value = '';
  try {
    const result = await client.rpc('acknowledge_retention_policy');
    if (result.error) throw result.error;
    received.value = true;
  } catch (cause) { error.value = message(cause); }
  finally { saving.value = false; }
}
</script>
<template>
  <article class="card privacy-copy">
    <h2>Data &amp; privasi</h2><p class="muted">Catatan Anda, kendali Anda.</p>
    <details class="help-disclosure"><summary>Data dan pemrosesan</summary><p>Email, catatan keuangan, dan lampiran digunakan untuk pencatatan, laporan, dan ekspor. Lampiran akun disimpan privat. Saldo merupakan catatan Anda, bukan saldo bank terverifikasi.</p><p>Foto dan halaman PDF struk diproses layanan AI eksternal saat Anda memilih scan atau impor berkas. Pada paket layanan tertentu, data dapat digunakan untuk peningkatan model. Hindari data sensitif. QRIS dan teks yang terbaca dapat diproses lokal; isi manual tetap tersedia.</p></details>
    <details class="help-disclosure"><summary>Sesi dan perangkat</summary><p>Sesi browser disimpan per tab di sessionStorage. Menutup tab menghapus salinan sesi tab, tetapi tidak otomatis mencabut token server. Hanya preferensi tampilan disimpan di localStorage. Perubahan Demo tersimpan selama sesi dan hilang saat dimuat ulang atau direset.</p></details>
    <details class="help-disclosure"><summary>Retensi data</summary><p>Tinjauan ditolak memenuhi syarat penghapusan permanen setelah 30 hari. Tinjauan pending setelah 90 hari hanya dibersihkan bila penerimaan kebijakan tercatat di server, dengan tenggang minimal 7 hari setelah pemberitahuan. Tanpa catatan pemberitahuan, pending tetap disimpan sampai dihapus pengguna.</p><p>Lampiran dibersihkan bersama tinjauan. Bukti yang ditautkan ke transaksi atau split bill tidak ikut dibersihkan. Jika penghapusan berkas gagal, metadata dipertahankan untuk percobaan ulang.</p><p>Pembersihan memerlukan aktivasi operator. Jadwal produksi dan retensi cadangan belum diverifikasi; penghapusan tidak berarti seluruh cadangan penyedia langsung hilang.</p></details>
    <button v-if="state.mode === 'authenticated' && !received" class="secondary" :disabled="saving" @click="acknowledge">{{ saving ? 'Mencatat…' : 'Saya sudah membaca kebijakan retensi' }}</button>
    <p v-if="received" role="status">Penerimaan kebijakan tercatat.</p><p v-if="error" role="alert" class="error-text">{{ error }}</p>
    <details class="help-disclosure"><summary>Ekspor dan penghapusan akun</summary><p>Pengaturan menyediakan ekspor catatan dan lampiran serta penghapusan akun dengan kata sandi dan konfirmasi HAPUS. File ekspor berisi data sensitif. Penghapusan dinyatakan selesai setelah dikonfirmasi server. Demo tidak memiliki akun server.</p></details>
    <details class="help-disclosure"><summary>Tentang Danarapi</summary><p>Danarapi adalah pencatat keuangan, bukan bank atau layanan pembayaran. Pemilik: Rakan Naufal.</p><a v-if="supportEmail" :href="`mailto:${supportEmail}`">Hubungi dukungan</a><p v-else>Kanal dukungan produksi belum tersedia.</p></details>
  </article>
</template>
