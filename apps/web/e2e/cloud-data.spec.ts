import { expect, test, type Page } from '@playwright/test';
import { emptySnapshot } from '../src/domain.ts';

const owner = '90000000-0000-4000-8000-000000000001';

async function session(page: Page) {
  await page.addInitScript(({ userID }) => {
    const expires = Math.floor(Date.now() / 1000) + 3600;
    const token = `${btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))}.${btoa(JSON.stringify({ sub: userID, exp: expires }))}.synthetic-signature`;
    sessionStorage.setItem('danarapi.auth', JSON.stringify({ access_token: token, refresh_token: 'synthetic-refresh', token_type: 'bearer', expires_in: 3600, expires_at: expires, user: { id: userID, email: 'synthetic-owner@example.invalid', email_confirmed_at: '2026-10-01T00:00:00Z', aud: 'authenticated', role: 'authenticated', app_metadata: { provider: 'google' }, user_metadata: {} } }));
  }, { userID: owner });
  await page.route('**/rest/v1/profiles?**', route => route.fulfill({ json: { timezone: 'Asia/Jakarta', theme: 'light' } }));
  await page.route('**/auth/v1/logout**', route => route.fulfill({ status: 204 }));
}

test('missing backend never displays fake zero balances; retry restores the dashboard', async ({ page }) => {
  await session(page);
  let available = false;
  const data = emptySnapshot();
  data.accounts.push({ id: '90000000-0000-4000-8000-000000000002', name: 'Tunai', kind: 'cash', openingBalance: '0', balance: '0', openedAt: '2026-10-01T00:00:00Z', version: 1, archived: false });
  await page.route('**/functions/v1/ios-data/dashboard', route => available ? route.fulfill({ json: data }) : route.fulfill({ status: 404, json: { code: 'NOT_FOUND', message: 'Requested function was not found' } }));
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Data belum dapat dimuat' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('Layanan cloud belum tersedia');
  await expect(page.getByText('Saldo semua akun')).toHaveCount(0);
  await page.getByRole('link', { name: 'Transaksi', exact: true }).first().click();
  await expect(page.getByRole('heading', { name: 'Data belum dapat dimuat' })).toBeVisible();
  available = true;
  await page.getByRole('button', { name: 'Coba lagi', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Lewati tur', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Data belum dapat dimuat' })).toHaveCount(0);
  await page.getByRole('link', { name: 'Beranda', exact: true }).first().click();
  await expect(page.getByText('Saldo semua akun')).toBeVisible();
});

test('blocked network presents a readable error and permits logout', async ({ page }) => {
  await session(page);
  await page.route('**/functions/v1/**', route => route.abort('failed'));
  await page.goto('/');
  await expect(page.getByRole('alert')).toContainText('Tidak dapat terhubung ke layanan cloud');
  await expect(page.getByRole('alert')).not.toContainText('Failed to fetch');
  await page.getByRole('button', { name: 'Keluar', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Lanjutkan dengan Google' })).toBeVisible();
});
