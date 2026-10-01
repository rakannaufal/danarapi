import { defineConfig, loadEnv } from 'vite';
import vue from '@vitejs/plugin-vue';
import { fileURLToPath } from 'node:url';
import { localScanHandler } from './server/local-receipt-scan.ts';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, fileURLToPath(new URL('../../supabase', import.meta.url)), '');
  return { plugins: [vue(), {
    name: 'local-receipt-scan', apply: 'serve',
    configureServer(server) {
      const handler = localScanHandler({ enabled: env.LOCAL_RECEIPT_SCAN === '1', apiKey: env.GEMINI_API_KEY ?? '', model: env.GEMINI_MODEL || 'gemini-3.5-flash-lite', fallbackModel: env.GEMINI_FALLBACK_MODEL || undefined, dailyLimit: Number(env.SCAN_DAILY_LIMIT || 50), interval: Number(env.SCAN_INTERVAL_MS || 4000) });
      server.middlewares.use('/__local/receipt-scan', (request, response) => { void handler(request, response); });
    },
  }], envDir: '../..', server: { port: 5173, strictPort: true }, build: { sourcemap: false } };
});
