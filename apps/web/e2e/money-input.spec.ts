import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  await page.route('**/__local/receipt-scan', route => route.fulfill({ json: { configured: false } }));
  await page.goto('/');
  await page.getByRole('button', { name: /Coba Demo/ }).click();
});

test('rupiah formatting, caret, deletion, pasted values, canonical saving', async ({ page }, info) => {
  await page.getByRole('button', { name: 'Catat baru' }).click();
  await page.getByRole('button', { name: /^Target$/ }).click();
  await page.getByLabel('Nama target', { exact: true }).fill('Uji format rupiah');
  const amount = page.getByLabel('Total target (Rp)', { exact: true });
  await amount.pressSequentially('5000');
  await expect(amount).toHaveValue('5.000');
  await amount.evaluate((input: HTMLInputElement) => input.setSelectionRange(1, 1));
  await amount.press('1');
  await expect(amount).toHaveValue('51.000');
  expect(await amount.evaluate((input: HTMLInputElement) => input.selectionStart)).toBe(2);
  await amount.evaluate((input: HTMLInputElement) => input.setSelectionRange(3, 3));
  await amount.press('Backspace');
  await expect(amount).toHaveValue('5.000');
  await amount.evaluate((input: HTMLInputElement) => input.setSelectionRange(1, 1));
  await amount.press('Delete');
  await expect(amount).toHaveValue('500');
  await amount.fill('Rp 5.000.000');
  await expect(amount).toHaveValue('5.000.000');
  await amount.fill('0005000');
  await expect(amount).toHaveValue('5.000');
  await amount.fill('1234567890123');
  await expect(amount).toHaveValue('123.456.789.012');
  await amount.fill('');
  await expect(amount).toHaveValue('');
  await amount.fill('500000');
  await expect(page.getByLabel('Sudah terkumpul (Rp)', { exact: true })).toHaveCount(0);
  await page.getByRole('button', { name: 'Simpan target', exact: true }).click();
  await page.locator('.goal-card').filter({ hasText: 'Uji format rupiah' }).getByRole('button', { name: 'Ubah target', exact: true }).click();
  await expect(amount).toHaveValue('500.000');
  await page.setViewportSize({ width: 375, height: 812 });
  await page.screenshot({ path: `artifacts/visual/${info.project.name}/money-input/goal-mobile.png`, fullPage: true });
});

test('receipt correction preserves nullable numbers and signed rounding', async ({ page }) => {
  const receipt = { merchant: 'Uji Rupiah', date: '2026-10-01', items: [{ name: 'Menu', qty: 1, unit_price: null, line_total: null, note: null }], subtotal: 5000, service_charge: 0, tax: 0, discount: 0, rounding: 0, grand_total: 5000, tax_included_in_price: false, unreadable_fields: ['items[0].unit_price'] };
  await page.route('**/__money-review', route => route.fulfill({ contentType: 'text/html', body: `<html lang="id"><body><div id="app"></div><script type="module">import {createApp,h} from '/node_modules/.vite/deps/vue.js';import Review from '/src/components/ReceiptScanReview.vue';createApp({render(){return h(Review,{initialReceipt:${JSON.stringify(receipt)},onApply:data=>{window.reviewResult=data}})}}).mount('#app');</script></body></html>` }));
  await page.goto('/__money-review');
  const unitPrice = page.locator('.scan-line').getByLabel('Harga satuan', { exact: true });
  await expect(unitPrice).toHaveValue('');
  await unitPrice.fill('5000');
  await expect(unitPrice).toHaveValue('5.000');
  await unitPrice.fill('');
  await expect(unitPrice).toHaveValue('');
  await unitPrice.fill('5000');
  await page.locator('.scan-line').getByLabel('Total baris', { exact: true }).fill('5000');
  const rounding = page.getByLabel('Pembulatan (Rp)', { exact: true });
  await rounding.fill('');
  await rounding.pressSequentially('-1000');
  await expect(rounding).toHaveValue('-1.000');
  await page.getByLabel('Total struk', { exact: true }).fill('4000');
  await page.getByRole('button', { name: 'Lanjut pilih pemesan', exact: true }).click();
  const result = await page.evaluate(() => (window as unknown as { reviewResult: { items: { unit_price: number }[]; rounding: number; grand_total: number } }).reviewResult);
  expect(result.items[0]!.unit_price).toBe(5000);
  expect(result.rounding).toBe(-1000);
  expect(result.grand_total).toBe(4000);
});
