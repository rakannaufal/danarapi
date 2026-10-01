import { cloudProject } from '../apps/web/src/cloud.ts';

const backendOnly = process.argv.includes('--backend-only');
let ready = true;
const headers = { apikey: cloudProject.key, 'content-type': 'application/json' };

async function probe(path, method = 'GET', body) {
  try {
    const response = await fetch(`${cloudProject.url}${path}`, { method, headers, ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(15000) });
    return { status: response.status, data: await response.json().catch(() => ({})) };
  } catch { return { status: 0, data: {} }; }
}

function report(label, passed, detail) {
  console.log(`${passed ? 'OK' : 'BELUM SIAP'} ${label}: ${detail}`);
  if (!passed) ready = false;
}

console.log(`Proyek: ${cloudProject.url}`);
const auth = await probe('/auth/v1/settings');
report('Supabase Auth', auth.status === 200, `HTTP ${auth.status}`);
if (!backendOnly) report('Login google', auth.data.external?.google === true, auth.data.external?.google === true ? 'aktif; callback tetap perlu uji akun nyata' : 'aktifkan provider dan kredensial di Dashboard');
for (const [table, column] of [['profiles', 'user_id'], ['accounts', 'id'], ['transactions', 'goal_id'], ['review_items', 'confirmed_transaction_id'], ['savings_goal_progress', 'id']]) {
  const database = await probe(`/rest/v1/${table}?select=${column}&limit=0`);
  report(`Database ${table}`, ['42501', 'PGRST301', 'PGRST302', 'UNAUTHORIZED'].includes(database.data.code), database.status === 404 ? 'schema belum tersedia; cek migrations' : `HTTP ${database.status} ${database.data.code ?? ''}; akses anonim harus ditolak`);
}
for (const name of ['ledger', 'ios-data', 'export-data', 'receipt-scan']) {
  const result = await probe(`/functions/v1/${name}`, 'POST', {});
  report(`Fungsi ${name}`, result.status === 401, result.status === 404 ? 'belum terdeploy' : `HTTP ${result.status}; permintaan tanpa sesi harus ditolak`);
}
console.log('Pemeriksaan ini tidak membuat akun, mengunggah struk, atau mengubah saldo. Scan AI dan OAuth tetap memerlukan uji akun nyata.');
process.exitCode = ready ? 0 : 1;
