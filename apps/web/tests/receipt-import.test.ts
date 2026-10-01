import assert from 'node:assert/strict';
import test from 'node:test';
import { Readable } from 'node:stream';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { localScanHandler, localScanStore } from '../server/local-receipt-scan.ts';
import { normalizeReceipt, validateReceipt } from '../src/receipt.ts';
import { needsReceiptScan, reviewFromReceipt } from '../src/receipt-import.ts';
import { parseText } from '../src/import.ts';
import { assertDecimalPayload } from '../src/domain.ts';
import { DemoRepository } from '../src/demo.ts';

const receipt = normalizeReceipt({ merchant: 'Karis Jaya Shop', date: '2023-08-02', items: [{ name: 'Indomie Goreng', qty: 1, unit_price: 36000, line_total: 36000, note: '1 lusin' }, { name: 'Fruit Tea Apple', qty: 1, unit_price: 7000, line_total: 7000, note: '500 ml' }, { name: 'Belfood Sosis Bakar', qty: 1, unit_price: 27000, line_total: 27000, note: null }], subtotal: 70000, service_charge: 0, tax: 0, discount: 0, rounding: 0, grand_total: 70000, tax_included_in_price: false, unreadable_fields: [] });
test('images and every PDF request AI extraction; QR and pasted text stay local', () => {
  assert.equal(needsReceiptScan(parseText('', 'image')), true);
  assert.equal(needsReceiptScan(parseText('', 'pdf_text')), true);
  assert.equal(needsReceiptScan(parseText('TOKO\nTotal: 70000', 'pdf_text')), true);
  assert.equal(needsReceiptScan(parseText('', 'qris')), false);
  assert.equal(needsReceiptScan(parseText('TOKO\nTotal: 70000', 'pasted_text')), false);
});
test('Karis receipt produces merchant, historical date, total, every menu and decimal-string storage', () => {
  const original = { ...parseText('', 'image'), fingerprint: 'original-image', attachmentName: 'struk.png' };
  const review = reviewFromReceipt(original, receipt);
  assert.equal(review.id, original.id); assert.equal(review.status, 'pending'); assert.equal(review.amount.value, '70000'); assert.equal(review.merchant.value, 'Karis Jaya Shop'); assert.equal(review.date.value, '2023-08-02');
  assert.equal(review.receipt!.items.length, 3); assert.equal(review.receipt!.items[0]!.qty, 1); assert.equal(review.receipt!.items[0]!.unit_price, '36000'); assert.equal(review.receipt!.items[0]!.note, '1 lusin');
  assert.match(review.rawReference!, /Fruit Tea Apple/); assert.match(review.rawReference!, /Belfood Sosis Bakar/); assert.equal(review.fingerprint, original.fingerprint); assert.equal(review.attachmentName, original.attachmentName);
  assertDecimalPayload(review); assert.equal(validateReceipt(normalizeReceipt(review.receipt)).lolos, true);
});
test('missing grand total is never replaced by subtotal; mismatches remain visible', () => {
  const review = reviewFromReceipt(parseText('', 'image'), { ...receipt, grand_total: null });
  assert.equal(review.amount.value, null); assert.equal(review.amount.confidence, 'low');
  const mismatch = reviewFromReceipt(parseText('', 'image'), { ...receipt, grand_total: 80000 });
  assert.equal(mismatch.amount.value, '80000'); assert.equal(mismatch.amount.confidence, 'medium'); assert.equal(validateReceipt(normalizeReceipt(mismatch.receipt)).lolos, false);
});
test('ISO dates work for local text; invalid dates remain empty', () => {
  assert.equal(parseText('Karis Jaya Shop\nTotal: 70000\n2023-08-02').date.value, '2023-08-02');
  assert.equal(parseText('Karis Jaya Shop\n2023-02-30').date.value, null);
});
test('reading an existing pending review updates details without changing balances or adding a duplicate', async () => {
  const repository = new DemoRepository(), original = { ...parseText('', 'image'), fingerprint: 'rescan-test' };
  await repository.mutate('add_review_item', original);
  const before = await repository.snapshot();
  await repository.mutate('update_review_item', reviewFromReceipt(original, receipt));
  const after = await repository.snapshot();
  assert.deepEqual(after.overview, before.overview); assert.equal(after.reviewItems.length, before.reviewItems.length); assert.equal(after.reviewItems.find(row => row.id === original.id)!.amount.value, '70000');
  await repository.mutate('reject_review_item', { id: original.id });
  await assert.rejects(repository.mutate('update_review_item', reviewFromReceipt(original, receipt)), /tidak lagi/);
});
test('local scan budgets enforce cache, concurrency, two calls, daily limits and expiration', async () => {
  let now = Date.parse('2026-10-01T00:00:00Z'); const store = localScanStore({ dailyLimit: 1, interval: 4000, now: () => now });
  assert.equal((await store.claim('local', 'one')).state, 'new'); assert.equal((await store.claim('local', 'one')).state, 'busy');
  assert.equal(await store.reserve('local', 'one'), 0); assert.equal(await store.reserve('local', 'one'), 4000); await assert.rejects(store.reserve('local', 'one'), /call_limit/);
  await store.finish('local', 'one', { status: 'ok', data: receipt }); assert.equal((await store.claim('local', 'one')).state, 'cached'); assert.equal((await store.claim('local', 'two')).state, 'quota_exceeded');
  now += 86400001; assert.equal((await store.claim('local', 'one')).state, 'new');
});
async function invoke(handler: ReturnType<typeof localScanHandler>, method: string, headers: Record<string, string> = {}, body = '', address = '127.0.0.1') {
  const request = Object.assign(Readable.from([Buffer.from(body)]), { method, headers: { host: 'localhost:5173', ...headers }, socket: { remoteAddress: address } }) as unknown as IncomingMessage;
  let status = 0, responseHeaders: unknown, output = '';
  const response = { writeHead(code: number, values: unknown) { status = code; responseHeaders = values; }, end(value: string) { output = value; } } as unknown as ServerResponse;
  await handler(request, response);
  return { status, headers: responseHeaders, data: JSON.parse(output) };
}
test('local backend rejects remote addresses, hostile Host/Origin, missing tokens and oversize bodies', async () => {
  let calls = 0; const handler = localScanHandler({ enabled: true, apiKey: 'secret-test-key', model: 'gemini-3.5-flash-lite', interval: 0, fetch: (async () => { calls++; return Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: JSON.stringify(receipt) }] } }] }); }) as typeof fetch });
  const capability = await invoke(handler, 'GET'); assert.equal(capability.data.configured, true); assert.ok(capability.data.token); assert.ok(!JSON.stringify(capability.data).includes('secret-test-key'));
  assert.equal((await invoke(handler, 'GET', {}, '', '192.168.1.10')).status, 403);
  assert.equal((await invoke(handler, 'GET', { host: 'evil.example:5173' })).status, 403);
  assert.equal((await invoke(handler, 'GET', { origin: 'https://evil.example' })).status, 403);
  assert.equal((await invoke(handler, 'POST', { origin: 'http://localhost:5173' })).status, 403);
  const headers = { origin: 'http://localhost:5173', 'x-danarapi-local-scan': capability.data.token, 'content-type': 'application/json' };
  assert.equal((await invoke(handler, 'POST', { ...headers, 'content-length': '5700001' })).status, 400);
  assert.equal((await invoke(handler, 'POST', headers, '{broken')).data.status, 'invalid_image'); assert.equal(calls, 0);
  const image = { mimeType: 'image/jpeg', data: Buffer.from([255, 216, 255, ...Array(13).fill(0)]).toString('base64') };
  assert.equal((await invoke(handler, 'POST', headers, JSON.stringify({ images: [image] }))).data.status, 'ok'); assert.equal(calls, 1);
  assert.equal((await invoke(handler, 'POST', headers, JSON.stringify({ images: [image] }))).data.cached, true); assert.equal(calls, 1);
});
test('local backend stays disabled without explicit opt-in or valid settings', async () => {
  for (const config of [{ enabled: false }, { enabled: true, dailyLimit: NaN }]) { const handler = localScanHandler({ apiKey: 'secret-test-key', model: 'gemini-3.5-flash-lite', ...config }); assert.equal((await invoke(handler, 'GET')).data.configured, false); }
});
