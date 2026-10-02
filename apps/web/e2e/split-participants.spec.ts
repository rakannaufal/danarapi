import { test, expect, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { mkdir } from 'node:fs/promises';

async function openSplit(page: Page) {
  await page.route('**/__local/receipt-scan', route => route.fulfill({ json: { configured: false } }));
  await page.goto('/');
  await page.getByRole('button', { name: /Coba Demo/ }).click(); await page.getByRole('dialog').getByRole('button', { name: 'Lewati tur', exact: true }).click();
  await page.getByRole('button', { name: 'Catat baru', exact: true }).click();
  await page.getByRole('button', { name: /^Split bill/ }).click();
}

test('receipt starts with Saya; accessible plus adds names; removal clears assignments', async ({ page }, info) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await openSplit(page);
  await expect(page.locator('.receipt-chip')).toHaveCount(1);
  await expect(page.locator('.receipt-chip')).toHaveText('Saya');
  const add = page.getByRole('button', { name: 'Tambah orang', exact: true });
  await expect(add).toHaveText('');
  await expect(add).toBeDisabled();
  await page.getByLabel('Nama orang', { exact: true }).fill('Raka');
  await add.click();
  await expect(page.locator('.receipt-chip')).toHaveCount(2);
  await expect(page.getByLabel('Nama orang', { exact: true })).toHaveValue('');
  await page.getByLabel('Nama orang', { exact: true }).fill('Raka');
  await add.click();
  await expect(page.getByRole('alert')).toContainText('Nama peserta tidak boleh sama');
  await expect(page.locator('.receipt-chip')).toHaveCount(2);
  await page.getByLabel('Nama orang', { exact: true }).fill('Dina');
  await page.getByLabel('Nama orang', { exact: true }).press('Enter');
  await expect(page.locator('.receipt-chip')).toHaveCount(3);
  await page.getByLabel('Nama menu 1', { exact: true }).fill('Makan bersama');
  await page.getByLabel('Harga menu 1', { exact: true }).fill('10000');
  await page.locator('.receipt-owners').getByLabel('Raka', { exact: true }).check();
  await page.getByRole('combobox', { name: 'Pembayar', exact: true }).selectOption({ label: 'Raka' });
  await page.getByRole('button', { name: 'Hapus peserta Raka', exact: true }).click();
  await expect(page.getByRole('combobox', { name: 'Pembayar', exact: true })).toHaveValue('self');
  await expect(page.getByText('Belum ada pemesan: Makan bersama.')).toBeVisible();
  await page.getByRole('button', { name: 'Hapus peserta Dina', exact: true }).click();
  await expect(page.locator('.receipt-chip')).toHaveCount(1);
  expect((await new AxeBuilder({ page }).include('dialog').analyze()).violations).toEqual([]);
  const dimensions = await add.boundingBox();
  expect(dimensions?.width).toBeGreaterThanOrEqual(44);
  expect(dimensions?.height).toBeGreaterThanOrEqual(44);
  await mkdir('/tmp/danarapi-participant-qa', { recursive: true });
  await page.screenshot({ path: `/tmp/danarapi-participant-qa/${info.project.name}-receipt.png` });
});

test('total split starts with Saya; plus adds editable participant; can return to Saya', async ({ page }) => {
  await openSplit(page);
  await page.getByRole('button', { name: 'Bagi total', exact: true }).click();
  await expect(page.locator('.member-row')).toHaveCount(1);
  await expect(page.getByRole('textbox', { name: 'Nama peserta 1', exact: true })).toHaveValue('Saya');
  const add = page.getByRole('button', { name: 'Tambah peserta', exact: true });
  await expect(add).toHaveText('');
  await add.click();
  await page.getByRole('textbox', { name: 'Nama peserta 2', exact: true }).fill('Raka');
  await page.getByRole('textbox', { name: 'Total tagihan', exact: true }).fill('10001');
  await expect(page.locator('.member-share')).toHaveText(['Rp5.001', 'Rp5.000']);
  await page.getByRole('combobox', { name: 'Pembayar', exact: true }).selectOption({ label: 'Raka' });
  await page.getByRole('button', { name: 'Hapus peserta Raka', exact: true }).click();
  await expect(page.locator('.member-row')).toHaveCount(1);
  await expect(page.getByRole('combobox', { name: 'Pembayar', exact: true })).toHaveValue('self');
  expect((await new AxeBuilder({ page }).include('dialog').analyze()).violations).toEqual([]);
});
