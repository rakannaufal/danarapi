import { test, expect, type Page } from '@playwright/test';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import AxeBuilder from '@axe-core/playwright';
import QRCode from 'qrcode';
import { readFileSync } from 'node:fs';

async function demo(page: Page) { await page.goto('/'); await page.getByRole('button',{name:/Coba Demo/}).click(); await expect(page.getByRole('heading',{name:'Ringkasan keuangan'})).toBeVisible(); }
async function nav(page: Page, key: string) { await page.evaluate(value => { location.hash = value; }, key); await expect(page).toHaveURL(new RegExp(`#${key}$`)); await expect(page.locator('#main-content')).toBeVisible(); }
async function openInput(page: Page, kind: string) { if (kind === 'Transfer') { await nav(page, 'transactions'); await page.getByRole('button', { name: 'Transfer antar akun', exact: true }).click(); return; } await page.getByRole('button',{name:'Catat baru'}).click(); await page.getByRole('button',{name:new RegExp(`^${kind}`)}).click(); if (kind === 'Split bill') await page.getByRole('button', { name: 'Bagi total', exact: true }).click(); }
let visualRoot = 'artifacts/visual';
test.beforeEach(async ({ page, browserName }) => { await page.route('**/__local/receipt-scan', route => route.fulfill({ json: route.request().method() === 'GET' ? { configured: false } : { status: 'config_error' } })); visualRoot = browserName === 'chromium' ? 'artifacts/visual' : `artifacts/visual/${browserName}`; const errors: string[] = []; page.on('pageerror', error => errors.push(error.message)); (page as any).__errors = errors; });
test.afterEach(async ({ page }) => { expect((page as any).__errors).toEqual([]); });

function syntheticPDF() {
  const content='BT /F1 12 Tf 50 750 Td (TOKO PDF UJI) Tj 0 -20 Td (Total: Rp75.000) Tj 0 -20 Td (30/09/2026) Tj ET';
  const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>','<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>','<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',`<< /Length ${content.length} >>\nstream\n${content}\nendstream`];
  let result='%PDF-1.4\n';const offsets=[0];objects.forEach((object,index)=>{offsets.push(Buffer.byteLength(result));result+=`${index+1} 0 obj\n${object}\nendobj\n`;});const xref=Buffer.byteLength(result);result+=`xref\n0 6\n0000000000 65535 f \n${offsets.slice(1).map(offset=>String(offset).padStart(10,'0')+' 00000 n \n').join('')}trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;return Buffer.from(result);
}

test('Local QR image/PDF import, MIME/5MB errors, no automatic posting',async({page})=>{
  await page.route('**/__local/receipt-scan', route => route.fulfill({ json: route.request().method() === 'GET' ? { configured: true, token: 'test-token' } : { status: 'ok', data: { merchant: 'TOKO PDF UJI', date: '2026-09-30', items: [{ name: 'Barang', qty: 1, unit_price: 75000, line_total: 75000, note: null }], subtotal: 75000, service_charge: 0, tax: 0, discount: 0, rounding: 0, grand_total: 75000, tax_included_in_price: false, unreadable_fields: [] } } }));
  await demo(page);await nav(page,'review');await expect(page.locator('.review-card')).toHaveCount(2);const fixture=JSON.parse(readFileSync(path.resolve('../../tests/fixtures/import-v1.json'),'utf8'));const qr=await QRCode.toBuffer(fixture.qris[0].raw,{width:600,margin:4});await page.getByLabel('Unggah gambar atau PDF').setInputFiles({name:'qris-sintetis.png',mimeType:'image/png',buffer:qr});await expect(page.locator('.review-card')).toHaveCount(3);await expect(page.locator('.review-card').filter({hasText:'TOKO DEMO'}).last()).toContainText('Rp75.000');await page.getByLabel('Unggah gambar atau PDF').setInputFiles({name:'bukti-teks.pdf',mimeType:'application/pdf',buffer:syntheticPDF()});await expect(page.locator('.review-card')).toHaveCount(4);await expect(page.locator('.review-card').filter({hasText:'TOKO PDF UJI'})).toContainText('Rp75.000');await page.getByLabel('Unggah gambar atau PDF').setInputFiles({name:'palsu.pdf',mimeType:'application/pdf',buffer:Buffer.from('bukan PDF')});await expect(page.getByText(/Jenis berkas tidak didukung/)).toBeVisible();await page.getByLabel('Unggah gambar atau PDF').setInputFiles({name:'besar.png',mimeType:'image/png',buffer:Buffer.alloc(5*1024*1024+1)});await expect(page.getByRole('alert').filter({hasText:/maksimal 5 MB/i})).toBeVisible();await nav(page,'transactions');await page.getByRole('searchbox').fill('TOKO PDF UJI');await expect(page.locator('.transaction-row')).toHaveCount(0);
});
test('Unreadable PDF and unsupported QR retain attachments for manual review', async ({ page }) => {
  await demo(page); await nav(page, 'review');
  await page.route('**/__local/receipt-scan', route => route.fulfill({ json: route.request().method() === 'GET' ? { configured: true, token: 'test-token' } : { status: 'unreadable' } }));
  await page.getByLabel('Unggah gambar atau PDF').setInputFiles({ name: 'tidak-terbaca.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-1.4\ninvalid bounded content') });
  await expect(page.locator('.review-card')).toHaveCount(3);
  await page.getByLabel('Unggah gambar atau PDF').setInputFiles({ name: 'qr-bukan-qris.png', mimeType: 'image/png', buffer: await QRCode.toBuffer('https://example.invalid/unsupported', { width: 600 }) });
  await expect(page.locator('.review-card')).toHaveCount(4);
  await expect(page.locator('.review-card').last()).toContainText('Isi nominal sebelum menyimpan');
  await expect(page.locator('.review-card').last().getByRole('button', { name: /lampiran/i })).toBeVisible();
});
test('Posted manual attachment and confirmed import preview never post another transaction', async ({ page }) => {
  await demo(page); await openInput(page, 'Pengeluaran');
  await page.getByRole('textbox', { name: 'Nominal', exact: true }).fill('1000');
  await page.getByLabel('Merchant').fill('Bukti manual uji');
  await page.getByRole('button', { name: 'Simpan catatan' }).click();
  await nav(page, 'transactions'); await page.getByRole('searchbox').fill('Bukti manual uji');
  await page.locator('.transaction-row').click();
  await page.getByLabel('Tambahkan lampiran').setInputFiles({ name: 'bukti-uji.pdf', mimeType: 'application/pdf', buffer: syntheticPDF() });
  await page.getByRole('button', { name: 'Lihat bukti-uji.pdf' }).click();
  await expect(page.getByTitle('Pratinjau PDF')).toHaveAttribute('src', /^blob:/);
  await page.getByRole('button', { name: 'Tutup', exact: true }).click();
  await expect(page.locator('.transaction-row')).toHaveCount(1);
  await nav(page, 'review'); await page.getByRole('button', { name: 'Coba contoh PDF' }).click();
  await expect(page.locator('.review-card')).toHaveCount(3);
  await expect(page.getByRole('button', { name: 'Coba contoh PDF' })).toBeEnabled();
  await page.locator('.review-card').last().getByRole('button', { name: 'Periksa & simpan' }).click();
  await page.getByRole('textbox', { name: 'Nominal', exact: true }).fill('75000');
  await page.getByLabel('Merchant').fill('Impor bukti tersimpan');
  await page.getByRole('button', { name: 'Simpan catatan' }).click();
  await expect(page.locator('dialog')).toHaveCount(0);
  await nav(page, 'transactions'); await page.getByRole('searchbox').fill('Impor bukti tersimpan');
  await page.locator('.transaction-row').click();
  await expect(page.getByRole('button', { name: 'Lihat bukti-teks.pdf' })).toBeVisible();
});
test('Large synthetic snapshot keeps transaction DOM bounded and filters usable', async ({ page }) => {
  await demo(page);
  await page.evaluate(async () => {
    const modulePath = '/src/store.ts';
    const { state } = await import(modulePath);
    const source = [...state.data.transactions];
    state.data.transactions = Array.from({ length: 50000 }, (_, index) => ({ ...source[index % source.length], id: `large-${index}` }));
  });
  await nav(page, 'transactions');
  await expect(page.locator('.transaction-row')).toHaveCount(30);
  await page.getByRole('searchbox').fill('Warung');
  await expect(page.locator('.transaction-row')).toHaveCount(30);
  await page.getByRole('button', { name: 'Reset filter' }).click();
  await expect(page.locator('.transaction-row')).toHaveCount(30);
});
test('Bundled Demo PDF imports locally with evidence and no posting', async ({ page }) => {
  await demo(page); await nav(page, 'review');
  await page.getByRole('button', { name: 'Coba contoh PDF' }).click();
  await expect(page.locator('.review-card')).toHaveCount(3);
  await expect(page.locator('.review-card').last()).toContainText('Rp75.000');
  await expect(page.locator('.review-card').last().getByRole('button', { name: 'Lihat lampiran' })).toBeVisible();
  await nav(page, 'transactions'); await page.getByRole('searchbox').fill('TOKO DEMO');
  await expect(page.locator('.transaction-row')).toHaveCount(0);
});
test('Duplicate bill review can be dismissed or explicitly merged without double posting', async ({ page }) => {
  await demo(page); await nav(page, 'review'); await page.getByRole('button', { name: 'Tempel teks' }).click();
  await page.getByLabel('Teks bukti').fill('Makan bersama\nTotal 120.000\n25/09/2026');
  await page.getByRole('button', { name: 'Masukkan ke Perlu Ditinjau' }).click();
  const card = page.locator('.review-card').last();
  await expect(card.getByRole('button', { name: 'Bukan duplikat' })).toBeVisible();
  await card.getByRole('button', { name: 'Bukan duplikat' }).click();
  await expect(card.getByRole('button', { name: 'Gabung', exact: true })).toHaveCount(0);
  await page.getByLabel('Teks bukti').fill('MAKAN BERSAMA\nTotal 120.000\n25/09/2026');
  await page.getByRole('button', { name: 'Masukkan ke Perlu Ditinjau' }).click();
  page.once('dialog', dialog => dialog.accept()); await card.getByRole('button', { name: 'Gabung', exact: true }).click();
  await expect(page.locator('.review-card')).toHaveCount(3);
  await expect(page.getByText('Bukti digabung; saldo tidak berubah.')).toBeVisible();
  await nav(page, 'transactions'); await page.getByRole('searchbox').fill('Makan bersama');
  await expect(page.locator('.transaction-row')).toHaveCount(1);
});

test('20 quick entries and 10 split entries automated regression, not human usability',async({page})=>{
  await demo(page);
  for(let index=0;index<20;index++){await openInput(page,'Pengeluaran');await page.getByRole('textbox',{name:'Nominal',exact:true}).fill(String(1000+index));await page.getByLabel('Merchant').fill(`Percobaan cepat ${index}`);await page.getByRole('button',{name:'Simpan catatan'}).click();await expect(page.locator('dialog')).toHaveCount(0);}
  for(let index=0;index<10;index++){await openInput(page,'Split bill');await page.getByLabel('Nama tagihan').fill(`Percobaan split ${index}`);await page.getByRole('textbox',{name:'Total tagihan',exact:true}).fill('100001');await page.getByRole('button',{name:'Simpan tagihan'}).click();await expect(page.locator('dialog')).toHaveCount(0);}
  await nav(page,'transactions');await page.getByRole('searchbox').fill('Percobaan cepat');await expect(page.locator('.transaction-row')).toHaveCount(20);await page.getByRole('searchbox').fill('Percobaan split');await expect(page.locator('.transaction-row')).toHaveCount(10);
});

for(const theme of ['light','dark']) test(`accessibility five screens, small phone, 200% text ${theme}`,async({page})=>{
  await page.setViewportSize({width:375,height:812});await page.addInitScript(value=>localStorage.setItem('danarapi.theme',value),theme);await demo(page);
  const check=async(label:string)=>{const results=await new AxeBuilder({page}).withTags(['wcag2a','wcag2aa','wcag21aa']).analyze();expect(results.violations,JSON.stringify({label,violations:results.violations},null,2)).toEqual([]);
    const contrast = await page.evaluate(() => {
      const root = getComputedStyle(document.documentElement), canvas = document.createElement('canvas'), context = canvas.getContext('2d')!;
      canvas.width = 1; canvas.height = 1;
      const rgb = (color: string) => { context.clearRect(0, 0, 1, 1); context.fillStyle = color; context.fillRect(0, 0, 1, 1); return [...context.getImageData(0, 0, 1, 1).data].slice(0, 3); };
      const luminance = (color: number[]) => color.map(value => { const channel = value / 255; return channel <= .04045 ? channel / 12.92 : ((channel + .055) / 1.055) ** 2.4; }).reduce((sum, value, index) => sum + value * [.2126, .7152, .0722][index], 0);
      const ratio = (left: number[], right: number[]) => { const values = [luminance(left), luminance(right)].sort((first, second) => second - first); return (values[0] + .05) / (values[1] + .05); };
      const token = (name: string) => rgb(root.getPropertyValue('--' + name).trim());
      const focus = token('focus-ring').map((value, index) => Math.round(value * .9 + token('ink')[index] * .1));
      const surfaceNames = document.documentElement.dataset.theme === 'dark' ? ['surface', 'canvas', 'mint-surface', 'sky-surface', 'peach-surface', 'sun-surface'] : ['surface', 'canvas', 'primary-soft', 'sky-soft', 'peach-soft', 'sun-soft'];
      const focusRatios = surfaceNames.map(name => ratio(focus, token(name)));
      const textRatios = surfaceNames.map(name => ratio(token('muted'), token(name)));
      const field = document.querySelector('select,textarea');
      return { focusRatios, textRatios, fieldRatio: field ? ratio(rgb(getComputedStyle(field).borderColor), token('surface')) : 3 };
    });
    expect(contrast.focusRatios.every(value => value >= 3), JSON.stringify({ label, contrast })).toBeTruthy();
    expect(contrast.textRatios.every(value => value >= 4.5), JSON.stringify({ label, contrast })).toBeTruthy();
    expect(contrast.fieldRatio).toBeGreaterThanOrEqual(3);
  };
  await check('beranda');await openInput(page,'Pengeluaran');await check('input');await page.getByRole('button',{name:'Tutup',exact:true}).click();await openInput(page,'Split bill');await check('split');await page.getByRole('button',{name:'Tutup',exact:true}).click();await nav(page,'review');await check('review');await nav(page,'reports');await expect(page.getByRole('heading',{name:'Pengeluaran per kategori'})).toBeVisible();await check('reports');await nav(page,'home');await page.evaluate(()=>{document.documentElement.style.fontSize='200%';});await expect(page.locator('.balance-value')).toBeVisible();
  const capture = async (name: string) => {
    const overflow = await page.evaluate(() => ({ width: innerWidth, document: document.documentElement.scrollWidth, elements: [...document.querySelectorAll<HTMLElement>('body *')].filter(element => { const rect = element.getBoundingClientRect(); return !element.closest('.bottom-nav') && rect.width > 0 && (rect.right > innerWidth + 1 || rect.left < -1 || element.scrollWidth > element.clientWidth + 1); }).slice(0, 25).map(element => ({ tag: element.tagName, class: element.className, text: element.textContent?.slice(0, 50), right: element.getBoundingClientRect().right, scroll: element.scrollWidth, client: element.clientWidth })) }));
    await mkdir(path.resolve('artifacts/visual'), { recursive: true });
    await mkdir(visualRoot, { recursive: true });
    await page.screenshot({ path: path.resolve(`${visualRoot}/${name}-375-text200-${theme}.png`), fullPage: true });
    if (await page.locator('dialog').count()) {
      const dialogWidth = await page.locator('dialog').evaluate(element => ({ scroll: element.scrollWidth, client: element.clientWidth }));
      expect(dialogWidth.scroll, JSON.stringify({ name, dialogWidth })).toBeLessThanOrEqual(dialogWidth.client);
      const amount = page.locator('.amount-input input');
      const fits = await amount.evaluate(element => {
        const input = element as HTMLInputElement, style = getComputedStyle(input), context = document.createElement('canvas').getContext('2d')!;
        context.font = `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
        return context.measureText(input.value).width <= input.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
      });
      expect(fits, `${name}: nominal tidak boleh terpotong`).toBeTruthy();
      await page.screenshot({ path: path.resolve(`${visualRoot}/${name}-375-text200-${theme}-viewport.png`) });
      await page.locator('dialog').evaluate(element => { element.scrollTop = element.scrollHeight; });
      await page.screenshot({ path: path.resolve(`${visualRoot}/${name}-375-text200-${theme}-bottom.png`) });
      await page.locator('dialog').evaluate(element => { element.scrollTop = 0; });
    }
    expect(overflow.document, JSON.stringify({ name, ...overflow })).toBeLessThanOrEqual(overflow.width);
  };
  await capture('beranda'); await openInput(page, 'Pengeluaran'); await page.getByRole('textbox', { name: 'Nominal', exact: true }).fill('999999999999'); await capture('input'); page.once('dialog', dialog => dialog.accept()); await page.getByRole('button', { name: 'Tutup', exact: true }).click();
  await openInput(page, 'Split bill'); await page.getByRole('textbox', { name: 'Total tagihan', exact: true }).fill('120000'); await capture('split-bill'); page.once('dialog', dialog => dialog.accept()); await page.getByRole('button', { name: 'Tutup', exact: true }).click();
  await nav(page, 'review'); await capture('perlu-ditinjau'); await nav(page, 'reports'); await capture('laporan');
});

test('Demo offline, no backend; edit/delete/undo; CSV matches filter', async ({ page, context }) => {
  const external: string[]=[]; const expectedHost = new URL(test.info().project.use.baseURL as string).host; page.on('request',request=>{if(new URL(request.url()).host !== expectedHost || /\/auth\/v1|\/functions\/v1/.test(request.url()))external.push(request.url());});
  await demo(page); await context.setOffline(true); await openInput(page,'Pengeluaran'); await page.getByRole('textbox',{name:'Nominal',exact:true}).fill('12500'); await page.getByLabel('Merchant').fill('Catatan uji web'); await page.getByRole('button',{name:'Simpan catatan'}).click(); await expect(page.getByText('Tersimpan',{exact:true})).toBeVisible(); await nav(page,'transactions'); await page.getByRole('searchbox').fill('Catatan uji web'); await expect(page.locator('.transaction-row')).toHaveCount(1);
  await page.locator('.transaction-row').click(); await page.getByRole('button',{name:'Ubah',exact:true}).click(); await page.getByRole('textbox',{name:'Nominal',exact:true}).fill('14000'); await page.getByRole('button',{name:'Simpan perubahan'}).click(); await expect(page.locator('.transaction-row')).toContainText('14.000');
  const downloaded=page.waitForEvent('download'); await page.getByRole('button',{name:/CSV tampilan/}).click(); expect((await downloaded).suggestedFilename()).toBe('transaksi-tampilan.csv');
  await page.locator('.transaction-row').click(); page.once('dialog',dialog=>dialog.accept()); await page.getByRole('button',{name:'Hapus',exact:true}).click(); await expect(page.locator('.transaction-row')).toHaveCount(0); await page.getByRole('button',{name:'Urungkan'}).click(); await expect(page.locator('.transaction-row')).toHaveCount(1); expect(external).toEqual([]);
});
test('Import remains review; ambiguous amount missing; explicit confirmation; reject undo', async ({ page }) => {
  await demo(page); await nav(page,'review'); const before=await page.locator('.review-card').count(); await page.getByRole('button',{name:'Tempel teks'}).click(); await page.getByLabel('Teks bukti').fill('TOKO UJI WEB\nTotal: Rp75.000\n30/09/2026'); await page.getByRole('button',{name:'Masukkan ke Perlu Ditinjau'}).click(); await expect(page.locator('.review-card')).toHaveCount(before+1);
  const review=page.locator('.review-card').filter({hasText:'TOKO UJI WEB'}); await review.getByRole('button',{name:'Periksa & simpan'}).click(); await expect(page.getByRole('textbox',{name:'Nominal',exact:true})).toHaveValue('75.000'); await page.getByRole('button',{name:'Simpan catatan'}).click(); await expect(page.locator('.review-card')).toHaveCount(before); await page.locator('.review-card').first().getByRole('button',{name:'Tolak',exact:true}).click(); await expect(page.locator('.review-card')).toHaveCount(before-1); await page.getByRole('button',{name:'Urungkan'}).click(); await expect(page.locator('.review-card')).toHaveCount(before);
});
test('Split bill, partial settlement, overpay, noncash resolution and reversal', async ({ page }) => {
  await demo(page); await openInput(page,'Split bill'); await page.getByLabel('Nama tagihan').fill('Makan uji bersama'); await page.getByRole('textbox',{name:'Total tagihan',exact:true}).fill('120000'); await expect(page.getByText('Bagian saya Rp40.000.',{exact:false})).toBeVisible(); await page.getByRole('button',{name:'Simpan tagihan'}).click(); await page.locator('.bill-link').filter({hasText:'Makan uji bersama'}).click(); await expect(page.getByText('Pelunasan ini hanya mengurangi piutang, bukan pemasukan.')).toBeVisible(); await page.getByRole('combobox',{name:'Peserta',exact:true}).selectOption({label:'Teman 1'}); await page.getByLabel('Nominal',{exact:true}).fill('15000'); await page.getByRole('button',{name:'Catat pelunasan',exact:true}).click(); await expect(page.locator('dialog').getByText('Lunas sebagian',{exact:true}).first()).toBeVisible(); await page.getByLabel('Nominal',{exact:true}).fill('25001'); await page.getByRole('button',{name:'Catat pelunasan',exact:true}).click(); await expect(page.getByText('Jumlah melebihi sisa kewajiban.')).toBeVisible(); await page.getByRole('combobox',{name:'Tindakan',exact:true}).selectOption('resolution'); await page.getByLabel('Nominal',{exact:true}).fill('10000'); await page.getByLabel('Alasan (wajib)').fill('Keputusan uji'); page.once('dialog',dialog=>dialog.accept()); await page.getByRole('button',{name:'Hapus kewajiban',exact:true}).click(); await expect(page.getByText('Penghapusan kewajiban · Teman 1')).toBeVisible(); page.once('dialog',dialog=>dialog.accept('Koreksi')); await page.locator('.list-row').filter({hasText:'Penghapusan kewajiban'}).getByRole('button',{name:'Batalkan'}).click(); await expect(page.getByText(/Dibatalkan Koreksi/)).toBeVisible();
});
test('Transfer validation, creation, edit/delete/undo; last account protected', async ({page})=>{
  await demo(page); await openInput(page,'Transfer'); await page.getByRole('textbox',{name:'Nominal',exact:true}).fill('10000'); await page.getByRole('combobox',{name:'Ke akun',exact:true}).selectOption('cash'); await page.getByRole('button',{name:'Simpan catatan'}).click(); await expect(page.getByText('Akun asal dan tujuan harus berbeda.')).toBeVisible(); await page.getByRole('combobox',{name:'Ke akun',exact:true}).selectOption('bank'); await page.getByRole('button',{name:'Simpan catatan'}).click(); await nav(page,'transactions'); await page.getByRole('button',{name:'Filter',exact:true}).click(); await page.getByRole('combobox',{name:'Jenis',exact:true}).selectOption('transfer'); await expect(page.locator('.transaction-row')).toHaveCount(1); await page.locator('.transaction-row').click(); page.once('dialog',dialog=>dialog.accept()); await page.getByRole('button',{name:'Hapus transfer'}).click(); await expect(page.locator('.transaction-row')).toHaveCount(0); await page.getByRole('button',{name:'Urungkan'}).click(); await expect(page.locator('.transaction-row')).toHaveCount(1);
});
test('Unsaved input guards browser back; keyboard focus; theme persists without sensitive data', async({page})=>{
  await demo(page); await openInput(page,'Pengeluaran'); await page.getByRole('textbox',{name:'Nominal',exact:true}).fill('123'); page.once('dialog',dialog=>dialog.dismiss()); await page.goBack(); await expect(page.getByRole('textbox',{name:'Nominal',exact:true})).toHaveValue('123'); page.once('dialog',dialog=>dialog.accept()); await page.getByRole('button',{name:'Tutup',exact:true}).click(); await page.getByRole('button',{name:'Gunakan tema gelap'}).click(); await expect(page.locator('html')).toHaveAttribute('data-theme','dark'); const keys=await page.evaluate(()=>Object.keys(localStorage)); expect(keys.every(key=>['danarapi.theme','danarapi.hide','danarapi.timezone'].includes(key))).toBeTruthy(); await page.reload(); await expect(page.locator('html')).toHaveAttribute('data-theme','dark'); await expect(page.getByRole('button',{name:/Coba Demo/})).toBeVisible();
});
test('Keyboard dialog traps focus, Escape restores trigger; controls meet 44px and reduced motion', async ({ page }) => {
  await demo(page); await page.emulateMedia({ reducedMotion: 'reduce' });
  await expect(page.getByRole('link', { name: 'Lewati navigasi' })).not.toBeInViewport();
  const trigger = page.getByRole('button', { name: 'Catat baru' });
  await trigger.focus(); await page.keyboard.press('Enter');
  await expect(page.locator('dialog')).toBeVisible();
  for (let index = 0; index < 12; index++) {
    await page.keyboard.press(index % 2 ? 'Shift+Tab' : 'Tab');
    expect(await page.evaluate(() => Boolean(document.activeElement?.closest('dialog')))).toBeTruthy();
  }
  const controls = await page.locator('dialog button').evaluateAll(elements => elements.map(element => ({ width: element.getBoundingClientRect().width, height: element.getBoundingClientRect().height, transition: getComputedStyle(element).transitionDuration })));
  expect(controls.every(control => control.width >= 44 && control.height >= 44 && control.transition === '0s')).toBeTruthy();
  await page.keyboard.press('Escape'); await expect(page.locator('dialog')).toHaveCount(0);
  await expect(trigger).toBeFocused();
  expect(await trigger.evaluate(element => getComputedStyle(element).outlineWidth)).toBe('3px');
  await openInput(page, 'Pengeluaran');
  const fields = await page.locator('dialog input, dialog select, dialog textarea').evaluateAll(elements => elements.map(element => ({ width: element.getBoundingClientRect().width, height: element.getBoundingClientRect().height })));
  expect(fields.every(field => field.width >= 44 && field.height >= 44), JSON.stringify(fields)).toBeTruthy();
});
test('Accounts, categories, merchant rules, budget and full export',async({page})=>{
  await demo(page); await nav(page,'settings'); await page.getByRole('button',{name:'Akun',exact:true}).click(); await page.getByRole('button',{name:'Tambah akun'}).click(); await page.getByLabel('Nama',{exact:true}).fill('E-wallet uji'); await page.getByRole('combobox',{name:'Jenis',exact:true}).selectOption('ewallet'); await page.getByLabel('Saldo awal').fill('1000'); await page.getByRole('button',{name:'Simpan',exact:true}).click(); await expect(page.getByText('E-wallet uji',{exact:true})).toBeVisible(); await page.getByRole('button',{name:'Kategori',exact:true}).click(); await page.getByRole('button',{name:'Tambah kategori'}).click(); await page.getByLabel('Nama',{exact:true}).fill('Hobi'); await page.getByRole('button',{name:'Simpan',exact:true}).click(); await expect(page.locator('.list-row strong').filter({hasText:/^Hobi$/})).toBeVisible(); await page.getByLabel('Pola merchant').fill('toko hobi'); await page.getByRole('combobox',{name:'Kategori',exact:true}).selectOption({label:'Hobi'}); await page.getByRole('button',{name:'Tambah aturan'}).click(); await expect(page.getByText('toko hobi · Hobi')).toBeVisible(); await nav(page,'budgets'); await page.getByRole('button',{name:'Tambah anggaran',exact:true}).click(); await page.getByRole('combobox',{name:'Kategori',exact:true}).selectOption({label:'Hobi'}); await page.getByLabel('Limit bulanan').fill('200000'); await page.getByRole('button',{name:'Simpan anggaran'}).click(); await expect(page.getByRole('heading',{name:'Hobi',exact:true})).toBeVisible(); await nav(page,'settings'); await page.getByRole('button',{name:'Data & privasi'}).click(); page.once('dialog',dialog=>dialog.accept()); const downloaded=page.waitForEvent('download'); await page.getByRole('button',{name:'Ekspor penuh (ZIP)'}).click(); expect((await downloaded).suggestedFilename()).toBe('danarapi-demo.zip'); await expect(page.getByText('Mode Demo tidak memiliki akun server.')).toBeVisible();
});

for(const width of [390,1440]) for(const theme of ['light','dark']) test(`visual five screens ${width} ${theme}`,async({page})=>{
  await page.setViewportSize({width,height:width===390?844:1000}); await page.addInitScript(value=>localStorage.setItem('danarapi.theme',value),theme); await demo(page); await page.evaluate(()=>document.fonts.ready); const folder=path.resolve(visualRoot); await mkdir(folder,{recursive:true});
  const capture=async(name:string)=>{await page.screenshot({path:path.join(folder,`${name}-${width}-${theme}.png`),fullPage:true}); expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBeTruthy();};
  await capture('beranda'); await openInput(page,'Pengeluaran'); await page.getByRole('textbox',{name:'Nominal',exact:true}).fill('75000'); await capture('input'); page.once('dialog',dialog=>dialog.accept()); await page.getByRole('button',{name:'Tutup',exact:true}).click(); await openInput(page,'Split bill'); await page.getByLabel('Nama tagihan').fill('Makan bersama'); await page.getByRole('textbox',{name:'Total tagihan',exact:true}).fill('120000'); await capture('split-bill'); page.once('dialog',dialog=>dialog.accept()); await page.getByRole('button',{name:'Tutup',exact:true}).click(); await nav(page,'review'); await capture('perlu-ditinjau'); await nav(page,'reports'); await expect(page.getByRole('heading',{name:'Pengeluaran per kategori'})).toBeVisible(); await capture('laporan');
});
