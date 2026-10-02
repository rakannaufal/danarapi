import { test, expect, type Page } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import AxeBuilder from '@axe-core/playwright';

async function openReceipt(page: Page) {
  await page.goto('/'); await page.getByRole('button', { name: /Coba Demo/ }).click(); await page.getByRole('dialog').getByRole('button', { name: 'Lewati tur', exact: true }).click();
  await page.getByRole('button', { name: 'Catat baru' }).click(); await page.getByRole('button', { name: /^Split bill/ }).click();
}
test('manual receipt entry recomputes without focus loss, saves details, survives editing', async ({ page }) => {
  await openReceipt(page);
  await expect(page.locator('.receipt-chip')).toHaveCount(1);
  await expect(page.locator('.receipt-chip')).toHaveText('Saya');
  await page.getByLabel('Nama orang', { exact: true }).fill('Teman');
  await page.getByRole('button', { name: 'Tambah orang', exact: true }).click();
  expect((await new AxeBuilder({ page }).include('dialog').analyze()).violations).toEqual([]);
  await page.getByLabel('Nama menu 1', { exact: true }).fill('Nasi bersama'); await page.getByLabel('Harga menu 1', { exact: true }).fill('10000');
  await expect(page.getByText('Belum ada pemesan: Nasi bersama.')).toBeVisible();
  await page.locator('.receipt-owners').getByLabel('Saya', { exact: true }).check(); await page.locator('.receipt-owners').getByLabel('Teman', { exact: true }).check();
  await expect(page.locator('.receipt-result tfoot')).toContainText('Rp11.500');
  await page.getByLabel('Diskon (Rp)', { exact: true }).fill('1000'); await page.getByLabel('Pembulatan struk (Rp)', { exact: true }).fill('-1');
  await expect(page.locator('.receipt-result tfoot')).toContainText('Rp10.349');
  await page.getByLabel('Harga sudah termasuk pajak dan service', { exact: true }).check();
  await expect(page.locator('.receipt-result tfoot')).toContainText('Rp8.999');
  await page.getByRole('button', { name: 'Per orang', exact: true }).click();
  await page.getByRole('combobox', { name: 'Pilih pemesan', exact: true }).selectOption({ label: 'Teman' });
  await expect(page.locator('.receipt-owners').getByRole('checkbox')).toHaveCount(1);
  await page.getByRole('button', { name: 'Per menu', exact: true }).click();
  const price = page.getByLabel('Harga menu 1', { exact: true }); await price.focus(); await price.press('End'); await price.press('Backspace'); await expect(price).toBeFocused();
  await price.fill('10000'); await page.getByLabel('Nama tagihan', { exact: true }).fill('Receipt E2E');
  await page.getByRole('button', { name: 'Simpan tagihan', exact: true }).click(); await expect(page.locator('dialog')).toHaveCount(0);
  await page.locator('.home-bills .bill-row').filter({ hasText: 'Receipt E2E' }).click();
  await page.getByRole('button', { name: /Ubah/ }).click();
  await expect(page.getByLabel('Nama menu 1', { exact: true })).toHaveValue('Nasi bersama'); await expect(page.getByLabel('Diskon (Rp)', { exact: true })).toHaveValue('1.000');
  await expect(page.locator('.receipt-chip')).toHaveCount(2);
  await expect(page.locator('.receipt-chip').filter({ hasText: 'Teman' })).toBeVisible();
});
test('scan unavailable in demo leaves manual form usable; Enter adds participant', async ({ page }) => {
  await page.route('**/__local/receipt-scan', route => route.fulfill({ contentType: 'application/json', body: JSON.stringify({ configured: false }) }));
  await openReceipt(page);
  await expect(page.getByText('Privasi foto', { exact: true })).toHaveCount(0);
  const png = Buffer.from(await page.evaluate(() => { const canvas = document.createElement('canvas'); canvas.width = 64; canvas.height = 64; const context = canvas.getContext('2d')!; context.fillStyle = 'white'; context.fillRect(0, 0, 64, 64); return canvas.toDataURL('image/png').split(',')[1]!; }), 'base64');
  await page.locator('.scan-actions input[type=file]').last().setInputFiles({ name: 'receipt.png', mimeType: 'image/png', buffer: png });
  await expect(page.getByText(scanMessages.config_error, { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Isi manual', exact: true }).click();
  await page.getByLabel('Nama orang', { exact: true }).fill('Ani'); await page.getByLabel('Nama orang', { exact: true }).press('Enter');
  await expect(page.locator('.receipt-chip').filter({ hasText: 'Ani' })).toBeVisible(); await expect(page.locator('.receipt-owners').getByLabel('Ani', { exact: true })).toBeVisible();
});
test('receipt review highlights differences, updates locally, confirms override, escapes model text', async ({ page }) => {
  const receipt = { merchant: 'ABC', date: '2026-10-01', items: [{ name: '<img src=x onerror="window.injected=1">', qty: 1, unit_price: 10000, line_total: 9000, note: null }], subtotal: 10000, service_charge: 500, tax: 1000, discount: 0, rounding: 0, grand_total: 11500, tax_included_in_price: false, unreadable_fields: [] };
  await page.route('**/__receipt-review', route => route.fulfill({ contentType: 'text/html', body: `<html lang="id"><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div id="app"></div><script type="module">import {createApp,h} from '/node_modules/.vite/deps/vue.js';import Review from '/src/components/ReceiptScanReview.vue';createApp({render(){return h(Review,{initialReceipt:${JSON.stringify(receipt).replace(/</g, '\\u003c')},onApply:data=>{window.reviewResult=data}})}}).mount('#app');</script></body></html>` }));
  let scanRequests = 0; page.on('request', request => { if (request.url().includes('receipt-scan')) scanRequests++; });
  await page.goto('/__receipt-review'); await expect(page.locator('.scan-line.problematic')).toHaveCount(1);
  await page.getByText('Perlu dikoreksi', { exact: true }).click();
  await expect(page.getByText(/Selisih Rp 1.000/i)).toHaveCount(2);
  await page.getByLabel('Total baris', { exact: true }).fill('10000');
  await expect(page.locator('.scan-validation')).toHaveCount(0);
  await page.getByLabel('Total struk', { exact: true }).fill('99999');
  await expect(page.getByRole('button', { name: 'Lanjut, saya sudah memeriksa' })).toBeVisible();
  page.once('dialog', dialog => dialog.accept()); await page.getByRole('button', { name: 'Lanjut, saya sudah memeriksa' }).click();
  expect(await page.evaluate(() => (window as any).reviewResult.grand_total)).toBe(99999); expect(await page.evaluate(() => (window as any).injected)).toBeUndefined(); expect(scanRequests).toBe(0);
});
test('receipt layout fits phone and desktop, light and dark', async ({ page, browserName }) => {
  await mkdir(`artifacts/visual/${browserName}/receipt-scan`, { recursive: true });
  for (const theme of ['light', 'dark']) for (const width of [390, 1440]) {
    await page.setViewportSize({ width, height: 900 }); await page.emulateMedia({ colorScheme: theme as 'light' | 'dark' }); await openReceipt(page);
    expect(await page.locator('.receipt-split').evaluate(element => getComputedStyle(element).backgroundColor)).toBe(theme === 'dark' ? 'rgb(10, 22, 36)' : 'rgb(251, 252, 251)');
    await page.getByLabel('Nama menu 1', { exact: true }).fill('Nasi goreng bersama'); await page.getByLabel('Harga menu 1', { exact: true }).fill('10000'); await page.locator('.receipt-owners').getByLabel('Saya', { exact: true }).check();
    await page.locator('dialog').evaluate(element => { element.scrollTop = 0; });
    await page.locator('dialog').screenshot({ path: `artifacts/visual/${browserName}/receipt-scan/${width}-${theme}.png` });
    await page.locator('.receipt-result').scrollIntoViewIfNeeded();
    await page.locator('dialog').screenshot({ path: `artifacts/visual/${browserName}/receipt-scan/${width}-${theme}-results.png` });
    expect(await page.locator('dialog').evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
  }
});
import { scanMessages } from '../src/receipt.ts';
