<script setup lang="ts">
import MoneyInput from './MoneyInput.vue';
import { ref, reactive, computed } from 'vue';
import { state, client, mutate, mutation, preferences, setTheme, today, resetDemo, logout, exportRemote, attachments, message, saveTimezone } from '../store.ts';
import { demoArchive, download } from '../export.ts';
import { id, type Account, type Category, type MerchantRule, normalize } from '../domain.ts';
import { fromZonedTime } from '../timezone.ts';
import { parseSignedMoney } from '../contracts.ts';
import Icon from './Icon.vue';
import Money from './Money.vue';
const emit = defineEmits<{ privacy: []; transfer: []; navigate: [page: string]; dirty: [value: boolean] }>();
const props = defineProps<{ initialPanel?: string; standalone?: boolean }>();
const panel = ref(sessionStorage.getItem('danarapi.deletion.owner') ? 'privacy' : props.initialPanel ?? 'preferences'), editor = ref(''), busy = ref(false), error = ref(''), deletion = ref(''), existing = ref<Account | Category>();
const form = reactive({ name: '', kind: 'cash', amount: '0', date: today(), order: '0', reason: '' });
const rule = reactive({ pattern: '', category: '', match: 'contains' });
const categories = computed(() => state.data.categories.filter(row => !row.archived && row.kind === 'expense'));
const accountKinds: Record<string, string> = { cash: 'Tunai', bank: 'Bank', ewallet: 'E-wallet', other: 'Lainnya' };
const panels = [
  { id: 'preferences', title: 'Preferensi', icon: 'settings', color: 'mint', description: 'Tampilan dan sesi' },
  { id: 'accounts', title: 'Akun', icon: 'wallet', color: 'sky', description: 'Saldo dan rekening' },
  { id: 'categories', title: 'Kategori', icon: 'budget', color: 'peach', description: 'Catatan dan merchant' },
  { id: 'privacy', title: 'Data & privasi', icon: 'file', color: 'sun', description: 'Ekspor dan akun' },
];
function edit(type: string, item?: Account | Category) { editor.value = type; existing.value = item; form.name = item?.name ?? ''; form.kind = item?.kind ?? (type === 'account' ? 'cash' : 'expense'); form.amount = item && 'openingBalance' in item ? item.balance : '0'; form.date = item && 'openedAt' in item ? item.openedAt.slice(0,10) : today(); form.order = item && 'sortOrder' in item ? String(item.sortOrder) : String(state.data.categories.length); form.reason = ''; error.value = ''; }
async function save() {
  error.value = '';
  try {
    if (editor.value === 'account') parseSignedMoney(form.amount);
    const payload = editor.value === 'account' ? existing.value ? { ...mutation(), p_account_id: existing.value.id, p_expected_version: existing.value.version, p_expected_balance: (existing.value as Account).balance, p_name: form.name, p_kind: form.kind, p_balance: form.amount, p_reason: form.reason.trim() || 'Koreksi saldo akun' } : { ...mutation(), p_name: form.name, p_kind: form.kind, p_opening_balance: form.amount, p_opened_at: fromZonedTime(form.date, state.timezone) } : existing.value ? { ...existing.value, name: form.name, sortOrder: Number(form.order) } : { ...mutation(), p_name: form.name, p_kind: form.kind, p_sort_order: Number(form.order) };
    if (await mutate(editor.value === 'account' && existing.value ? 'edit_financial_account' : `${existing.value ? 'update' : 'create'}_${editor.value}`, payload)) editor.value = '';
  } catch (cause) { error.value = message(cause); }
}
async function removeRecord(type: string, item: Account | Category) {
  if (!window.confirm(`Hapus ${item.name}? Data tanpa riwayat dihapus permanen. Data yang sudah dipakai diarsipkan agar riwayat dan saldo tetap akurat.`)) return;
  if (await mutate('delete_financial_record', { ...mutation(), p_entity: type, p_id: item.id, p_expected_version: item.version }, 'Data dihapus dari daftar aktif; riwayat tetap tersimpan.')) {
    if (existing.value?.id === item.id) { editor.value = ''; existing.value = undefined; }
  }
}
async function removeRule(item: MerchantRule) {
  if (window.confirm(`Hapus aturan merchant ${item.normalizedPattern}? Transaksi yang sudah tercatat tidak berubah.`)) await mutate('delete_merchant_rule', { id: item.id, expected_version: item.version }, 'Aturan merchant dihapus');
}
async function exportAll() {
  if (!window.confirm('Ekspor penuh berisi informasi sensitif, termasuk lampiran. Simpan dan bagikan hanya di tempat aman.')) return;
  busy.value = true; error.value = '';
  try { const archive = state.mode === 'demo' ? await demoArchive(state.data, attachments) : await exportRemote(); download(state.mode === 'demo' ? 'danarapi-demo.zip' : 'danarapi-export.zip', archive); state.notice = state.mode === 'demo' ? 'Data contoh diunduh, bukan data server.' : 'Ekspor penuh diunduh.'; } catch (cause) { error.value = message(cause); } finally { busy.value = false; }
}
async function reauthenticate(provider: 'google') {
  if (!client) return;
  const { data: { session } } = await client.auth.getSession();
  if (!session) return;
  sessionStorage.setItem('danarapi.deletion.owner', session.user.id);
  const { error: failure } = await client.auth.signInWithOAuth({ provider, options: { redirectTo: window.location.origin + window.location.pathname + '#settings', queryParams: { prompt: 'select_account' } } });
  if (failure) { sessionStorage.removeItem('danarapi.deletion.owner'); error.value = message(failure); }
}
async function deleteAccount() {
  if (state.mode === 'demo') { error.value = 'Mode Demo tidak memiliki akun server untuk dihapus.'; return; }
  if (!client || deletion.value !== 'HAPUS' || !window.confirm('Data Anda akan dihapus permanen setelah proses selesai. Akun, catatan, dan lampiran tidak dapat dipulihkan melalui aplikasi. Lanjutkan?')) return;
  busy.value = true; error.value = '';
  try {
    const expectedOwner = sessionStorage.getItem('danarapi.deletion.owner');
    const { data: { session } } = await client.auth.getSession();
    if (!expectedOwner || session?.user.id !== expectedOwner) throw new Error('Konfirmasi Google dengan akun yang sama terlebih dahulu.');
    if (await mutate('request_account_deletion', { expected_user_id: sessionStorage.getItem('danarapi.deletion.owner') }, 'Penghapusan selesai')) { await client.auth.signOut({ scope: 'local' }); await logout(); sessionStorage.removeItem('danarapi.deletion.owner'); state.notice = 'Penghapusan akun selesai dan dikonfirmasi server.'; }
  } catch (cause) { error.value = message(cause); } finally { busy.value = false; }
}
async function addRule() { if (!normalize(rule.pattern) || !rule.category) return; if (await mutate('save_merchant_rule', { id: id(), matchType: rule.match, normalizedPattern: normalize(rule.pattern), categoryID: rule.category, priority: 10, version: 0 })) rule.pattern = ''; }
</script>
<template>
  <div class="settings-page" :class="{ 'settings-standalone': standalone }">
    <div v-if="!standalone" class="settings-navigation">
      <p class="settings-navigation-title">Pengaturan aplikasi</p>
      <div class="settings-tabs" role="group" aria-label="Bagian pengaturan">
        <button v-for="tab in panels" :key="tab.id" :class="{ selected: panel === tab.id }" :aria-pressed="panel === tab.id" @click="panel = tab.id; editor = ''">
          <span class="icon-tile" :class="tab.color"><Icon :name="tab.icon" :size="18" /></span>
          <span class="settings-tab-copy"><strong>{{ tab.title }}</strong><span>{{ tab.description }}</span></span>
          <Icon class="settings-tab-chevron" name="next" :size="16" />
        </button>
      </div>
    </div>
    <div class="settings-content">
      <p v-if="error || state.error" role="alert" class="error-text">{{ error || state.error }}</p>

      <template v-if="panel === 'preferences'">
        <section class="card settings-section settings-profile">
          <div class="profile-line">
            <span class="avatar mint">{{ state.mode === 'demo' ? 'D' : state.email.charAt(0).toUpperCase() }}</span>
            <div><strong>{{ state.mode === 'demo' ? 'Teman Demo' : state.email }}</strong><p class="muted">{{ state.mode === 'demo' ? 'Data contoh, bebas mencoba' : 'Akun terverifikasi' }}</p></div>
            <span class="pill">{{ state.mode === 'demo' ? 'Demo' : 'Terhubung' }}</span>
          </div>
        </section>
        <section class="card settings-section settings-preferences">
          <h2>Nyaman dengan caramu</h2>
          <div class="settings-preference-row">
            <span class="icon-tile sky"><Icon name="sun" /></span>
            <label for="settings-theme" class="settings-row-label"><strong>Tema</strong><span>Sesuaikan tampilan aplikasi.</span></label>
            <select id="settings-theme" :value="state.theme" @change="setTheme(($event.target as HTMLSelectElement).value)"><option value="system">Sistem</option><option value="light">Terang</option><option value="dark">Gelap</option></select>
          </div>
          <div class="settings-preference-row">
            <span class="icon-tile sky"><Icon name="calendar" /></span>
            <label for="settings-timezone" class="settings-row-label"><strong>Zona waktu</strong><span>Digunakan untuk tanggal catatan dan laporan.</span></label>
            <select id="settings-timezone" :value="state.timezone" :disabled="busy" @change="busy = true; saveTimezone(($event.target as HTMLSelectElement).value).catch(cause => error = message(cause)).finally(() => busy = false)"><option>Asia/Jakarta</option><option>Asia/Makassar</option><option>Asia/Jayapura</option><option>UTC</option></select>
          </div>
          <div class="settings-preference-row">
            <span class="icon-tile sky"><Icon name="eye" /></span>
            <label for="settings-hide" class="settings-row-label"><strong>Sembunyikan nominal</strong><span>Jaga privasi saldo dan jumlah transaksi.</span></label>
            <input id="settings-hide" v-model="state.hideAmounts" class="settings-switch" type="checkbox" role="switch" aria-label="Sembunyikan nominal" @change="preferences">
          </div>
          <details class="help-disclosure settings-storage"><summary>Penyimpanan perangkat</summary><p>Preferensi disimpan di perangkat. Data keuangan tidak disimpan di localStorage; sesi akun berlaku per tab.</p></details>
        </section>
        <section class="card settings-section settings-session">
          <div class="settings-row-label"><strong>Sesi akun</strong><span>{{ state.mode === 'demo' ? 'Mulai ulang data contoh atau keluar dari Demo.' : 'Keluar dari sesi akun pada perangkat ini.' }}</span></div>
          <div class="button-row"><button v-if="state.mode === 'demo'" class="secondary" :disabled="state.saving" @click="resetDemo"><Icon name="reset" :size="18" />Reset Demo</button><button class="secondary" :disabled="state.saving" @click="logout"><Icon name="logout" :size="18" />{{ state.mode === 'demo' ? 'Keluar Demo' : 'Keluar' }}</button></div>
        </section>
      </template>

      <template v-if="panel === 'accounts' || panel === 'categories'">
        <section class="card settings-section">
          <div class="settings-section-heading">
            <div><h2>{{ panel === 'accounts' ? 'Akunmu' : 'Kategori catatan' }}</h2><p class="muted">{{ panel === 'accounts' ? 'Saldo catatan, bukan saldo bank.' : 'Arsip kategori tidak mengubah histori.' }}</p></div>
            <div class="button-row"><button v-if="panel === 'accounts'" class="secondary" :disabled="state.data.accounts.filter(account => !account.archived).length < 2" @click="emit('transfer')"><Icon name="transfer" :size="18" />Transfer antar akun</button><button class="secondary" @click="edit(panel === 'accounts' ? 'account' : 'category')"><Icon name="plus" :size="18" />Tambah {{ panel === 'accounts' ? 'akun' : 'kategori' }}</button></div>
          </div>
          <form v-if="editor" class="entry-form inline-editor" @submit.prevent="save">
            <h3>{{ existing ? 'Ubah' : 'Tambah' }} {{ editor === 'account' ? 'akun' : 'kategori' }}</h3>
            <div class="form-grid">
              <label>Nama<input v-model="form.name" maxlength="80" required></label>
              <label>Jenis<select v-model="form.kind" :disabled="editor === 'category' && !!existing"><template v-if="editor === 'account'"><option value="cash">Tunai</option><option value="bank">Bank</option><option value="ewallet">E-wallet</option><option value="other">Lainnya</option></template><template v-else><option value="expense">Pengeluaran</option><option value="income">Pemasukan</option></template></select></label>
              <template v-if="editor === 'account'"><label>{{ existing ? 'Saldo saat ini' : 'Saldo awal' }}<MoneyInput v-model="form.amount" signed required /></label><label v-if="!existing">Tanggal pembukaan<input v-model="form.date" type="date" required></label><label v-else>Alasan penyesuaian (opsional)<input v-model="form.reason" maxlength="500" placeholder="Koreksi saldo akun"></label></template>
              <label v-else>Urutan<input v-model="form.order" type="number" min="0" max="9999" required></label>
            </div>
            <p v-if="editor === 'account' && existing" class="callout sky">Selisih saldo dicatat sebagai penyesuaian. Riwayat pemasukan dan pengeluaran tetap tersimpan.</p>
            <div class="button-row"><button class="primary" :disabled="state.saving">Simpan</button><button type="button" class="secondary" @click="editor = ''">Batal</button></div>
          </form>
          <div v-if="panel === 'accounts'" class="settings-list">
            <div v-for="account in state.data.accounts.filter(row => !row.archived)" :key="account.id" class="list-row settings-account-row">
              <span class="icon-tile sky"><Icon :name="account.kind === 'bank' ? 'bank' : 'wallet'" /></span>
              <div class="row-copy"><strong>{{ account.name }}</strong><span>{{ account.archived ? 'Diarsipkan' : 'Aktif' }} · {{ accountKinds[account.kind] ?? account.kind }}</span></div>
              <Money :amount="account.balance" />
              <div class="settings-row-actions"><button class="icon-button" :aria-label="`Ubah akun ${account.name}`" @click="edit('account', account)"><Icon name="edit" :size="18" /></button><button v-if="!account.archived" class="icon-button" :aria-label="`Hapus akun ${account.name}`" :disabled="state.saving || state.data.accounts.filter(row => !row.archived).length <= 1" @click="removeRecord('account', account)"><Icon name="trash" :size="18" /></button></div>
            </div>
          </div>
          <div v-else class="settings-list">
            <div v-for="category in [...state.data.categories.filter(row => !row.archived)].sort((left, right) => left.sortOrder - right.sortOrder)" :key="category.id" class="list-row settings-category-row">
              <span class="icon-tile" :class="category.kind === 'income' ? 'mint' : 'peach'"><Icon :name="category.kind === 'income' ? 'income' : 'expense'" :size="18" /></span>
              <div class="row-copy"><strong>{{ category.name }}</strong><span>{{ category.kind === 'income' ? 'Pemasukan' : 'Pengeluaran' }} · {{ category.archived ? 'Diarsipkan' : 'Aktif' }} · urutan {{ category.sortOrder }}</span></div>
              <div class="settings-row-actions"><button class="icon-button" :aria-label="`Ubah kategori ${category.name}`" @click="edit('category', category)"><Icon name="edit" :size="18" /></button><button v-if="!category.systemKey" class="icon-button" :aria-label="`Hapus kategori ${category.name}`" :disabled="state.saving" @click="removeRecord('category', category)"><Icon name="trash" :size="18" /></button></div>
            </div>
          </div>
        </section>
        <section v-if="panel === 'categories'" class="card settings-section settings-rules">
          <div class="settings-section-heading"><div><h2>Aturan merchant</h2><p class="muted">Saran kategori berdasarkan nama merchant.</p></div></div>
          <form class="entry-form" @submit.prevent="addRule">
            <div class="form-grid"><label>Pola merchant<input v-model="rule.pattern" required maxlength="160" placeholder="warung"></label><label>Pencocokan<select v-model="rule.match"><option value="contains">Mengandung</option><option value="exact">Persis</option><option value="prefix">Diawali</option></select></label><label>Kategori<select v-model="rule.category" required><option value="" disabled>Pilih kategori</option><option v-for="category in categories" :key="category.id" :value="category.id">{{ category.name }}</option></select></label></div>
            <button class="secondary" :disabled="state.saving">Tambah aturan</button>
          </form>
          <div class="settings-list"><div v-for="item in state.data.merchantRules" :key="item.id" class="list-row"><span>{{ item.normalizedPattern }} · {{ state.data.categories.find(row => row.id === item.categoryID)?.name }}</span><button class="text-button danger-text" :disabled="state.saving" @click="removeRule(item)">Hapus</button></div></div>
        </section>
      </template>

      <template v-if="panel === 'privacy'">
        <section class="card settings-section settings-export">
          <div class="settings-section-heading"><div><h2>Datamu tetap milikmu</h2><p>Unduh catatan dan lampiran. File ekspor berisi data sensitif.</p></div><span class="icon-tile sky"><Icon name="download" /></span></div>
          <div class="button-row"><button class="secondary" :disabled="busy" @click="exportAll"><Icon name="download" :size="18" />{{ busy ? 'Menyiapkan ekspor…' : 'Ekspor penuh (ZIP)' }}</button><button class="text-button" @click="emit('privacy')">Baca kebijakan privasi</button></div>
        </section>
        <section class="card settings-section settings-danger">
          <h2 class="danger-text">Hapus akun</h2>
          <p>Data Anda akan dihapus permanen setelah proses selesai. Data aplikasi, lampiran, serta sesi dihapus; retensi cadangan mengikuti konfigurasi penyedia dan belum diverifikasi untuk publikasi.</p>
          <p v-if="state.mode === 'demo'" class="callout sun">Mode Demo tidak memiliki akun server. Gunakan Reset Demo atau Keluar Demo.</p>
          <form v-else class="entry-form" @submit.prevent="deleteAccount"><div class="button-row"><button type="button" class="secondary" :disabled="busy" @click="reauthenticate('google')">Konfirmasi Google</button></div><label>Ketik HAPUS untuk melanjutkan<input v-model="deletion" autocomplete="off" pattern="HAPUS" required></label><button class="danger" :disabled="busy || state.saving || deletion !== 'HAPUS'">{{ busy ? 'Penghapusan sedang diproses…' : 'Hapus akun permanen' }}</button></form>
        </section>
      </template>
    </div>
  </div>
</template>
