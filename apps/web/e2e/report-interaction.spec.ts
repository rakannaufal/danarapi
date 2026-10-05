import { expect, test } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import content from '../../../contracts/product-content.json' with { type: 'json' };

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.route('**/functions/v1/product-info', route => route.fulfill({ json: { policyVersion: content.version, supportEmail: null, authentication: 'available', scanConfigured: true } }));
  await page.goto('/');
  await page.getByRole('button', { name: 'Coba Demo', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Lewati tur', exact: true }).click();
});

for (const width of [390, 1440]) {
  test(`chart segments show values on pointer, click and keyboard ${width}`, async ({ page }) => {
    await page.setViewportSize({ width, height: 960 });
    await page.goto('/#reports');
    const donut = page.locator('.donut-card').filter({ has: page.getByRole('heading', { name: 'Pemasukan & pengeluaran', exact: true }) });
    const segment = donut.locator('circle.chart-segment').first();
    await segment.scrollIntoViewIfNeeded();
    const point = await segment.evaluate(element => {
      const bounds = (element as SVGElement).ownerSVGElement!.getBoundingClientRect();
      const length = Number(element.getAttribute('stroke-dasharray')!.split(' ')[0]);
      const start = -Number(element.getAttribute('stroke-dashoffset'));
      const angle = (start + length / 2) / 251.327 * Math.PI * 2;
      return { x: bounds.left + (55 + 40 * Math.sin(angle)) / 110 * bounds.width, y: bounds.top + (55 - 40 * Math.cos(angle)) / 110 * bounds.height };
    });
    await page.mouse.move(point.x, point.y);
    const detail = donut.getByRole('status');
    await expect(detail).toContainText('Pemasukan');
    await expect(detail).toContainText('Rp');
    await expect(detail).toContainText('% dari total');
    await page.mouse.click(point.x, point.y);
    await page.getByRole('heading', { name: 'Laporan', exact: true }).hover();
    await expect(detail).toBeVisible();
    await expect(segment).toHaveAttribute('aria-pressed', 'true');
    const expense = donut.locator('circle.chart-segment').last();
    await expense.focus();
    await expense.press('Enter');
    await expect(detail).toContainText('Pengeluaran');
    await expect(expense).toHaveAttribute('aria-pressed', 'true');
    const bar = page.locator('.flow-chart rect.chart-segment').first();
    await bar.click();
    await expect(page.getByRole('status', { name: 'Rincian arus keuangan' })).toContainText('Pemasukan');
    await page.getByRole('button', { name: /Sembunyikan nominal/ }).click();
    await expect(detail).toContainText('Rp••••••');
    await expect(detail).not.toContainText(/Rp[0-9]/);
    await expect(page.getByRole('status', { name: 'Rincian arus keuangan' })).toContainText('Rp••••••');
    expect((await new AxeBuilder({ page }).include('#main-content').analyze()).violations).toEqual([]);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
    await page.screenshot({ path: `/tmp/danarapi-report-interaction-${width}.png`, fullPage: true });
  });
}

test('budget usage shows total and category percentages, cash values stay aligned', async ({ page }) => {
  await page.goto('/#budgets');
  await expect(page.locator('.planning-summary .budget-percent')).toContainText(/\d+% terpakai/);
  await expect(page.locator('.budget-card .budget-percent')).toHaveCount(7);
  for (const badge of await page.locator('.budget-card .budget-percent').all()) await expect(badge).toContainText(/\d+%/);
  await page.goto('/#reports');
  await page.setViewportSize({ width: 390, height: 960 });
  await expect(page.getByRole('heading', { name: 'Arus kas per akun', exact: true })).toBeVisible();
  const metrics = await page.locator('.cash-metrics strong').evaluateAll(elements => elements.map(element => ({ right: element.getBoundingClientRect().right, fontSize: parseFloat(getComputedStyle(element).fontSize) })));
  expect(metrics).toHaveLength(9);
  expect(metrics.every(metric => Math.abs(metric.right - metrics[0].right) < 1 && metric.fontSize >= 14)).toBe(true);
});
