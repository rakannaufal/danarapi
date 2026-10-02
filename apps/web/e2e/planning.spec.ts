import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test('quick menu, ten categories, custom monthly budget, goal countdown and editing', async ({ page }, info) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.clock.install({ time: new Date('2026-10-01T05:00:00Z') });
  await page.goto('/'); await page.getByRole('button', { name: /Coba Demo/ }).click(); await page.getByRole('dialog').getByRole('button', { name: 'Lewati tur', exact: true }).click();
  await expect(page.locator('.position-strip')).toHaveCount(0);
  await page.getByLabel('Periode beranda').fill('2026-10');
  const balance = await page.locator('.balance-value').innerText();
  await page.getByRole('button', { name: 'Catat baru' }).click();
  await expect(page.locator('.quick-action')).toHaveCount(6);
  await expect(page.locator('.quick-actions').getByRole('button', { name: /^Transfer/ })).toHaveCount(0);
  expect((await new AxeBuilder({ page }).include('dialog').analyze()).violations).toEqual([]);
  await page.screenshot({ path: `artifacts/visual/${info.project.name}/planning/quick-menu.png` });
  await page.getByRole('button', { name: /^Anggaran$/ }).click();
  await expect(page.locator('.preset-chip')).toHaveCount(10);
  await page.getByRole('button', { name: 'Hiburan', exact: true }).click();
  await page.getByLabel('Limit bulanan', { exact: true }).fill('400000');
  await page.getByRole('button', { name: 'Simpan anggaran', exact: true }).click();
  await expect(page.locator('[aria-label="Anggaran bulanan"]')).toContainText('Hiburan');
  await page.getByRole('button', { name: 'Catat baru' }).click(); await page.getByRole('button', { name: /^Anggaran$/ }).click();
  await page.getByRole('combobox', { name: 'Kategori', exact: true }).selectOption('new');
  await page.getByLabel('Nama kategori', { exact: true }).fill('Perawatan hewan');
  await page.getByLabel('Limit bulanan', { exact: true }).fill('300000');
  await page.getByRole('button', { name: 'Simpan anggaran', exact: true }).click();
  await expect(page.locator('[aria-label="Anggaran bulanan"]')).toContainText('Perawatan hewan');
  for (const category of ['Tagihan', 'Kesehatan']) {
    await page.getByRole('button', { name: 'Catat baru' }).click(); await page.getByRole('button', { name: /^Anggaran$/ }).click();
    await page.getByRole('button', { name: category, exact: true }).click();
    await page.getByLabel('Limit bulanan', { exact: true }).fill('100000');
    await page.getByRole('button', { name: 'Simpan anggaran', exact: true }).click();
  }
  await expect(page.locator('.plan-budget')).toHaveCount(4);
  await page.getByRole('button', { name: 'Catat baru' }).click(); await page.getByRole('button', { name: /^Target$/ }).click();
  await expect(page.getByLabel('Nama target', { exact: true })).toBeFocused();
  await page.getByLabel('Nama target', { exact: true }).fill('Dana darurat');
  await page.getByLabel('Total target (Rp)', { exact: true }).fill('5000000');
  await expect(page.getByLabel('Sudah terkumpul (Rp)', { exact: true })).toHaveCount(0);
  await page.getByLabel('Tanggal target', { exact: true }).fill('2026-10-31');
  await page.getByRole('button', { name: 'Simpan target', exact: true }).click();
  await expect(page.locator('.goal-card')).toContainText('30 hari lagi'); await expect(page.locator('.goal-card')).toContainText('0%');
  await expect(page.locator('.balance-value')).toHaveText(balance);
  await page.getByLabel('Periode beranda').fill('2026-11'); await expect(page.locator('[aria-label="Anggaran bulanan"]')).not.toContainText('Perawatan hewan');
  await expect(page.locator('.goal-card')).toContainText('Dana darurat'); await page.getByLabel('Periode beranda').fill('2026-10');
  if (await page.getByRole('button', { name: 'Tutup pemberitahuan' }).isVisible()) await page.getByRole('button', { name: 'Tutup pemberitahuan' }).click();
  await page.screenshot({ path: `artifacts/visual/${info.project.name}/planning/home-desktop.png`, fullPage: true });
  await page.setViewportSize({ width: 375, height: 812 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect((await new AxeBuilder({ page }).include('#main-content').analyze()).violations).toEqual([]);
  await page.screenshot({ path: `artifacts/visual/${info.project.name}/planning/home-mobile.png`, fullPage: true });
  await page.evaluate(() => document.documentElement.dataset.theme = 'dark');
  expect((await new AxeBuilder({ page }).include('#main-content').analyze()).violations).toEqual([]);
  await page.screenshot({ path: `artifacts/visual/${info.project.name}/planning/home-dark.png`, fullPage: true });
  await page.getByRole('button', { name: 'Tambah progres', exact: true }).click();
  await expect(page.getByRole('combobox', { name: 'Target', exact: true })).toHaveValue(/.+/);
  await page.getByLabel('Nominal', { exact: true }).fill('1000000');
  await page.getByRole('button', { name: 'Simpan catatan', exact: true }).click();
  await expect(page.locator('.goal-card')).toContainText('20%');
  await expect(page.locator('.balance-value')).not.toHaveText(balance);
  await page.getByRole('button', { name: 'Catat baru' }).click();
  await page.getByRole('button', { name: /^Pengeluaran$/ }).click();
  await page.getByRole('combobox', { name: 'Kategori', exact: true }).selectOption({ label: 'Target' });
  await page.getByRole('combobox', { name: 'Target', exact: true }).selectOption({ label: 'Dana darurat' });
  await page.getByLabel('Nominal', { exact: true }).fill('4000000');
  await page.getByRole('button', { name: 'Simpan catatan', exact: true }).click();
  await expect(page.locator('.goal-card')).toContainText('Tercapai');
  const contributedBalance = await page.locator('.balance-value').innerText();
  await page.getByRole('button', { name: 'Ubah target', exact: true }).click();
  page.once('dialog', dialog => dialog.accept()); await page.getByRole('button', { name: 'Hapus target', exact: true }).click();
  await expect(page.locator('.goal-card')).toHaveCount(0); await expect(page.locator('.balance-value')).toHaveText(contributedBalance);
});

test('login shows only Google; reports include reconciled allocation charts', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('button', { name: 'Lanjutkan dengan Google' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Lanjutkan dengan Apple' })).toHaveCount(0);
  await expect(page.locator('input[type="password"], input[type="email"]')).toHaveCount(0);
  await page.getByRole('button', { name: /Coba Demo/ }).click(); await page.getByRole('dialog').getByRole('button', { name: 'Lewati tur', exact: true }).click();
  await page.goto('/#reports');
  await expect(page.getByRole('img', { name: 'Diagram Alokasi pengeluaran', exact: true })).toBeVisible();
  await expect(page.getByRole('img', { name: 'Diagram Pemasukan & pengeluaran', exact: true })).toBeVisible();
  await expect(page.getByRole('img', { name: 'Grafik perbandingan pemasukan dan pengeluaran tiga bulan', exact: true })).toBeVisible();
  await page.setViewportSize({ width: 375, height: 812 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect((await new AxeBuilder({ page }).include('#main-content').analyze()).violations).toEqual([]);
});

test('merchant stays inline; budget bars follow actual expense thresholds', async ({ page }) => {
  await page.goto('/'); await page.getByRole('button', { name: /Coba Demo/ }).click(); await page.getByRole('dialog').getByRole('button', { name: 'Lewati tur', exact: true }).click();
  await page.getByRole('button', { name: 'Catat baru' }).click(); await page.getByRole('button', { name: /^Anggaran$/ }).click();
  await page.getByRole('button', { name: 'Hiburan', exact: true }).click();
  await page.getByLabel('Limit bulanan', { exact: true }).fill('100000');
  await page.getByRole('button', { name: 'Simpan anggaran', exact: true }).click();
  const budget = page.locator('.plan-budget').filter({ hasText: 'Hiburan' });
  for (const [amount, status] of [['70000', 'warning'], ['30000', 'warning'], ['1', 'over']]) {
    await page.getByRole('button', { name: 'Catat baru' }).click(); await page.getByRole('button', { name: /^Pengeluaran$/ }).click();
    const label = page.locator('.field-label').filter({ hasText: 'Merchant' });
    const merchant = await label.boundingBox(), optional = await label.locator('.optional').boundingBox();
    expect(merchant).not.toBeNull(); expect(optional).not.toBeNull();
    expect(Math.abs(merchant!.y - optional!.y)).toBeLessThan(8);
    await page.getByLabel('Nominal', { exact: true }).fill(amount!);
    await page.getByRole('combobox', { name: 'Kategori', exact: true }).selectOption({ label: 'Hiburan' });
    await page.getByRole('button', { name: 'Simpan catatan', exact: true }).click();
    await expect(budget).toHaveClass(new RegExp(status!));
  }
  await expect(budget).toContainText('Rp100.001'); await expect(budget).toContainText('Melebihi batas');
});
