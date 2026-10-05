import { reactive, ref, computed } from 'vue';
import { DemoRepository } from './demo.ts';
import { authClient, RemoteRepository } from './remote.ts';
import { emptySnapshot, derive, id, localDay, reportFor, selfShare, type Report } from './domain.ts';
import { fromZonedTime } from './timezone.ts';
import { productContent, type AIConsent, type PlanningHistory, type PlanningEntry } from './product.ts';
import { hasCompletedOnboarding, saveOnboardingCompletion } from './onboarding.ts';

export const state = reactive({ mode: 'signedOut', recovery: false, loading: false, loaded: false, loadError: '', saving: false, error: '', notice: '', online: navigator.onLine, data: emptySnapshot(), email: '', theme: localStorage.getItem('danarapi.theme') ?? 'system', resolvedTheme: document.documentElement.dataset.theme || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'), hideAmounts: localStorage.getItem('danarapi.hide') === 'true', timezone: localStorage.getItem('danarapi.timezone') ?? 'Asia/Jakarta' });
export const client = authClient();
let repository: DemoRepository | RemoteRepository = new DemoRepository();
let authenticatedOwner: string | undefined;
export function calculatorOwnerID(): string { return state.mode === 'authenticated' ? authenticatedOwner ?? 'signed-out' : state.mode; }
export const attachments = new Map<string, File>();
export const report = ref<Report>({ personalIncome: '0', personalExpense: '0', categories: [] });
let reportRevision = 0;
export const demo = computed(() => state.mode === 'demo');
export const onboardingPending = ref(false);
export function completeOnboarding() {
  if (state.mode === 'demo') { onboardingPending.value = false; return; }
  if (state.mode !== 'authenticated' || !authenticatedOwner) return;
  try { saveOnboardingCompletion(localStorage, authenticatedOwner); }
  catch { state.notice = 'Tur selesai. Preferensi tidak dapat disimpan pada browser ini.'; }
  onboardingPending.value = false;
}
export const aiConsent = ref<AIConsent>();
export const consentPrompt = ref(false);
let consentDecision: ((value: boolean) => void) | undefined;
let pendingConsent: Promise<boolean> | undefined;
export function resolveAIConsent(value: boolean) { consentDecision?.(value); consentDecision = undefined; pendingConsent = undefined; consentPrompt.value = false; }
async function requestAIConsent(signal: AbortSignal) {
  signal.throwIfAborted();
  if (!pendingConsent) { consentPrompt.value = true; pendingConsent = new Promise<boolean>(resolve => { consentDecision = resolve; }); }
  const cancel = () => resolveAIConsent(false);
  signal.addEventListener('abort', cancel, { once: true });
  try { return await pendingConsent; } finally { signal.removeEventListener('abort', cancel); }
}
export async function productRequest(operation: string, payload?: Record<string, unknown>): Promise<any> {
  if (!(repository instanceof RemoteRepository) || state.mode !== 'authenticated') throw new Error('Masuk untuk menggunakan layanan akun.');
  const requestedRepository = repository, owner = authenticatedOwner;
  const result = ['support', 'consent'].includes(operation) ? await requestedRepository.request(`ios-data/${operation}`) : await requestedRepository.mutate(operation, payload ?? {});
  if (requestedRepository !== repository || owner !== authenticatedOwner) throw new Error('Akun berubah.');
  return result;
}
export async function planningHistory(filter: { goalID?: string; categoryID?: string; startDate?: string; endDate?: string; cursor?: PlanningHistory['nextCursor'] }): Promise<PlanningHistory> {
  const requestedOwner = authenticatedOwner;
  if (repository instanceof RemoteRepository) {
    const result = await repository.request('ios-data/planning-history', filter);
    if (requestedOwner !== authenticatedOwner) throw new Error('Akun berubah.');
    return result;
  }
  const items: PlanningEntry[] = state.data.transactions.filter(row => !row.deleted && row.kind === 'expense' && (!filter.goalID || row.goalID === filter.goalID) && (!filter.categoryID || row.categoryID === filter.categoryID)).map(row => ({ ...row, sourceID: row.id, kind: 'transaction' }));
  if (filter.categoryID) for (const bill of state.data.splitBills.filter(row => !row.deleted && row.categoryID === filter.categoryID)) {
    const amount = selfShare(bill); if (amount > 0n) items.push({ id: bill.id, sourceID: bill.id, kind: 'split_bill', amount: amount.toString(), occurredAt: bill.occurredAt, merchant: bill.title });
  }
  const filtered = items.filter(row => (!filter.startDate || row.occurredAt >= filter.startDate) && (!filter.endDate || row.occurredAt < filter.endDate)).sort((left,right) => right.occurredAt.localeCompare(left.occurredAt) || right.id.localeCompare(left.id));
  const start = filter.cursor ? filtered.findIndex(row => row.id === filter.cursor?.id) + 1 : 0;
  const page = filtered.slice(start,start + 30), last = page.at(-1);
  return { items: page, nextCursor: start + 30 < filtered.length && last ? { id: last.id, occurredAt: last.occurredAt } : null };
}
export async function setAIConsent(granted: boolean) {
  const owner = authenticatedOwner;
  await productRequest('set_ai_consent', { granted, policyVersion: productContent.version });
  if (authenticatedOwner !== owner) throw new Error('Akun berubah. Coba kembali.');
  aiConsent.value = { granted, policyVersion: productContent.version, updatedAt: new Date().toISOString() };
}
export async function refreshAIConsent() {
  const owner = authenticatedOwner;
  const value = await productRequest('consent') as AIConsent;
  if (authenticatedOwner === owner) aiConsent.value = value;
  return value;
}
export async function saveTimezone(timezone: string) {
  if (!['Asia/Jakarta', 'Asia/Makassar', 'Asia/Jayapura', 'UTC'].includes(timezone)) throw new Error('Zona waktu tidak valid.');
  const owner = authenticatedOwner;
  if (state.mode === 'authenticated') await productRequest('set_timezone', { timezone });
  if (owner !== authenticatedOwner) throw new Error('Akun berubah. Coba kembali.');
  state.timezone = timezone; preferences(); await load();
}
window.addEventListener('online', () => { state.online = true; void refreshOnResume(); });
window.addEventListener('offline', () => { state.online = false; });
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') void refreshOnResume(); });
window.addEventListener('focus', () => { void refreshOnResume(); });
async function refreshOnResume() {
  if (state.mode !== 'authenticated' || !state.online || state.loading || state.saving) return;
  if (state.data.syncedAt && Date.now() - new Date(state.data.syncedAt).getTime() < 15000) return;
  await load();
}
export function setTheme(value: string) { state.theme = value; localStorage.setItem('danarapi.theme', value); state.resolvedTheme = value === 'system' ? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : value; document.documentElement.dataset.theme = state.resolvedTheme; }
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { if (state.theme === 'system') setTheme('system'); });
export async function load() {
  if (state.loading) return false;
  const requestedRepository = repository, requestedMode = state.mode;
  state.loading = true; state.loadError = '';
  try {
    if (requestedRepository instanceof DemoRepository) requestedRepository.timezone = state.timezone;
    let data = await requestedRepository.snapshot();
    if (repository !== requestedRepository || state.mode !== requestedMode) return false;
    if (requestedRepository instanceof RemoteRepository && data.accounts.length === 0) {
      try { await requestedRepository.mutate('create_account', { p_client_mutation_id: id(), p_name: 'Tunai', p_kind: 'cash', p_opening_balance: '0', p_opened_at: fromZonedTime(today(), state.timezone) }); }
      catch (cause) { const latest = await requestedRepository.snapshot(); if (!latest.accounts.length) throw cause; }
      data = await requestedRepository.snapshot();
    }
    if (repository !== requestedRepository || state.mode !== requestedMode) return false;
    if (data.timezone) { state.timezone = data.timezone; localStorage.setItem('danarapi.timezone', data.timezone); }
    state.data = data; state.loaded = true;
    return true;
  } catch (error) { if (repository === requestedRepository && state.mode === requestedMode) state.loadError = message(error); return false; }
  finally { if (repository === requestedRepository && state.mode === requestedMode) state.loading = false; }
}
export async function startDemo() { resolveAIConsent(false); aiConsent.value = undefined; if (client) { await client.auth.stopAutoRefresh(); sessionStorage.removeItem('danarapi.auth'); } repository = new DemoRepository(new Date()); authenticatedOwner = undefined; state.mode = 'demo'; onboardingPending.value = true; state.email = ''; state.data = emptySnapshot(); state.loaded = false; state.loading = false; state.loadError = ''; attachments.clear(); await load(); }
export async function resetDemo() { if (repository instanceof DemoRepository) { repository.reset(); attachments.clear(); await load(); state.notice = 'Demo kembali ke data awal.'; } }
export async function logout() {
  resolveAIConsent(false); aiConsent.value = undefined;
  if (client && state.mode === 'authenticated') { const { error } = await client.auth.signOut(); if (error) throw error; }
  state.mode = 'signedOut'; state.data = emptySnapshot(); state.loaded = false; state.loading = false; state.loadError = ''; state.email = ''; state.error = ''; state.notice = ''; attachments.clear(); repository = new DemoRepository();
  sessionStorage.removeItem('danarapi.deletion.owner');
  authenticatedOwner = undefined;
}
export function message(error: unknown) { return error instanceof Error ? error.message : 'Belum tersimpan. Coba lagi.'; }
export async function mutate(operation: string, payload: Record<string, unknown>, success = 'Tersimpan') {
  if (state.saving) return false;
  state.saving = true; state.error = '';
  const requestedRepository = repository;
  try {
    const previousTransactions = new Set(state.data.transactions.map(row => row.id)), previousBills = new Set(state.data.splitBills.map(row => row.id));
    await requestedRepository.mutate(operation, payload);
    if (requestedRepository !== repository) return false;
    if (operation !== 'request_account_deletion' && !await load()) { state.notice = 'Perubahan tersimpan. Data terbaru belum dimuat; coba muat ulang.'; return true; }
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
  catch (error) { if (requestedRepository === repository) state.error = message(error); return false; }
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
    if (!(aiConsent.value?.granted && aiConsent.value.policyVersion === productContent.version)) {
      if (!await requestAIConsent(signal)) throw new Error('Pengiriman AI dibatalkan. Isi manual tetap tersedia.');
      signal.throwIfAborted();
      aiConsent.value = { granted: true,policyVersion: productContent.version,updatedAt: new Date().toISOString() };
    }
    signal.throwIfAborted();
    const response = await fetch('/__local/receipt-scan', { method: 'POST', headers: { 'content-type': 'application/json', 'x-danarapi-local-scan': local.token }, body: JSON.stringify({ images }), signal: timeout });
    if (!response.ok && response.status !== 400) throw new Error('Backend scan lokal tidak dapat diakses. Isi manual tetap tersedia.');
    return response.json();
  }
  const owner = authenticatedOwner;
  const consent = await refreshAIConsent();
  if (!(consent.granted && consent.policyVersion === productContent.version)) {
    if (!await requestAIConsent(signal)) throw new Error('Pengiriman AI dibatalkan. Isi manual tetap tersedia.');
    if (signal.aborted || owner !== authenticatedOwner) throw new Error('Scan dibatalkan.');
    await setAIConsent(true);
  }
  if (signal.aborted || owner !== authenticatedOwner) throw new Error('Scan dibatalkan.');
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
  const requestedRepository = repository, requestedTimezone = state.timezone, revision = ++reportRevision;
  let value: Report;
  if (requestedRepository instanceof DemoRepository) { value = reportFor(state.data, from, to, requestedTimezone); }
  else {
    const end = new Date(`${to}T00:00:00Z`); end.setUTCDate(end.getUTCDate() + 1);
    value = await requestedRepository.report(fromZonedTime(from, requestedTimezone), fromZonedTime(end.toISOString().slice(0, 10), requestedTimezone));
  }
  if (revision === reportRevision && requestedRepository === repository && requestedTimezone === state.timezone) report.value = value;
}
function activateSession(user: { id: string; email?: string }) {
  if (!client) return;
  if (authenticatedOwner !== user.id || !(repository instanceof RemoteRepository)) {
    resolveAIConsent(false); aiConsent.value = undefined;
    state.timezone = 'Asia/Jakarta';
    authenticatedOwner = user.id;
    try { onboardingPending.value = !hasCompletedOnboarding(localStorage, user.id); }
    catch { onboardingPending.value = true; }
    repository = new RemoteRepository(client);
    state.data = emptySnapshot(); state.loaded = false; state.loading = false; state.loadError = ''; state.error = ''; attachments.clear();
    report.value = { personalIncome: '0', personalExpense: '0', categories: [] };
  }
  state.email = user.email ?? ''; state.mode = 'authenticated';
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
    if (event === 'SIGNED_OUT' && state.mode === 'authenticated') { resolveAIConsent(false); aiConsent.value = undefined; state.mode = 'signedOut'; state.data = emptySnapshot(); state.loaded = false; state.loading = false; state.loadError = ''; repository = new DemoRepository(); authenticatedOwner = undefined; attachments.clear(); }
    if (event === 'PASSWORD_RECOVERY') { state.recovery = true; return; }
    if (session?.user.email_confirmed_at && event !== 'TOKEN_REFRESHED' && state.mode !== 'demo' && !state.recovery) { activateSession(session.user); setTimeout(() => void load(), 0); }
  });
  const { data: { session } } = await client.auth.getSession();
  if (session?.user.email_confirmed_at) {
    activateSession(session.user);
    const { data: profile } = await client.from('profiles').select('timezone,theme').eq('user_id', session.user.id).single();
    if (authenticatedOwner !== session.user.id || state.mode !== 'authenticated') return;
    if (profile?.timezone && ['Asia/Jakarta','Asia/Makassar','Asia/Jayapura','UTC'].includes(profile.timezone)) state.timezone = profile.timezone;
    if (profile?.theme && ['system','light','dark'].includes(profile.theme)) setTheme(profile.theme);
    await load();
  }
}
export const today = () => localDay(new Date().toISOString(), state.timezone);
export function preferences() {
  localStorage.setItem('danarapi.hide', String(state.hideAmounts)); localStorage.setItem('danarapi.timezone', state.timezone);
  if (repository instanceof DemoRepository) { repository.timezone = state.timezone; state.data = derive(state.data, state.timezone); }
  if (client && state.mode === 'authenticated') void saveProfile();
}
async function saveProfile() {
  if (!client) return;
  const { data: { session } } = await client.auth.getSession(); if (!session) return;
  const { error } = await client.from('profiles').update({ theme: state.theme }).eq('user_id', session.user.id);
  if (error) state.notice = 'Preferensi tersimpan di perangkat; profil server belum diperbarui.';
  else await load();
}
