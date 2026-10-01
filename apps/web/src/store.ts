import { reactive, ref, computed } from 'vue';
import { DemoRepository } from './demo.ts';
import { authClient, RemoteRepository } from './remote.ts';
import { emptySnapshot, derive, id, localDay, reportFor, type Report } from './domain.ts';
import { fromZonedTime } from './timezone.ts';

export const state = reactive({ mode: 'signedOut', recovery: false, loading: false, saving: false, error: '', notice: '', online: navigator.onLine, data: emptySnapshot(), email: '', theme: localStorage.getItem('danarapi.theme') ?? 'system', hideAmounts: localStorage.getItem('danarapi.hide') === 'true', timezone: localStorage.getItem('danarapi.timezone') ?? 'Asia/Jakarta' });
export const client = authClient();
let repository: DemoRepository | RemoteRepository = new DemoRepository();
export const attachments = new Map<string, File>();
export const report = ref<Report>({ personalIncome: '0', personalExpense: '0', categories: [] });
export const demo = computed(() => state.mode === 'demo');
window.addEventListener('online', () => { state.online = true; });
window.addEventListener('offline', () => { state.online = false; });
export function setTheme(value: string) { state.theme = value; localStorage.setItem('danarapi.theme', value); document.documentElement.dataset.theme = value === 'system' ? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : value; }
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { if (state.theme === 'system') setTheme('system'); });
export async function load() {
  if (state.loading) return;
  state.loading = true; state.error = '';
  try {
    if (repository instanceof DemoRepository) repository.timezone = state.timezone;
    state.data = await repository.snapshot();
    if (repository instanceof RemoteRepository && state.data.accounts.length === 0) {
      try { await repository.mutate('create_account', { p_client_mutation_id: id(), p_name: 'Tunai', p_kind: 'cash', p_opening_balance: '0', p_opened_at: fromZonedTime(today(), state.timezone) }); }
      catch (cause) { const latest = await repository.snapshot(); if (!latest.accounts.length) throw cause; }
      state.data = await repository.snapshot(); state.notice = 'Akun Tunai siap. Saldo awal dapat diatur di Pengaturan → Akun.';
    }
  } catch (error) { state.error = message(error); } finally { state.loading = false; }
}
export async function startDemo() { if (client) { await client.auth.stopAutoRefresh(); sessionStorage.removeItem('danarapi.auth'); } repository = new DemoRepository(); state.mode = 'demo'; state.email = ''; state.data = emptySnapshot(); attachments.clear(); await load(); }
export async function resetDemo() { if (repository instanceof DemoRepository) { repository.reset(); attachments.clear(); await load(); state.notice = 'Demo kembali ke data awal.'; } }
export async function logout() {
  if (client && state.mode === 'authenticated') { const { error } = await client.auth.signOut(); if (error) throw error; }
  state.mode = 'signedOut'; state.data = emptySnapshot(); state.email = ''; state.error = ''; state.notice = ''; attachments.clear(); repository = new DemoRepository();
  sessionStorage.removeItem('danarapi.deletion.owner');
}
export function message(error: unknown) { return error instanceof Error ? error.message : 'Belum tersimpan. Coba lagi.'; }
export async function mutate(operation: string, payload: Record<string, unknown>, success = 'Tersimpan') {
  if (state.saving) return false;
  state.saving = true; state.error = '';
  try {
    const previousTransactions = new Set(state.data.transactions.map(row => row.id)), previousBills = new Set(state.data.splitBills.map(row => row.id));
    await repository.mutate(operation, payload);
    if (operation !== 'request_account_deletion') await load();
    if (repository instanceof DemoRepository) {
      const reviewID = String(payload.id ?? payload.p_review_item_id ?? '');
      const file = attachments.get(reviewID);
      const transaction = state.data.transactions.find(row => !previousTransactions.has(row.id));
      const bill = state.data.splitBills.find(row => !previousBills.has(row.id));
      let destination: string | undefined;
      if (operation === 'confirm_review_item' && transaction) destination = `transaction:${transaction.id}`;
      if ((operation === 'create_split_bill_from_review' || (operation === 'save_item_split_bill' && payload.p_review_item_id)) && bill) destination = `bill:${bill.id}`;
      if (operation === 'merge_review_item') destination = payload.bill_id ? `bill:${payload.bill_id}` : `transaction:${payload.transaction_id}`;
      if (file && destination) { attachments.set(`${destination}:${id()}`, file); attachments.delete(reviewID); }
      if ((operation === 'convert_transaction_to_split_bill' || (operation === 'save_item_split_bill' && payload.p_transaction_id)) && bill) {
        for (const [key, value] of attachments) if (key.startsWith(`transaction:${payload.p_transaction_id}:`)) { attachments.set(`bill:${bill.id}:${id()}`, value); attachments.delete(key); }
      }
    }
    state.notice = state.error ? 'Tersimpan; pemuatan ulang gagal. Coba lagi.' : success; return true;
  }
  catch (error) { state.error = message(error); return false; }
  finally { state.saving = false; }
}
export const mutation = () => ({ p_client_mutation_id: id() });
export async function scanReceiptImages(images: { mimeType: string; data: string }[], signal: AbortSignal): Promise<import('./receipt.ts').ScanResult> {
  if (!(repository instanceof RemoteRepository)) {
    if (!import.meta.env.DEV || import.meta.env.VITE_LOCAL_RECEIPT_SCAN !== 'true') {
      if (!client) return { status: 'config_error' };
      throw new Error('Masuk akun untuk membaca struk melalui layanan cloud.');
    }
    const timeout = AbortSignal.any([signal, AbortSignal.timeout(110000)]);
    const capability = await fetch('/__local/receipt-scan', { signal: timeout });
    if (!capability.ok || !capability.headers.get('content-type')?.includes('application/json')) return { status: 'config_error' };
    const local = await capability.json();
    if (!local.configured || typeof local.token !== 'string') return { status: 'config_error' };
    const response = await fetch('/__local/receipt-scan', { method: 'POST', headers: { 'content-type': 'application/json', 'x-danarapi-local-scan': local.token }, body: JSON.stringify({ images }), signal: timeout });
    if (!response.ok && response.status !== 400) throw new Error('Backend scan lokal tidak dapat diakses. Isi manual tetap tersedia.');
    return response.json();
  }
  return repository.request('receipt-scan', { images }, undefined, false, signal);
}
export async function upload(reviewID: string, file: File) { if (repository instanceof RemoteRepository) await repository.upload(reviewID, file); attachments.set(reviewID, file); }
export async function uploadPosted(kind: 'transaction' | 'bill', targetID: string, file: File) {
  if (repository instanceof RemoteRepository) await repository.uploadPosted(kind, targetID, file);
  else {
    if (attachments.size >= 200 || [...attachments.values()].reduce((total, item) => total + item.size, file.size) > 100 * 1024 * 1024) throw new Error('Kuota lampiran tercapai.');
    attachments.set(`${kind}:${targetID}:${id()}`, file);
  }
}
export async function exportRemote() { if (!(repository instanceof RemoteRepository)) throw new Error('Tidak ada data server dalam Mode Demo.'); return repository.export(); }
export async function loadReport(from: string, to: string) {
  if (repository instanceof DemoRepository) { report.value = reportFor(state.data, from, to, state.timezone); }
  else {
    const end = new Date(`${to}T00:00:00Z`); end.setUTCDate(end.getUTCDate() + 1);
    report.value = await repository.report(fromZonedTime(from, state.timezone), fromZonedTime(end.toISOString().slice(0, 10), state.timezone));
  }
}
export async function initialize() {
  if (!client) return;
  const callback = new URL(window.location.href);
  const providerError = callback.searchParams.get('error') ?? new URLSearchParams(callback.hash.slice(1)).get('error');
  if (providerError) {
    sessionStorage.removeItem('danarapi.deletion.owner');
    history.replaceState(null, '', callback.pathname);
    state.error = 'Login dibatalkan atau belum berhasil. Silakan coba kembali.';
    return;
  }
  const code = callback.searchParams.get('code');
  if (code) {
    const { error } = await client.auth.exchangeCodeForSession(code);
    callback.searchParams.delete('code');
    history.replaceState(null, '', callback.pathname + callback.search + callback.hash);
    if (error) { sessionStorage.removeItem('danarapi.deletion.owner'); state.error = 'Login belum berhasil. Silakan coba kembali.'; return; }
  }
  const expectedOwner = sessionStorage.getItem('danarapi.deletion.owner');
  if (expectedOwner) {
    const { data: { session } } = await client.auth.getSession();
    if (session?.user.id !== expectedOwner) {
      await client.auth.signOut({ scope: 'local' });
      sessionStorage.removeItem('danarapi.deletion.owner');
      state.error = 'Konfirmasi dengan akun yang sama untuk melanjutkan.';
      return;
    }
  }
  client.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_OUT' && state.mode === 'authenticated') { state.mode = 'signedOut'; state.data = emptySnapshot(); attachments.clear(); }
    if (event === 'PASSWORD_RECOVERY') { state.recovery = true; return; }
    if (session?.user.email_confirmed_at && event !== 'TOKEN_REFRESHED' && state.mode !== 'demo' && !state.recovery) { state.email = session.user.email ?? ''; repository = new RemoteRepository(client); state.mode = 'authenticated'; setTimeout(() => void load(), 0); }
  });
  const { data: { session } } = await client.auth.getSession();
  if (session?.user.email_confirmed_at) {
    const { data: profile } = await client.from('profiles').select('timezone,theme').eq('user_id', session.user.id).single();
    if (profile?.timezone && ['Asia/Jakarta','Asia/Makassar','Asia/Jayapura','UTC'].includes(profile.timezone)) state.timezone = profile.timezone;
    if (profile?.theme && ['system','light','dark'].includes(profile.theme)) setTheme(profile.theme);
    state.email = session.user.email ?? ''; repository = new RemoteRepository(client); state.mode = 'authenticated'; await load();
  }
}
export const today = () => localDay(demo.value ? '2026-09-30T05:00:00Z' : new Date().toISOString(), state.timezone);
export function preferences() {
  localStorage.setItem('danarapi.hide', String(state.hideAmounts)); localStorage.setItem('danarapi.timezone', state.timezone);
  if (repository instanceof DemoRepository) { repository.timezone = state.timezone; state.data = derive(state.data, state.timezone); }
  if (client && state.mode === 'authenticated') void saveProfile();
}
async function saveProfile() {
  if (!client) return;
  const { data: { session } } = await client.auth.getSession(); if (!session) return;
  const { error } = await client.from('profiles').update({ timezone: state.timezone, theme: state.theme }).eq('user_id', session.user.id);
  if (error) state.notice = 'Preferensi tersimpan di perangkat; profil server belum diperbarui.';
  else await load();
}
