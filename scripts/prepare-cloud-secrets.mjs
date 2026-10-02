import { readFile, writeFile } from 'node:fs/promises';

const [source, destination, requestedOrigin = 'https://danarapi.vercel.app'] = process.argv.slice(2);
if (!source || !destination) throw new Error('Gunakan file konfigurasi server dan tujuan sementara.');
const env = {};
for (const line of (await readFile(source, 'utf8')).split(/\r?\n/)) {
  const match = line.match(/^([A-Z_]+)=(.*)$/);
  if (match) env[match[1]] = match[2].trim().replace(/^(['"])(.*)\1$/, '$2');
}
const origin = new URL(requestedOrigin);
if (origin.username || origin.password || origin.pathname !== '/' || origin.search || origin.hash || (origin.protocol !== 'https:' && !(origin.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(origin.hostname)))) throw new Error('URL web harus berupa origin HTTPS atau localhost pengembangan.');
if (!env.GEMINI_API_KEY || /[\r\n]/.test(env.GEMINI_API_KEY)) throw new Error('GEMINI_API_KEY server belum diisi.');
const model = env.GEMINI_MODEL || 'gemini-3.5-flash-lite';
if (!/^[a-zA-Z0-9._-]+$/.test(model) || (env.GEMINI_FALLBACK_MODEL && !/^[a-zA-Z0-9._-]+$/.test(env.GEMINI_FALLBACK_MODEL))) throw new Error('Nama model tidak valid.');
for (const selected of [model, env.GEMINI_FALLBACK_MODEL].filter(Boolean)) {
  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${selected}`, { headers: { 'x-goog-api-key': env.GEMINI_API_KEY }, signal: AbortSignal.timeout(15000) });
  if (!response.ok) throw new Error(`Model scan tidak tersedia (HTTP ${response.status}). Periksa key, akses model, dan billing penyedia.`);
  const body = await response.json();
  if (!body.supportedGenerationMethods?.includes('generateContent')) throw new Error('Model tidak mendukung ekstraksi.');
}
const daily = Number(env.SCAN_DAILY_LIMIT || 50), interval = Number(env.SCAN_INTERVAL_MS || 4000);
if (!Number.isInteger(daily) || daily < 1 || daily > 10000 || !Number.isInteger(interval) || interval < 0 || interval > 60000) throw new Error('Batas scan tidak valid.');
const secrets = {
  GEMINI_API_KEY: env.GEMINI_API_KEY,
  GEMINI_MODEL: model,
  GEMINI_FALLBACK_MODEL: env.GEMINI_FALLBACK_MODEL || '',
  SCAN_DAILY_LIMIT: daily,
  SCAN_INTERVAL_MS: interval,
  ALLOWED_ORIGIN: origin.origin,
  ALLOWED_ORIGINS: [...new Set([origin.origin, 'http://127.0.0.1:5173', 'http://localhost:5173'])].join(','),
};
if (env.SUPPORT_EMAIL) {
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(env.SUPPORT_EMAIL)) throw new Error('SUPPORT_EMAIL tidak valid.');
  secrets.SUPPORT_EMAIL = env.SUPPORT_EMAIL;
}
await writeFile(destination, Object.entries(secrets).map(([name, value]) => `${name}=${value}`).join('\n') + '\n', { mode: 0o600 });
console.log(`Konfigurasi model ${model} valid. Key tidak ditampilkan.`);
