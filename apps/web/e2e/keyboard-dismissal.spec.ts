import { expect, test } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  await page.route('**/__local/receipt-scan', route => route.fulfill({ json: { configured: false } }));
  await page.goto('/');
  await page.getByRole('button', { name: /Coba Demo/ }).click(); await page.getByRole('dialog').getByRole('button', { name: 'Lewati tur', exact: true }).click();
  await page.getByRole('button', { name: 'Catat baru', exact: true }).click();
  await page.getByRole('button', { name: 'Pengeluaran', exact: true }).click();
});

test('outside tap blurs amount without losing money or blocking save', async ({ page }) => {
  const dialog = page.getByRole('dialog');
  const amount = dialog.getByLabel('Nominal', { exact: true });
  await amount.fill('5000');
  await expect(amount).toBeFocused();
  await dialog.getByRole('heading').click();
  await expect(amount).not.toBeFocused();
  await expect(amount).toHaveValue('5.000');
  await dialog.getByRole('button', { name: 'Simpan catatan', exact: true }).click();
  await expect(dialog).not.toBeVisible();
});

test('input changes and labels retain normal focus', async ({ page }) => {
  const dialog = page.getByRole('dialog');
  const amount = dialog.getByLabel('Nominal', { exact: true });
  const merchant = dialog.getByLabel(/Merchant/);
  await amount.fill('5000');
  await merchant.click();
  await merchant.fill('TOKO KEYBOARD');
  await expect(merchant).toBeFocused();
  await amount.click();
  await expect(amount).toBeFocused();
  await expect(merchant).toHaveValue('TOKO KEYBOARD');
  await dialog.locator('label.amount-input').click({ position: { x: 12, y: 8 } });
  await expect(amount).toBeFocused();
});
