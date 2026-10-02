<script setup lang="ts">
import { computed, ref, reactive, watch, nextTick, onMounted, onBeforeUnmount } from 'vue';
import Auth from './components/Auth.vue';
import BrandIdentity from './components/BrandIdentity.vue';
import BrandArtwork from './components/BrandArtwork.vue';
import { onboardingContent } from './brand.ts';
import Icon from './components/Icon.vue';
import Money from './components/Money.vue';
import Modal from './components/Modal.vue';
import TransactionForm from './components/TransactionForm.vue';
import SplitForm from './components/ReceiptSplitForm.vue';
import BillDetail from './components/BillDetail.vue';
import ReviewList from './components/ReviewList.vue';
import Reports from './components/Reports.vue';
import HomeOverview from './components/HomeOverview.vue';
import Settings from './components/Settings.vue';
import Budgets from './components/Budgets.vue';
import GoalForm from './components/GoalForm.vue';
import PlanningOverview from './components/PlanningOverview.vue';
import type { PlanningEntry } from './product.ts';
import ProductPage from './components/ProductPage.vue';
import { publicPages, productLinks } from './product.ts';
import AttachmentPanel from './components/AttachmentPanel.vue';
import { state, initialize, load, logout, preferences, setTheme, mutate, mutation, today, consentPrompt, resolveAIConsent, onboardingPending, completeOnboarding } from './store.ts';
import { filterRows, reportFor, billRemaining, localDay, type ListRow, type Review, type Bill, type Transaction, type Transfer, type SavingsGoal } from './domain.ts';
import { download, filteredCSV } from './export.ts';
import { installKeyboardDismissal } from './keyboard-dismissal.ts';
const navigation = [{ key: 'home', title: 'Beranda', icon: 'home' }, { key: 'transactions', title: 'Transaksi', icon: 'transactions' }, { key: 'review', title: 'Perlu Ditinjau', icon: 'review' }, { key: 'reports', title: 'Laporan', icon: 'reports' }, { key: 'settings', title: 'Pengaturan', icon: 'settings' }];
const planningNavigation = [{ key: 'accounts', title: 'Akun keuangan', icon: 'wallet' }, { key: 'goals', title: 'Target', icon: 'target' }, { key: 'budgets', title: 'Anggaran', icon: 'budget' }];
const document = window.document;
const onboardingPage = ref(0);
const onboardingSteps = onboardingContent;
watch(onboardingPending, () => { onboardingPage.value = 0; });
const pathnamePage = location.pathname === '/hapus-akun' ? 'delete-account' : location.pathname.replace(/^\//, '');
const route = ref(location.hash.slice(1) || (publicPages.includes(pathnamePage) ? pathnamePage : 'home'));
const selectedGoal = ref<SavingsGoal>();
const dialogType = ref(''), dirty = ref(false), selectedReview = ref<Review>(), selectedBill = ref<Bill>(), selectedTransaction = ref<Transaction>(), selectedTransfer = ref<Transfer>(), lastRoute = ref('home');
const page = computed(() => navigation.some(row => row.key === route.value) || ['budgets','goals','accounts', ...publicPages].includes(route.value) ? route.value : lastRoute.value);
const undo = ref<{ action: () => Promise<void>; label: string; expires: number }>();
let undoTimer: ReturnType<typeof setTimeout> | undefined;
const filtersOpen = ref(false);
const filter = reactive({ query: '', kind: '', account: '', category: '', from: '', to: '' });
const activeFilters = computed(() => [filter.kind, filter.account, filter.category, filter.from, filter.to].filter(Boolean).length);
const cursor = ref<{ occurredAt: string; id: string }>();
const rows = computed(() => filterRows(state.data, filter, state.timezone));
const visibleRows = computed(() => { const end = cursor.value ? rows.value.findIndex(row => row.id === cursor.value?.id && row.occurredAt === cursor.value?.occurredAt) + 1 : 30; return rows.value.slice(0, Math.max(30, end)); });
const countPending = computed(() => state.data.reviewItems.filter(row => row.status === 'pending').length);
const month = ref(today().slice(0,7));
const settingsPanel = ref('preferences');
const homeReport = computed(() => reportFor(state.data, `${month.value}-01`, `${month.value}-31`, state.timezone));
const unpaidBills = computed(() => state.data.splitBills.filter(row => !row.deleted && billRemaining(row) > 0n));
const recent = computed(() => filterRows(state.data, { query: '', kind: '', account: '', category: '', from: '', to: '' }, state.timezone).slice(0,5));
const modalTitle = computed(() => ({ quick: 'Tambah catatan', budget: 'Buat anggaran', goal: selectedGoal.value ? 'Ubah target' : 'Buat target', expense: 'Catat pengeluaran', income: 'Catat pemasukan', transfer: 'Transfer antar akun', split: selectedBill.value ? 'Ubah tagihan bersama' : 'Split bill', 'bill-detail': selectedBill.value?.title ?? 'Tagihan bersama', 'transaction-detail': selectedTransaction.value?.merchant ?? 'Detail catatan', 'transfer-detail': 'Detail transfer', 'edit-transaction': 'Ubah transaksi', 'edit-transfer': 'Ubah transfer' } as Record<string,string>)[dialogType.value] ?? 'Catatan');
const title = computed(() => ({ home: 'Ringkasan keuangan', transactions: 'Transaksi', review: 'Tinjauan', reports: 'Laporan', settings: 'Pengaturan', budgets: 'Anggaran', goals: 'Target tabungan', accounts: 'Akun keuangan', privacy: 'Data & privasi' } as Record<string,string>)[page.value]);
const dateLabel = (value: string) => new Intl.DateTimeFormat('id-ID', { timeZone: state.timezone, day: 'numeric', month: 'short', year: 'numeric' }).format(new Date(value));
const kindLabel = (kind: string) => ({ income: 'Pemasukan', expense: 'Pengeluaran', transfer: 'Transfer', split: 'Split bill' } as Record<string,string>)[kind];
const accountName = (value: string) => state.data.accounts.find(row => row.id === value)?.name ?? 'Teman membayar';
const categoryName = (value: string) => state.data.categories.find(row => row.id === value)?.name ?? 'Antar akun';
function canLeave() { return !dirty.value || window.confirm('Ada input belum disimpan. Buang perubahan dan keluar dari formulir?'); }
function navigate(value: string) { if (!canLeave()) return; dirty.value = false; dialogType.value = ''; location.hash = value; route.value = value; state.error = ''; window.scrollTo({ top: 0 }); }
function onHash() {
  const next = location.hash.slice(1) || 'home';
  if (next === route.value) return;
  if (!canLeave()) { history.replaceState(null, '', `#${route.value}`); return; }
  dirty.value = false; route.value = next;
  if (!next.startsWith('input-') && next !== 'split-form' && next !== 'detail') dialogType.value = '';
}
function open(type: string, options?: { review?: Review; bill?: Bill; transaction?: Transaction; transfer?: Transfer; goal?: SavingsGoal }) {
  if (!state.loaded) return;
  if (!canLeave()) return; lastRoute.value = page.value; dirty.value = false; state.error = ''; selectedReview.value = options?.review; selectedBill.value = options?.bill; selectedTransaction.value = options?.transaction; selectedTransfer.value = options?.transfer; selectedGoal.value = options?.goal; dialogType.value = type;
  const next = type === 'split' ? 'split-form' : type.endsWith('detail') ? 'detail' : `input-${type}`;
  history.pushState(null, '', `#${next}`); route.value = next;
}
function openPlanningEntry(entry: PlanningEntry) {
  if (entry.kind === 'transaction') { const transaction = state.data.transactions.find(row => row.id === entry.sourceID); if (transaction) open('transaction-detail',{ transaction }); else state.error = 'Transaksi tidak tersedia. Muat ulang data.'; }
  else { const bill = state.data.splitBills.find(row => row.id === entry.sourceID || row.resolutions.some(value => value.id === entry.sourceID)); if (bill) open('bill-detail',{ bill }); else state.error = 'Catatan tidak tersedia. Muat ulang data.'; }
}
function openProgress(goal: SavingsGoal) { open('expense'); selectedGoal.value = goal; }
function openGoal(goal?: SavingsGoal) { open('goal', { goal }); }
function openAccounts() { navigate('accounts'); }
function openFlow(kind: string) {
  const [year, selectedMonth] = month.value.split('-').map(Number);
  Object.assign(filter, { query: '', kind, account: '', category: '', from: `${month.value}-01`, to: `${month.value}-${new Date(Date.UTC(year, selectedMonth, 0)).getUTCDate()}` });
  navigate('transactions');
}
function close(force = false) { if (!force && !canLeave()) return; dirty.value = false; dialogType.value = ''; state.error = ''; history.replaceState(null, '', `#${lastRoute.value}`); route.value = lastRoute.value; }
function openRow(row: ListRow) { if (row.kind === 'split') open('bill-detail', { bill: state.data.splitBills.find(bill => bill.id === row.id) }); else if (row.kind === 'transfer') open('transfer-detail', { transfer: state.data.transfers.find(transfer => transfer.id === row.id) }); else open('transaction-detail', { transaction: state.data.transactions.find(transaction => transaction.id === row.id) }); }
function showUndo(action: () => Promise<void>, label: string) { if (undoTimer) clearTimeout(undoTimer); undo.value = { action, label, expires: Date.now() + 10000 }; undoTimer = setTimeout(() => { undo.value = undefined; }, 10000); }
async function undoDelete() { const item = undo.value; if (!item || Date.now() >= item.expires) return; undo.value = undefined; await item.action(); }
async function remove(kind: string, item: Transaction | Transfer | Bill) {
  if (!window.confirm(`Hapus ${kind === 'split_bill' ? 'tagihan' : kind === 'transfer' ? 'transfer' : 'transaksi'} ini? Dapat diurungkan selama 10 detik.`)) return;
  const key = `p_${kind}_id`;
  if (await mutate(`delete_${kind}`, { ...mutation(), [key]: item.id, p_expected_version: item.version }, 'Catatan dihapus')) {
    close(true);
    showUndo(async () => { await mutate(`restore_${kind}`, { ...mutation(), [key]: item.id, p_expected_version: item.version + 1 }, 'Catatan dipulihkan'); }, 'Catatan dihapus');
  }
}
function loadMore() { const last = rows.value[Math.min(rows.value.length, visibleRows.value.length + 30) - 1]; if (last) cursor.value = { occurredAt: last.occurredAt, id: last.id }; }
watch(filter, () => { cursor.value = undefined; });
watch(() => state.mode, async () => { dialogType.value = ''; dirty.value = false; month.value = today().slice(0,7); cursor.value = undefined; await nextTick(); document.querySelector<HTMLElement>('#main-content')?.focus({ preventScroll: true }); });
function beforeUnload(event: BeforeUnloadEvent) { if (dirty.value) { event.preventDefault(); event.returnValue = ''; } }
let removeKeyboardDismissal: (() => void) | undefined;
onMounted(() => { removeKeyboardDismissal = installKeyboardDismissal(document); void initialize(); window.addEventListener('hashchange', onHash); window.addEventListener('beforeunload', beforeUnload); if (route.value.startsWith('input-') || ['split-form','detail'].includes(route.value)) route.value = 'home'; });
onBeforeUnmount(() => { removeKeyboardDismissal?.(); window.removeEventListener('hashchange', onHash); window.removeEventListener('beforeunload', beforeUnload); if (undoTimer) clearTimeout(undoTimer); });
</script>
<template>
  <template v-if="state.mode === 'signedOut'"><div v-if="publicPages.includes(page)" class="public-product"><ProductPage :page-i-d="page" @navigate="navigate" /></div><template v-else><Auth /><nav class="product-links public-product-footer" aria-label="Tentang dan bantuan"><a v-for="link in productLinks" :key="link.id" :href="`#${link.id}`" @click.prevent="navigate(link.id)">{{ link.id === 'privacy' ? 'Kebijakan privasi' : link.title }}</a></nav></template></template>
  <div v-else class="app-shell">
    <a class="skip-link" href="#main-content">Lewati navigasi</a>
    <aside class="sidebar"><a class="brand" href="#home" @click.prevent="navigate('home')"><BrandIdentity /></a><nav aria-label="Navigasi utama"><a v-for="item in navigation" :key="item.key" :href="`#${item.key}`" :aria-current="page === item.key ? 'page' : undefined" :aria-label="item.title" :class="{ active: page === item.key }" @click.prevent="navigate(item.key)"><Icon :name="item.icon" /><span>{{ item.key === 'review' ? 'Tinjauan' : item.title }}</span><span v-if="item.key === 'review' && countPending" class="nav-count">{{ countPending }}</span></a></nav><nav class="sidebar-planning" aria-label="Rencana dan akun"><span class="sidebar-caption">Rencana & akun</span><a v-for="item in planningNavigation" :key="item.key" :href="`#${item.key}`" :aria-current="page === item.key ? 'page' : undefined" :class="{ active: page === item.key }" @click.prevent="navigate(item.key)"><Icon :name="item.icon" /><span>{{ item.title }}</span></a></nav><div class="sidebar-bottom"><button class="sidebar-help" @click="navigate('faq')"><Icon name="help" /><span>Tentang & bantuan</span></button><button class="profile-button" @click="navigate('settings')"><span class="avatar mint">{{ state.mode === 'demo' ? 'D' : state.email.charAt(0).toUpperCase() }}</span><span><strong>{{ state.mode === 'demo' ? 'Teman Demo' : state.email }}</strong></span><Icon name="more" /></button></div></aside>
    <div class="main-wrap">
<div v-if="!state.online" class="offline-banner" role="status">{{ state.mode === 'demo' ? 'Offline · Demo tetap tersedia.' : 'Offline · Hubungkan internet untuk menyimpan.' }}</div><main id="main-content" tabindex="-1" :aria-busy="state.loading">
<header v-if="!publicPages.includes(page)" class="page-heading"><div><h1>{{ title }}</h1></div><div class="heading-actions"><button class="icon-button" aria-label="Muat ulang catatan" :disabled="state.loading" @click="load"><Icon name="reset" /></button><button class="icon-button" :aria-label="state.hideAmounts ? 'Tampilkan nominal' : 'Sembunyikan nominal'" @click="state.hideAmounts = !state.hideAmounts; preferences()"><Icon :name="state.hideAmounts ? 'hidden' : 'eye'" /></button><button class="icon-button" :aria-label="state.resolvedTheme === 'dark' ? 'Gunakan tema terang' : 'Gunakan tema gelap'" @click="setTheme(state.resolvedTheme === 'dark' ? 'light' : 'dark')"><Icon :name="state.resolvedTheme === 'dark' ? 'sun' : 'moon'" /></button><button class="primary add-button" @click="open('quick')"><Icon name="plus" /> Catat baru</button></div></header>
      <div v-if="state.loading && !state.loaded && !publicPages.includes(page)" class="loading-state" role="status" aria-live="polite"><div class="skeleton hero-skeleton"></div><div class="skeleton"></div><span>Memuat catatanmu…</span></div>
      <section v-else-if="!state.loaded && !publicPages.includes(page)" class="card cloud-unavailable" role="alert"><Icon name="warning" /><h2>Data belum dapat dimuat</h2><p>{{ state.loadError || 'Hubungkan internet untuk memuat catatanmu.' }}</p><div class="button-row"><button class="primary" :disabled="state.loading" @click="load">Coba lagi</button><button class="secondary" @click="logout">Keluar</button></div></section>
      <div v-else-if="state.loadError && !dialogType" class="callout error-box" role="alert"><Icon name="warning" /><div><strong>Data terbaru belum dimuat</strong><p>{{ state.loadError }}</p></div><button class="secondary" :disabled="state.loading" @click="load">Coba lagi</button></div>
      <div v-if="state.error && !dialogType" class="callout error-box" role="alert"><Icon name="warning" /><div><strong>Perubahan belum tersimpan</strong><p>{{ state.error }}</p></div></div>
      <template v-if="state.loaded || publicPages.includes(page)">
      <div v-if="state.loaded && state.mode === 'authenticated' && !publicPages.includes(page)" class="sync-strip" role="status" aria-live="polite"><span>{{ !state.online ? 'Offline · perlu internet untuk menyimpan' : state.loading ? 'Menyinkronkan…' : state.data.syncedAt ? `Sinkron ${new Date(state.data.syncedAt).toLocaleTimeString('id-ID', { timeZone: state.timezone })}` : 'Belum tersinkron' }}</span><button class="text-button" :disabled="state.loading || !state.online" @click="load">Perbarui</button></div>
      <HomeOverview v-if="page === 'home'" v-model:month="month" :report="homeReport" :pending="countPending" :rows="recent" :bills="unpaidBills" @accounts="openAccounts" @transactions="navigate('transactions')" @income="openFlow('income')" @expense="openFlow('expense')" @review="navigate('review')" @add="open('expense')" @goal="openGoal" @progress="openProgress" @budget="open('budget')" @row="openRow" @entry="openPlanningEntry" @bill="bill => open('bill-detail', { bill })" />
      <template v-if="page === 'transactions'"><div class="button-row transaction-actions"><button class="secondary" @click="open('transfer')"><Icon name="transfer" /> Transfer antar akun</button><button class="text-button" @click="navigate('goals')">Target</button><button class="text-button" @click="navigate('budgets')">Anggaran</button></div><section class="card filter-panel"><div class="filter-heading"><label class="search-field"><Icon name="search" /><input v-model="filter.query" type="search" aria-label="Cari merchant atau catatan" placeholder="Cari merchant atau catatan"></label><button type="button" class="secondary" :aria-expanded="filtersOpen" aria-controls="transaction-filters" @click="filtersOpen = !filtersOpen"><Icon name="settings" /> Filter<span v-if="activeFilters"> ({{ activeFilters }})</span></button></div><div v-show="filtersOpen" id="transaction-filters" class="filter-grid"><label>Akun<select v-model="filter.account"><option value="">Semua akun</option><option v-for="account in state.data.accounts" :key="account.id" :value="account.id">{{ account.name }}</option></select></label><label>Kategori<select v-model="filter.category"><option value="">Semua kategori</option><option v-for="category in state.data.categories" :key="category.id" :value="category.id">{{ category.name }}</option></select></label><label>Jenis<select v-model="filter.kind"><option value="">Semua jenis</option><option value="expense">Pengeluaran</option><option value="income">Pemasukan</option><option value="transfer">Transfer</option><option value="split">Split bill</option></select></label><label>Dari tanggal<input v-model="filter.from" type="date"></label><label>Sampai tanggal<input v-model="filter.to" type="date" :min="filter.from"></label></div><div class="section-heading filter-footer"><button v-if="filtersOpen || activeFilters || filter.query" class="text-button" @click="Object.assign(filter, { query: '', kind: '', account: '', category: '', from: '', to: '' })">Reset filter</button><button class="secondary" @click="download('transaksi-tampilan.csv', filteredCSV(state.data, filter, state.timezone))"><Icon name="download" /> CSV tampilan ({{ rows.length }})</button></div><p v-if="activeFilters && !filtersOpen" class="filter-summary">{{ activeFilters }} filter aktif</p></section><section class="card transaction-list"><div class="section-heading"><h2>Catatanmu</h2><span class="muted">{{ rows.length }} catatan</span></div><div v-if="!rows.length" class="empty"><Icon name="search" :size="36" /><h3>Belum ada catatan yang cocok</h3><p>Coba ubah filter atau catat sesuatu yang baru.</p><button class="secondary" @click="open('expense')">Catat pengeluaran</button></div><template v-for="(row,index) in visibleRows" :key="row.id"><h3 v-if="index === 0 || localDay(visibleRows[index - 1].occurredAt, state.timezone) !== localDay(row.occurredAt,state.timezone)" class="date-group">{{ dateLabel(row.occurredAt) }}</h3><button class="transaction-row" @click="openRow(row)"><span class="icon-tile" :class="row.kind === 'income' ? 'mint' : row.kind === 'split' ? 'peach' : 'sky'"><Icon :name="row.kind === 'expense' ? row.categoryID : row.kind" /></span><span class="row-copy"><strong>{{ row.merchant || kindLabel(row.kind) }}</strong><span>{{ categoryName(row.categoryID) }} · {{ accountName(row.accountID) }}{{ row.note ? ` · ${row.note}` : '' }}</span></span><span class="row-amount"><Money :amount="row.amount" :prefix="row.kind === 'income' ? '+' : row.kind === 'expense' ? '−' : ''" /></span></button></template><button v-if="visibleRows.length < rows.length" class="secondary full" @click="loadMore">Muat 30 berikutnya</button></section></template>
      <ReviewList v-if="page === 'review'" @confirm="(review, split) => open(split ? 'split' : 'expense', { review })" @undo="showUndo" />
      <Reports v-if="page === 'reports'" @bill="bill => open('bill-detail', { bill })" @budget="navigate('budgets')" />
      <Settings v-if="page === 'settings'" :key="settingsPanel" :initial-panel="settingsPanel" @transfer="open('transfer')" @privacy="navigate('privacy')" @navigate="navigate" @dirty="dirty = $event" />
      <Settings v-if="page === 'accounts'" initial-panel="accounts" standalone @transfer="open('transfer')" @privacy="navigate('privacy')" @navigate="navigate" @dirty="dirty = $event" />
      <Budgets v-if="page === 'budgets'" @entry="openPlanningEntry" />
      <PlanningOverview v-if="page === 'goals'" :month="month" targets-only @goal="openGoal" @progress="openProgress" @entry="openPlanningEntry" />
      <ProductPage v-if="publicPages.includes(page)" :page-i-d="page" @navigate="navigate" />
      </template>
</main>
</div>
    <nav class="bottom-nav" aria-label="Navigasi ponsel"><a v-for="item in navigation" :key="item.key" :href="`#${item.key}`" :aria-label="item.key === 'settings' ? 'Setelan, Pengaturan' : item.title" :aria-current="page === item.key ? 'page' : undefined" :class="{ active: page === item.key, 'scan-link': item.key === 'review' }" @click.prevent="navigate(item.key)"><span class="bottom-icon"><span v-if="item.key === 'review'" class="scan-disc"><Icon :name="item.icon" /></span><Icon v-else :name="item.icon" /><span v-if="item.key === 'review' && countPending" class="bottom-count">{{ countPending }}</span></span><span>{{ item.key === 'settings' ? 'Setelan' : item.key === 'review' ? 'Pindai' : item.title }}</span></a></nav>
    <div v-if="state.notice || undo" class="toast" role="status" aria-live="polite"><Icon name="check" /><span>{{ undo?.label ?? state.notice }}</span><button v-if="undo" class="text-button" :disabled="state.saving" @click="undoDelete">Urungkan</button><button v-else class="icon-button" aria-label="Tutup pemberitahuan" @click="state.notice = ''"><Icon name="close" :size="16" /></button></div>
    <Modal v-if="onboardingPending && ['authenticated', 'demo'].includes(state.mode) && state.loaded && !state.recovery && !publicPages.includes(page)" class="brand-onboarding" :title="onboardingSteps[onboardingPage]!.title" @close="completeOnboarding">
      <p class="brand-step-label" role="status">Langkah {{ onboardingPage + 1 }} dari {{ onboardingSteps.length }}</p>
      <BrandArtwork :name="onboardingSteps[onboardingPage]!.image" />
      <p class="brand-step-description">{{ onboardingSteps[onboardingPage]!.description }}</p>
      <div class="brand-step-dots" aria-hidden="true"><span v-for="(step, index) in onboardingSteps" :key="step.id" :class="{ active: index === onboardingPage }"></span></div>
      <div class="brand-step-actions">
        <button v-if="onboardingPage > 0" class="secondary" @click="onboardingPage--">Kembali</button>
        <button class="primary" data-initial-focus @click="onboardingPage < onboardingSteps.length - 1 ? onboardingPage++ : completeOnboarding()">{{ onboardingPage < onboardingSteps.length - 1 ? 'Lanjut' : 'Mulai mencatat' }}</button>
      </div>
      <button class="text-button brand-step-skip" @click="completeOnboarding">Lewati tur</button>
    </Modal>
    <Modal v-if="consentPrompt" title="Izinkan pengiriman struk?" @close="resolveAIConsent(false)"><p class="consent-copy">Foto atau halaman PDF dikirim ke penyedia AI untuk membaca struk. Data dapat diproses menurut ketentuan paket penyedia. Periksa hasil sebelum menyimpan.</p><a href="/privacy" target="_blank" rel="noopener noreferrer">Baca kebijakan privasi</a><div class="consent-actions"><button class="primary" @click="resolveAIConsent(true)">Setuju dan lanjutkan</button><button class="secondary" @click="resolveAIConsent(false)">Isi manual</button></div></Modal>
    <Modal v-if="dialogType" :title="modalTitle" :dirty="dirty" @close="close()">
      <div v-if="dialogType === 'quick'" class="quick-actions quick-planning"><button v-for="action in [{key:'expense',title:'Pengeluaran',hint:'Catat belanja',icon:'expense'},{key:'income',title:'Pemasukan',hint:'Catat uang masuk',icon:'income'},{key:'budget',title:'Anggaran',hint:'Batas belanja bulanan',icon:'budget'},{key:'goal',title:'Target',hint:'Tujuan dan tenggat',icon:'target'},{key:'split',title:'Split bill',hint:'Bagi tagihan',icon:'split'},{key:'import',title:'Impor bukti',hint:'Foto, PDF, atau teks',icon:'upload'}]" :key="action.key" class="quick-action" @click="action.key === 'import' ? navigate('review') : action.key === 'goal' ? openGoal() : open(action.key)"><span class="icon-tile sky"><Icon :name="action.icon" /></span><span><strong>{{ action.title }}</strong></span><Icon name="next" :size="16" /></button></div><Budgets v-if="dialogType === 'budget'" compact :initial-month="month" @saved="close(true)" @dirty="dirty = $event" />
      <GoalForm v-if="dialogType === 'goal'" :goal="selectedGoal" @saved="close(true)" @dirty="dirty = $event" />
      <TransactionForm v-if="['expense','income','transfer','edit-transaction','edit-transfer'].includes(dialogType)" :key="`${dialogType}-${selectedReview?.id ?? selectedTransaction?.id ?? selectedTransfer?.id ?? ''}`" :kind="dialogType === 'edit-transfer' ? 'transfer' : dialogType === 'edit-transaction' ? selectedTransaction!.kind : dialogType" :existing="dialogType === 'edit-transfer' ? selectedTransfer : dialogType === 'edit-transaction' ? selectedTransaction : undefined" :review="selectedReview" :initial-goal="dialogType === 'expense' ? selectedGoal : undefined" @dirty="dirty = $event" @saved="close(true)" /><SplitForm v-if="dialogType === 'split'" :key="selectedBill?.id ?? selectedReview?.id ?? selectedTransaction?.id ?? 'new'" :existing="selectedBill" :review="selectedReview" :transaction="selectedTransaction" @dirty="dirty = $event" @saved="close(true)" /><BillDetail v-if="dialogType === 'bill-detail' && selectedBill" :bill-i-d="selectedBill.id" @edit="bill => open('split', { bill })" @remove="bill => remove('split_bill', bill)" /><section v-if="dialogType === 'transaction-detail' && selectedTransaction" class="detail-summary"><span class="pill" :class="selectedTransaction.kind === 'income' ? 'mint' : 'peach'">{{ kindLabel(selectedTransaction.kind) }}</span><h2><Money :amount="selectedTransaction.amount" /></h2><dl><dt>Akun</dt><dd>{{ accountName(selectedTransaction.accountID) }}</dd><dt>Kategori</dt><dd>{{ categoryName(selectedTransaction.categoryID) }}</dd><template v-if="selectedTransaction.goalID"><dt>Target</dt><dd>{{ state.data.goals?.find(goal => goal.id === selectedTransaction!.goalID)?.name ?? 'Target' }}</dd></template><dt>Tanggal</dt><dd>{{ dateLabel(selectedTransaction.occurredAt) }}</dd><dt>Catatan</dt><dd>{{ selectedTransaction.note || 'Tidak ada catatan' }}</dd><dt>Sumber</dt><dd>{{ selectedTransaction.source }}</dd></dl><div class="button-row"><button class="secondary" @click="open('edit-transaction', { transaction: selectedTransaction })"><Icon name="edit" /> Ubah</button><button v-if="selectedTransaction.kind === 'expense' && !selectedTransaction.goalID" class="secondary" @click="open('split', { transaction: selectedTransaction })">Jadikan split bill</button><button class="danger" :disabled="state.saving" @click="remove('transaction', selectedTransaction)"><Icon name="trash" /> Hapus</button></div><AttachmentPanel kind="transaction" :target-i-d="selectedTransaction.id" /><p v-if="state.error" class="error-text" role="alert">{{ state.error }}</p></section><section v-if="dialogType === 'transfer-detail' && selectedTransfer" class="detail-summary"><span class="pill sky">Transfer antar akun sendiri</span><h2><Money :amount="selectedTransfer.amount" /></h2><p>{{ accountName(selectedTransfer.fromAccountID) }} ke {{ accountName(selectedTransfer.toAccountID) }}</p><p>{{ dateLabel(selectedTransfer.occurredAt) }} · {{ selectedTransfer.note }}</p><div class="button-row"><button class="secondary" @click="open('edit-transfer', { transfer: selectedTransfer })">Ubah transfer</button><button class="danger" :disabled="state.saving" @click="remove('transfer', selectedTransfer)">Hapus transfer</button></div><p v-if="state.error" role="alert" class="error-text">{{ state.error }}</p></section>
    </Modal>
  </div>
</template>
