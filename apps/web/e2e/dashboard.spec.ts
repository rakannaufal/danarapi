import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.route('**/__local/receipt-scan', route => route.fulfill({ json: { configured: false } }));
  await page.goto('/');
  await page.getByRole('button', { name: /Coba Demo/ }).click(); await page.getByRole('dialog').getByRole('button', { name: 'Lewati tur', exact: true }).click();
});

for (const width of [390, 1440]) for (const theme of ['light', 'dark']) {
  test(`home and report charts remain readable ${width} ${theme}`, async ({ page }, info) => {
    await page.setViewportSize({ width, height: 960 });
    await page.evaluate(value => document.documentElement.dataset.theme = value, theme);
    await expect(page.getByRole('button', { name: 'Lihat saldo akun', exact: true })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
    await page.screenshot({ path: `/tmp/danarapi-dashboard-qa/${info.project.name}-home-${width}-${theme}.png`, fullPage: true });
    await page.goto('/#reports');
    await expect(page.getByRole('img', { name: 'Grafik perbandingan pemasukan dan pengeluaran tiga bulan', exact: true })).toBeVisible();
    await expect(page.getByRole('img', { name: 'Diagram Alokasi pengeluaran', exact: true })).toBeVisible();
    expect(await page.locator('.report-metric h2 .money').evaluateAll(elements => elements.every(element => {
      const bounds = element.getBoundingClientRect();
      const parent = element.closest('.report-metric')!.getBoundingClientRect();
      return bounds.left >= parent.left - 1 && bounds.right <= parent.right + 1 && element.scrollWidth <= element.clientWidth + 1;
    }))).toBe(true);
    const flow = page.locator('.donut-card').filter({ has: page.getByRole('heading', { name: 'Pemasukan & pengeluaran', exact: true }) });
    await expect(flow.locator('circle[stroke="var(--chart-income)"]')).toHaveCount(0);
    await expect(flow.locator('circle[stroke="var(--chart-expense)"]')).toHaveCount(1);
    await expect(flow.getByRole('button').filter({ hasText: 'Pemasukan' }).locator('.chart-dot')).toHaveAttribute('style', /var\(--chart-income\)/);
    await flow.getByRole('button').filter({ hasText: 'Pengeluaran' }).click();
    await expect(flow.locator('.donut-center')).toContainText('Pengeluaran');
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
    const accessibility = await new AxeBuilder({ page }).include('#main-content').withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
    expect(accessibility.violations).toEqual([]);
    await page.screenshot({ path: `/tmp/danarapi-dashboard-qa/${info.project.name}-reports-${width}-${theme}.png`, fullPage: true });
    await page.getByRole('button', { name: /Sembunyikan nominal/ }).click();
    await expect(page.locator('.flow-axis')).toContainText('•••');
    await expect(page.locator('.flow-axis')).not.toContainText(/ribu|juta/);
  });
}

test('home shortcuts open the matching account and transaction filters', async ({ page }) => {
  await page.getByRole('button', { name: 'Lihat saldo akun', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Tambah akun', exact: true })).toBeVisible();
  await page.goto('/#home');
  await page.getByRole('button', { name: 'Lihat pemasukan', exact: true }).click();
  await page.getByRole('button', { name: /^Filter/ }).click();
  await expect(page.getByRole('combobox', { name: 'Jenis', exact: true })).toHaveValue('income');
  await page.goto('/#home');
  await page.getByRole('button', { name: 'Lihat pengeluaran', exact: true }).click();
  await expect(page.getByRole('combobox', { name: 'Jenis', exact: true })).toHaveValue('expense');
});
