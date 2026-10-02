import { expect, test, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import content from '../../../contracts/product-content.json' with { type: 'json' };

async function enterDemo(page: Page) {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.route('**/functions/v1/product-info', route => route.fulfill({ json: { policyVersion: content.version, supportEmail: null, authentication: 'available', scanConfigured: true, checkedAt: '2026-10-02T00:00:00Z' } }));
  await page.goto('/');
  await page.getByRole('button', { name: 'Coba Demo', exact: true }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Lewati tur', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Ringkasan keuangan', exact: true })).toBeVisible();
}

for (const theme of ['light', 'dark']) {
  test(`desktop cards have equal dimensions and aligned amounts ${theme}`, async ({ page }, info) => {
    await page.setViewportSize({ width: 1440, height: 1000 });
    await enterDemo(page);
    await page.evaluate(value => { document.documentElement.dataset.theme = value; }, theme);
    const metrics = await page.locator('.home-summary-grid > .card').evaluateAll(elements => elements.map(element => {
      const bounds = element.getBoundingClientRect();
      return { top: bounds.top, width: bounds.width, height: bounds.height, valueTop: element.querySelector('strong')!.getBoundingClientRect().top };
    }));
    expect(metrics).toHaveLength(4);
    for (const metric of metrics) {
      expect(Math.abs(metric.width - metrics[0].width)).toBeLessThan(1);
      expect(Math.abs(metric.height - metrics[0].height)).toBeLessThan(1);
      expect(Math.abs(metric.top - metrics[0].top)).toBeLessThan(1);
      expect(Math.abs(metric.valueTop - metrics[0].valueTop)).toBeLessThan(1);
    }
    for (const selector of ['.home-page .planning-grid > .card', '.home-detail-grid > .card']) {
      const cards = await page.locator(selector).evaluateAll(elements => elements.map(element => ({ width: element.getBoundingClientRect().width, height: element.getBoundingClientRect().height })));
      expect(cards).toHaveLength(2);
      expect(Math.abs(cards[0].width - cards[1].width)).toBeLessThan(1);
      expect(Math.abs(cards[0].height - cards[1].height)).toBeLessThan(1);
    }
    expect((await new AxeBuilder({ page }).include('#main-content').include('.sidebar').analyze()).violations).toEqual([]);
    await page.screenshot({ path: `/tmp/danarapi-workspace-redesign/${info.project.name}-home-desktop-${theme}.png`, fullPage: true });
  });
}

test('account, planning and transfer features are directly accessible', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 960 });
  await enterDemo(page);
  await page.getByRole('button', { name: 'Lihat saldo akun', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Akun keuangan', exact: true })).toBeVisible();
  await expect(page.locator('.settings-tabs')).toHaveCount(0);
  await page.getByRole('button', { name: 'Transfer antar akun', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Transfer antar akun' })).toBeVisible();
  await page.getByRole('button', { name: 'Tutup', exact: true }).click();
  await page.getByRole('navigation', { name: 'Rencana dan akun' }).getByRole('link', { name: 'Target', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Target tabungan', exact: true })).toBeVisible();
  await page.getByRole('navigation', { name: 'Rencana dan akun' }).getByRole('link', { name: 'Anggaran', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Anggaran', exact: true })).toBeVisible();
});

test('scan separates receipt and QRIS with camera, gallery and receipt PDF', async ({ page }) => {
  await enterDemo(page);
  await page.goto('/#review');
  await expect(page.getByRole('button', { name: 'Struk', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('.scan-source-camera')).toBeVisible();
  await expect(page.getByRole('button', { name: /^Galeri/ })).toBeVisible();
  await expect(page.getByRole('button', { name: /^PDF/ })).toBeVisible();
  await expect(page.getByLabel('Ambil foto struk atau QRIS')).toHaveAttribute('capture', 'environment');
  await page.getByRole('button', { name: 'QRIS', exact: true }).click();
  await expect(page.getByRole('button', { name: /^PDF/ })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Tempel teks', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'QRIS', exact: true })).toHaveAttribute('aria-pressed', 'true');
});

test('about and searchable help display the shared product catalog', async ({ page }) => {
  await enterDemo(page);
  await page.goto('/#about');
  await expect(page.locator('.product-feature')).toHaveCount(content.features.length);
  for (const feature of content.features) {
    await expect(page.locator('.product-feature').filter({ has: page.getByRole('heading', { name: feature.title, exact: true }) })).toContainText(feature.description);
  }
  await page.goto('/#faq');
  await expect(page.getByRole('heading', { name: content.help.gettingStartedTitle, exact: true })).toBeVisible();
  await expect(page.locator('.help-guide')).toHaveCount(3);
  await page.getByRole('group', { name: 'Topik bantuan' }).getByRole('button', { name: 'Scan', exact: true }).click();
  await expect(page.locator('.product-answer')).toHaveCount(content.faq.filter(answer => answer.topic === 'Scan').length);
  await page.getByRole('searchbox', { name: 'Cari bantuan', exact: true }).fill('tidak-ada-jawaban-ini');
  await expect(page.getByRole('heading', { name: content.help.emptyTitle, exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Kontak', exact: true })).toBeVisible();
  await page.getByRole('searchbox', { name: 'Cari bantuan', exact: true }).fill('');
  await page.getByRole('group', { name: 'Topik bantuan' }).getByRole('button', { name: 'Semua', exact: true }).click();
  expect((await new AxeBuilder({ page }).include('#main-content').analyze()).violations).toEqual([]);
});

for (const theme of ['light', 'dark']) {
  test(`mobile scan remains prominent and unclipped when active ${theme}`, async ({ page }, info) => {
    await page.setViewportSize({ width: 390, height: 960 });
    await enterDemo(page);
    await page.evaluate(value => { document.documentElement.dataset.theme = value; }, theme);
    await page.goto('/#review');
    const navigation = page.getByRole('navigation', { name: 'Navigasi ponsel' });
    await expect(navigation.locator('.scan-link')).toHaveAttribute('aria-current', 'page');
    const layout = await navigation.evaluate(element => {
      const icon = element.querySelector<HTMLElement>('.scan-disc')!;
      const bounds = icon.getBoundingClientRect();
      const navigationTop = element.getBoundingClientRect().top;
      const smallIconsInside = [...element.querySelectorAll<HTMLElement>('a:not(.scan-link) .bottom-icon')].every(item => item.getBoundingClientRect().top >= navigationTop && getComputedStyle(item).backgroundColor === 'rgba(0, 0, 0, 0)');
      const labels = [...element.querySelectorAll<HTMLElement>('a > span:last-child')].map(item => item.getBoundingClientRect().top);
      return { top: bounds.top, width: bounds.width, height: bounds.height, navigationTop, smallIconsInside, labelsAligned: Math.max(...labels) - Math.min(...labels) < 1, overflow: getComputedStyle(element).overflowY, background: getComputedStyle(icon).backgroundColor, primaryBackground: getComputedStyle(document.querySelector('.add-button')!).backgroundColor };
    });
    expect(layout.top).toBeLessThan(layout.navigationTop);
    expect(layout.navigationTop - layout.top).toBeLessThanOrEqual(20);
    expect(layout.width).toBe(60);
    expect(layout.height).toBe(60);
    expect(layout.smallIconsInside).toBe(true);
    expect(layout.labelsAligned).toBe(true);
    expect(layout.overflow).toBe('visible');
    expect(layout.background).toBe(layout.primaryBackground);
    await page.screenshot({ path: `/tmp/danarapi-workspace-redesign/${info.project.name}-scan-mobile-${theme}.png` });
  });
}

for (const width of [320, 390, 834, 1440]) {
  test(`all page layouts fit viewport ${width}`, async ({ page }, info) => {
    await page.setViewportSize({ width, height: 960 });
    await enterDemo(page);
    for (const route of ['home', 'transactions', 'accounts', 'goals', 'budgets', 'review', 'reports', 'settings', 'about', 'faq', 'contact', 'privacy', 'terms', 'delete-account', 'status']) {
      await page.goto(`/#${route}`);
      await expect(page.locator('#main-content h1').first()).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), route).toBe(true);
      if ([390, 1440].includes(width) && ['transactions', 'accounts', 'goals', 'budgets', 'review', 'reports', 'settings', 'about', 'faq'].includes(route)) {
        await page.screenshot({ path: `/tmp/danarapi-workspace-redesign/${info.project.name}-${route}-${width}.png`, fullPage: true });
      }
    }
    await page.goto('/#home');
    await page.evaluate(() => { document.documentElement.style.fontSize = '200%'; });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
    await page.screenshot({ path: `/tmp/danarapi-workspace-redesign/${info.project.name}-home-${width}-text200.png`, fullPage: true });
    for (const route of ['transactions', 'accounts', 'goals', 'budgets', 'review', 'reports', 'settings', 'about', 'faq']) {
      await page.goto(`/#${route}`);
      await expect(page.locator('#main-content h1').first()).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), `${route} with 200% text`).toBe(true);
    }
  });
}
