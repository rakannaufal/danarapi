import { test, expect, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { readFileSync } from 'node:fs';

const receipt = { merchant: 'Karis Jaya Shop', date: '2023-08-02', items: [{ name: 'Indomie Goreng', qty: 1, unit_price: 36000, line_total: 36000, note: '1 lusin' }, { name: 'Fruit Tea Apple', qty: 1, unit_price: 7000, line_total: 7000, note: '500 ml' }, { name: 'Belfood Sosis Bakar', qty: 1, unit_price: 27000, line_total: 27000, note: null }], subtotal: 70000, service_charge: 0, tax: 0, discount: 0, rounding: 0, grand_total: 70000, tax_included_in_price: false, unreadable_fields: [] };
async function openImport(page: Page) {
  await page.goto('/'); await page.getByRole('button', { name: /Coba Demo/ }).click(); await page.getByRole('button', { name: /^Perlu Ditinjau/ }).click();
}
async function image(page: Page) {
  return Buffer.from(await page.evaluate(() => { const canvas = document.createElement('canvas'); canvas.width = 200; canvas.height = 350; const context = canvas.getContext('2d')!; context.fillStyle = 'white'; context.fillRect(0, 0, 200, 350); context.fillStyle = 'black'; context.fillText('STRUK SINTETIS UNTUK TEST', 10, 50); return canvas.toDataURL('image/png').split(',')[1]!; }), 'base64');
}
test('wholesale receipt shows full quantities, named discrepancy and explicit manual correction', async ({ page }) => {
  const wholesale = JSON.parse(readFileSync(new URL('../../../tests/fixtures/receipt-wholesale.json', import.meta.url), 'utf8'));
  let calls = 0;
  await page.route('**/__local/receipt-scan', async route => {
    if (route.request().method() === 'GET') { await route.fulfill({ json: { configured: true, token: 'test-token' } }); return; }
    calls++; await route.fulfill({ json: { status: 'ok', data: wholesale } });
  });
  await openImport(page);
  await page.getByLabel('Unggah gambar atau PDF').setInputFiles({ name: 'grosir-test.png', mimeType: 'image/png', buffer: await image(page) });
  const card = page.locator('.review-card').filter({ hasText: 'Toko Abang' });
  await expect(card.locator('.extracted-items tbody tr')).toHaveCount(8);
  await expect(card.locator('.extracted-items tbody tr').nth(0)).toContainText('4.000');
  await expect(card.locator('.extracted-items tbody tr').nth(4)).toContainText('8.000');
  await expect(card.locator('.receipt-row-warning')).toHaveCount(1);
  await expect(card.locator('.receipt-row-warning')).toContainText('Kardus Packing');
  await expect(card.locator('.extraction-check')).toHaveCount(0);
  expect((await new AxeBuilder({ page }).include('.review-card').analyze()).violations).toEqual([]);
  await page.screenshot({ path: `artifacts/visual/${test.info().project.name}/receipt-import/wholesale-review.png`, fullPage: true });
  await page.setViewportSize({ width: 375, height: 812 });
  await expect(card).toContainText('8.000');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.screenshot({ path: `artifacts/visual/${test.info().project.name}/receipt-import/wholesale-mobile.png`, fullPage: true });
  await card.getByRole('button', { name: 'Koreksi rincian struk' }).click();
  await expect(card.locator('.scan-line').nth(0).getByLabel('Qty', { exact: true })).toHaveValue('4000');
  await card.locator('.scan-line').nth(7).getByLabel('Total baris', { exact: true }).fill('7200000');
  await card.getByRole('button', { name: 'Simpan koreksi', exact: true }).click();
  await expect(card.locator('.scan-review')).toHaveCount(0);
  await expect(card.locator('.receipt-row-warning')).toHaveCount(0);
  expect(calls).toBe(1);
  await card.getByRole('button', { name: 'Split bill', exact: true }).click();
  await expect(page.getByLabel('Jumlah menu 1', { exact: true })).toHaveValue('4000');
  await expect(page.getByLabel('Jumlah menu 5', { exact: true })).toHaveValue('8000');
});
test('image import displays complete extraction, historical date, evidence and prefilled split without changing balances', async ({ page }) => {
  let calls = 0;
  await page.route('**/__local/receipt-scan', async route => {
    if (route.request().method() === 'GET') { await route.fulfill({ json: { configured: true, token: 'test-token' } }); return; }
    calls++; expect(route.request().headers()['x-danarapi-local-scan']).toBe('test-token'); expect(route.request().postDataJSON().images[0].mimeType).toBe('image/jpeg');
    await route.fulfill({ json: { status: 'ok', data: receipt } });
  });
  await openImport(page);
  await page.getByLabel('Unggah gambar atau PDF').setInputFiles({ name: 'struk-sintetis.png', mimeType: 'image/png', buffer: await image(page) });
  const card = page.locator('.review-card').filter({ hasText: 'Karis Jaya Shop' });
  await expect(card).toBeVisible(); await expect(card).toContainText('Rp70.000'); await expect(card).toContainText('2023-08-02'); await expect(card.locator('.extracted-items tbody tr')).toHaveCount(3); await expect(card).toContainText('1 lusin'); await expect(card).toContainText('500 ml'); await expect(card.locator('.extraction-check')).toHaveCount(0); expect(calls).toBe(1);
  await card.getByText('Lihat asal ekstraksi').click(); await expect(card.locator('details')).toContainText('Belfood Sosis Bakar');
  expect((await new AxeBuilder({ page }).include('.review-card').analyze()).violations).toEqual([]);
  await card.getByRole('button', { name: 'Baca ulang' }).click(); await expect(page.getByText('Hasil ekstraksi diperbarui; saldo belum berubah.', { exact: true })).toBeVisible(); await expect(page.locator('.review-card').filter({ hasText: 'Karis Jaya Shop' })).toHaveCount(1);
  await card.getByRole('button', { name: 'Split bill', exact: true }).click(); await expect(page.getByLabel('Nama tagihan')).toHaveValue('Karis Jaya Shop'); await expect(page.getByLabel('Nama menu 1', { exact: true })).toHaveValue('Indomie Goreng'); await expect(page.getByLabel('Harga menu 1', { exact: true })).toHaveValue('36.000'); await expect(page.getByLabel('Tanggal', { exact: true })).toHaveValue('2023-08-02');
  await page.getByRole('button', { name: 'Per orang', exact: true }).click(); await page.getByRole('combobox', { name: 'Pilih pemesan', exact: true }).selectOption({ label: 'Saya' });
  for (const checkbox of await page.locator('.receipt-owners input').all()) await checkbox.check();
  await expect(page.locator('.receipt-result tfoot')).toContainText('Rp70.000');
});
test('scan failure preserves manual import and re-reading updates the same review', async ({ page }) => {
  let available = false;
  await page.route('**/__local/receipt-scan', route => route.fulfill({ json: route.request().method() === 'GET' ? { configured: true, token: 'test-token' } : available ? { status: 'ok', data: receipt } : { status: 'quota_exceeded' } }));
  await openImport(page); await page.getByLabel('Unggah gambar atau PDF').setInputFiles({ name: 'fallback.png', mimeType: 'image/png', buffer: await image(page) });
  await expect(page.getByRole('alert')).toContainText('Kuota scan habis');
  const card = page.locator('.review-card').filter({ hasText: 'Merchant belum terbaca' }); await expect(card).toHaveCount(1);
  available = true; await card.getByRole('button', { name: 'Baca ulang' }).click(); await expect(page.locator('.review-card').filter({ hasText: 'Karis Jaya Shop' })).toHaveCount(1); await expect(page.locator('.review-card').filter({ hasText: 'Merchant belum terbaca' })).toHaveCount(0);
});
test('scan always uses AI without mode toggles; mobile review stays within the page', async ({ page }) => {
  let calls = 0;
  await page.route('**/__local/receipt-scan', route => {
    if (route.request().method() === 'POST') calls++;
    return route.fulfill({ json: route.request().method() === 'GET' ? { configured: true, token: 'test-token' } : { status: 'ok', data: receipt } });
  });
  await page.setViewportSize({ width: 390, height: 844 }); await openImport(page);
  await expect(page.getByLabel('Baca struk otomatis')).toHaveCount(0);
  await expect(page.getByText('Privasi foto', { exact: true })).toHaveCount(0);
  await expect(page.locator('.demo-banner')).toHaveCount(0);
  await page.getByLabel('Unggah gambar atau PDF').setInputFiles({ name: 'scan.png', mimeType: 'image/png', buffer: await image(page) });
  await expect(page.locator('.review-card').filter({ hasText: 'Karis Jaya Shop' })).toBeVisible(); expect(calls).toBe(1); expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});
test('PDF without a text layer is rendered into an image and extracted', async ({ page }) => {
  let calls = 0;
  await page.route('**/__local/receipt-scan', route => {
    if (route.request().method() === 'POST') { calls++; expect(route.request().postDataJSON().images).toHaveLength(1); expect(route.request().postDataJSON().images[0].mimeType).toBe('image/jpeg'); }
    return route.fulfill({ json: route.request().method() === 'GET' ? { configured: true, token: 'test-token' } : { status: 'ok', data: receipt } });
  });
  const stream = '0.8 g 20 20 160 300 re f\n';
  const objects = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>', '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 350] /Resources << >> /Contents 4 0 R >>', `<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}endstream`];
  let pdf = '%PDF-1.4\n'; const offsets = [0];
  for (const [index, object] of objects.entries()) { offsets.push(Buffer.byteLength(pdf)); pdf += `${index + 1} 0 obj\n${object}\nendobj\n`; }
  const xref = Buffer.byteLength(pdf); pdf += `xref\n0 5\n0000000000 65535 f \n${offsets.slice(1).map(offset => `${String(offset).padStart(10, '0')} 00000 n \n`).join('')}trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  await openImport(page); await page.getByLabel('Unggah gambar atau PDF').setInputFiles({ name: 'scan-sintetis.pdf', mimeType: 'application/pdf', buffer: Buffer.from(pdf) });
  await expect(page.locator('.review-card').filter({ hasText: 'Karis Jaya Shop' })).toContainText('Rp70.000'); expect(calls).toBe(1);
});
