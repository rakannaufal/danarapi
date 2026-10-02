import { cloudProject } from '../apps/web/src/cloud.ts';

const backendOnly = process.argv.includes('--backend-only');
const originIndex = process.argv.indexOf('--origin');
const origin = originIndex >= 0 ? process.argv[originIndex + 1] : undefined;
if (originIndex >= 0 && (!origin || new URL(origin).origin !== origin || !['https:', 'http:'].includes(new URL(origin).protocol))) throw new Error('Gunakan --origin dengan origin web lengkap tanpa path.');
let ready = true;
const headers = { apikey: cloudProject.key, 'content-type': 'application/json' };

async function probe(path, method = 'GET', body, extraHeaders = {}) {
  try {
    const response = await fetch(`${cloudProject.url}${path}`, { method, headers: { ...headers, ...extraHeaders }, ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(15000) });
    return { status: response.status, headers: response.headers, data: await response.json().catch(() => ({})) };
  } catch { return { status: 0, headers: new Headers(), data: {} }; }
}

function report(label, passed, detail) {
  console.log(`${passed ? 'OK' : 'BELUM SIAP'} ${label}: ${detail}`);
  if (!passed) ready = false;
}

console.log(`Proyek: ${cloudProject.url}`);
const auth = await probe('/auth/v1/settings');
report('Supabase Auth', auth.status === 200, `HTTP ${auth.status}`);
if (!backendOnly) report('Login google', auth.data.external?.google === true, auth.data.external?.google === true ? 'aktif; callback tetap perlu uji akun nyata' : 'aktifkan provider dan kredensial di Dashboard');
for (const [table, column] of [['profiles', 'user_id'], ['accounts', 'id'], ['transactions', 'goal_id'], ['review_items', 'confirmed_transaction_id'], ['savings_goal_progress', 'id'], ['ai_consents', 'user_id'], ['support_tickets', 'id']]) {
  const database = await probe(`/rest/v1/${table}?select=${column}&limit=0`);
  report(`Database ${table}`, ['42501', 'PGRST301', 'PGRST302', 'UNAUTHORIZED'].includes(database.data.code), database.status === 404 ? 'schema belum tersedia; cek migrations' : `HTTP ${database.status} ${database.data.code ?? ''}; akses anonim harus ditolak`);
}
const product = await probe('/functions/v1/product-info');
report('Informasi layanan publik', product.status === 200 && product.data.policyVersion === '2026-10-02', `HTTP ${product.status}; versi kebijakan ${product.data.policyVersion ?? 'tidak tersedia'}`);
for (const name of ['ledger', 'ios-data', 'export-data', 'receipt-scan']) {
  const result = await probe(`/functions/v1/${name}`, 'POST', {});
  report(`Fungsi ${name}`, result.status === 401, result.status === 404 ? 'belum terdeploy' : `HTTP ${result.status}; permintaan tanpa sesi harus ditolak`);
  if (origin) {
    const preflight = await probe(`/functions/v1/${name}`, 'OPTIONS', undefined, { origin, 'access-control-request-method': 'POST', 'access-control-request-headers': 'authorization,apikey,content-type' });
    const allowedHeaders = (preflight.headers.get('access-control-allow-headers') ?? '').toLowerCase().split(',').map(value => value.trim());
    const passed = preflight.status >= 200 && preflight.status < 300 && preflight.headers.get('access-control-allow-origin') === origin && (preflight.headers.get('access-control-allow-methods') ?? '').split(',').some(value => value.trim() === 'POST') && ['authorization', 'apikey', 'content-type'].every(value => allowedHeaders.includes(value));
    report(`CORS ${name}`, passed, `HTTP ${preflight.status}; origin ${origin}`);
  }
}
console.log('Pemeriksaan ini tidak membuat akun, mengunggah struk, atau mengubah saldo. Redirect native harus diizinkan di Dashboard: id.danarapi.app://auth/callback. Scan AI dan OAuth tetap memerlukan uji akun nyata.');
process.exitCode = ready ? 0 : 1;
