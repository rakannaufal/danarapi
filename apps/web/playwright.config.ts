import { defineConfig } from '@playwright/test';
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://127.0.0.1:5173';
export default defineConfig({
  testDir: './e2e', fullyParallel: false, workers: 1,
  timeout: 45000, expect: { timeout: 8000 },
  outputDir: './test-results', reporter: [['list'], ['html', { open: 'never' }]],
  use: { baseURL, trace: 'retain-on-failure', screenshot: 'only-on-failure' },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
    { name: 'firefox', use: { browserName: 'firefox' } },
    { name: 'webkit', use: { browserName: 'webkit' } },
  ],
  webServer: { command: `npm run dev -- --port ${new URL(baseURL).port}`, env: { VITE_LOCAL_RECEIPT_SCAN: 'true' }, url: baseURL, reuseExistingServer: !process.env.CI },
});
