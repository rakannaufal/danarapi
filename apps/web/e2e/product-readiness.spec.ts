import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.route('**/__local/receipt-scan',route => route.fulfill({ json: { configured: false } }));
  await page.route('**/functions/v1/product-info',route => route.fulfill({ json: { policyVersion: '2026-10-02',supportEmail: null,authentication: 'available',scanConfigured: true,checkedAt: '2026-10-02T03:00:00Z' } }));
});

test('public legal, deletion, FAQ and contact pages remain accessible without login', async ({ page }) => {
  for (const [path,title] of [['/about','Tentang Danarapi'],['/privacy','Kebijakan privasi'],['/terms','Syarat penggunaan'],['/hapus-akun','Cara menghapus akun'],['/faq','Bantuan'],['/contact','Kontak & bantuan']]) {
    await page.goto(path);
    await expect(page.getByRole('heading',{ name: title,exact: true })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
  }
  await expect(page.getByText('Masuk untuk mengirim laporan privat dan melihat balasan.')).toBeVisible();
  await page.goto('/faq');
  await page.getByRole('searchbox').fill('QRIS');
  await expect(page.locator('.product-answer').filter({ hasText: 'QRIS' }).first()).toBeVisible();
  await page.getByRole('searchbox').fill('tidak-ada-jawaban-sintetis');
  await expect(page.getByText('Tidak ada jawaban yang cocok', { exact: true })).toBeVisible();
});

for (const theme of ['light','dark']) test(`public policy accessible on mobile ${theme}`,async ({ page }) => {
  await page.setViewportSize({ width: 390,height: 844 });
  await page.emulateMedia({ colorScheme: theme === 'dark' ? 'dark' : 'light' });
  await page.goto('/privacy');
  await page.evaluate(value => document.documentElement.dataset.theme = value,theme);
  const result = await new AxeBuilder({ page }).withTags(['wcag2a','wcag2aa','wcag21aa']).analyze();
  expect(result.violations).toEqual([]);
});

test('service status page and navigation are removed',async ({ page }) => {
  for (const path of ['/about', '/contact', '/status', '/#status']) {
    await page.goto(path);
    await expect(page.getByRole('link', { name: 'Status layanan', exact: true })).toHaveCount(0);
    await expect(page.getByRole('heading', { name: 'Status layanan', exact: true })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Periksa layanan', exact: true })).toHaveCount(0);
  }
  await expect(page.getByRole('button', { name: /Coba Demo/ })).toBeVisible();
});

test('target history and annual report are reachable with readable numbers',async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button',{ name: /Coba Demo/ }).click(); await page.getByRole('dialog').getByRole('button', { name: 'Lewati tur', exact: true }).click();
  await page.getByRole('button',{ name: 'Catat baru',exact: true }).click();
  await page.getByRole('button',{ name: 'Target',exact: true }).click();
  await page.getByLabel('Nama target',{ exact: true }).fill('Target riwayat');
  await page.getByLabel('Total target (Rp)',{ exact: true }).fill('1000000');
  await page.getByRole('button',{ name: 'Simpan target',exact: true }).click();
  await page.goto('/#goals');
  await page.getByRole('button',{ name: 'Lihat rincian',exact: true }).first().click();
  await expect(page.getByRole('heading',{ name: 'Riwayat kontribusi',exact: true })).toBeVisible();
  await page.goto('/#reports');
  await page.getByRole('button',{ name: 'Tahunan',exact: true }).click();
  await expect(page.getByText('Perbandingan tiga tahun',{ exact: true })).toBeVisible();
  await page.getByText('Lihat angka per tahun',{ exact: true }).click();
  await expect(page.locator('.flow-values')).toContainText('2026');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
});
