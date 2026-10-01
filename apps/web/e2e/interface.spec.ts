import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.route('**/__local/receipt-scan', route => route.fulfill({ json: { configured: false } }));
  await page.goto('/'); await page.getByRole('button', { name: /Coba Demo/ }).click();
});

for (const width of [390, 1440]) for (const theme of ['light', 'dark']) {
  test(`minimal interface across every page ${width} ${theme}`, async ({ page }, info) => {
    await page.setViewportSize({ width, height: 900 });
    await page.evaluate(value => document.documentElement.dataset.theme = value, theme);
    for (const route of ['home', 'transactions', 'review', 'reports', 'budgets', 'goals', 'settings', 'privacy']) {
      await page.goto(`/#${route}`);
      await expect(page.locator('#main-content h1')).toBeVisible();
      await expect(page.locator('#main-content')).not.toContainText(/Google\s+Gemini|Gemini/);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), route).toBe(true);
      if (route === 'budgets') {
        await expect(page.getByLabel('Limit bulanan', { exact: true })).toHaveCount(0);
        await expect(page.getByRole('button', { name: 'Tambah anggaran', exact: true })).toBeVisible();
      }
      if (route === 'transactions') {
        await expect(page.getByRole('button', { name: 'Filter', exact: true })).toHaveAttribute('aria-expanded', 'false');
        await expect(page.getByLabel('Dari tanggal', { exact: true })).not.toBeVisible();
      }
      if (route === 'review') {
        await expect(page.getByLabel('Baca struk otomatis')).toHaveCount(0);
        await expect(page.getByText('Privasi foto', { exact: true })).toHaveCount(0);
      }
      const result = await new AxeBuilder({ page }).include('#main-content').withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
      expect(result.violations, `${route}: ${JSON.stringify(result.violations)}`).toEqual([]);
      await page.screenshot({ path: `artifacts/visual/${info.project.name}/interface/${route}-${width}-${theme}.png` });
    }
  });
}

test('collapsed filters remain editable; budget overview preserves creation and editing', async ({ page }) => {
  await page.goto('/#transactions');
  await page.getByRole('button', { name: 'Filter', exact: true }).click();
  await page.getByRole('combobox', { name: 'Jenis', exact: true }).selectOption('income');
  await page.getByRole('button', { name: 'Filter (1)', exact: true }).click();
  await expect(page.getByText('1 filter aktif', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Reset filter', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Filter', exact: true })).toHaveAttribute('aria-expanded', 'false');
  await page.goto('/#budgets');
  await page.getByRole('button', { name: 'Tambah anggaran', exact: true }).click();
  await expect(page.locator('.preset-chip')).toHaveCount(10);
  await page.getByRole('button', { name: 'Hiburan', exact: true }).click();
  await page.getByLabel('Limit bulanan', { exact: true }).fill('200000');
  await page.getByRole('button', { name: 'Simpan anggaran', exact: true }).click();
  const budget = page.locator('.budget-card').filter({ hasText: 'Hiburan' });
  await expect(budget).toContainText('Rp200.000');
  await budget.getByRole('button', { name: 'Ubah limit', exact: true }).click();
  await expect(page.getByLabel('Limit bulanan', { exact: true })).toHaveValue('200.000');
  await page.getByLabel('Limit bulanan', { exact: true }).fill('300000');
  await page.getByRole('button', { name: 'Simpan anggaran', exact: true }).click();
  await expect(budget).toContainText('Rp300.000');
});

test('target metadata keeps keyboard order without manual progress fields', async ({ page }) => {
  await page.getByRole('button', { name: 'Catat baru', exact: true }).click();
  await page.getByRole('button', { name: 'Target', exact: true }).click();
  await expect(page.getByLabel('Sudah terkumpul (Rp)', { exact: true })).toHaveCount(0);
  await page.getByLabel('Tanggal target', { exact: true }).focus();
  await page.keyboard.press('Tab');
  await expect(page.getByRole('button', { name: 'Simpan target', exact: true })).toBeFocused();
  await page.keyboard.press('Shift+Tab');
  await expect(page.getByLabel('Tanggal target', { exact: true })).toBeFocused();
});
