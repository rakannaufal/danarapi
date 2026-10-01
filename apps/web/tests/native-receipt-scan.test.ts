import assert from 'node:assert/strict';
import test from 'node:test';
import { Readable } from 'node:stream';
import { readFileSync } from 'node:fs';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { nativeScanHandler, localScanHandler } from '../server/local-receipt-scan.ts';
import { normalizeReceipt } from '../src/receipt.ts';
import { reviewFromReceipt } from '../src/receipt-import.ts';
import { parseText } from '../src/import.ts';

const receipt = JSON.parse(readFileSync(new URL('../../../tests/fixtures/receipt-retail.json', import.meta.url), 'utf8'));
const token = 'a'.repeat(64);
const host = '192.168.1.20:5174';
const image = { mimeType: 'image/jpeg', data: Buffer.from([255, 216, 255, ...Array(13).fill(0)]).toString('base64') };
const body = JSON.stringify({ images: [image] });
const options = { token, host, apiKey: 'server-only-test-key', model: 'test-model', interval: 0 };

async function invoke(handler: ReturnType<typeof nativeScanHandler>, changes: { method?: string; url?: string; headers?: Record<string, string>; body?: string; encrypted?: boolean } = {}) {
  const request = Object.assign(Readable.from([Buffer.from(changes.body ?? body)]), { url: changes.url ?? '/scan', method: changes.method ?? 'POST', headers: { host, 'x-danarapi-native-scan': token, 'content-type': 'application/json', ...changes.headers }, socket: { encrypted: changes.encrypted ?? true, remoteAddress: '192.168.1.30' } }) as unknown as IncomingMessage;
  let status = 0, output = '';
  const response = { writeHead(code: number) { status = code; }, end(value: string) { output = value; } } as unknown as ServerResponse;
  await handler(request, response);
  return { status, data: JSON.parse(output) };
}

test('native scan requires TLS, exact Host, capability token; rejects browser origins and secret discovery', async () => {
  let calls = 0;
  const handler = nativeScanHandler({ ...options, fetch: (async () => { calls++; throw new Error('must not call'); }) as typeof fetch });
  const cases: Parameters<typeof invoke>[1][] = [{ encrypted: false }, { headers: { host: 'evil.example:5174' } }, { headers: { 'x-danarapi-native-scan': '' } }, { headers: { 'x-danarapi-native-scan': 'b'.repeat(64) } }, { headers: { origin: 'https://evil.example' } }, { headers: { 'sec-fetch-site': 'same-site' } }];
  for (const changes of cases) {
    assert.equal((await invoke(handler, changes)).status, 403);
  }
  const capability = await invoke(handler, { method: 'GET' });
  assert.deepEqual(capability.data, { configured: true });
  assert.ok(!JSON.stringify(capability).includes(token));
  assert.ok(!JSON.stringify(capability).includes(options.apiKey));
  assert.equal((await invoke(handler, { url: '/anything' })).status, 404);
  assert.equal((await invoke(handler, { method: 'PUT' })).status, 405);
  assert.equal(calls, 0);
});

test('native bridge uses web extraction, corrections and cache without losing retail detail', async () => {
  const requests: { url: string; body: unknown }[] = [];
  const fetcher = (async (url: string | URL | Request, init?: RequestInit) => {
    requests.push({ url: String(url), body: JSON.parse(String(init?.body)) });
    return Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: JSON.stringify(receipt) }] } }] });
  }) as typeof fetch;
  const native = nativeScanHandler({ ...options, fetch: fetcher });
  const result = await invoke(native);
  assert.equal(result.data.status, 'ok');
  assert.deepEqual(result.data.data, normalizeReceipt(receipt));
  assert.equal(result.data.validasi.lolos, false);
  assert.equal(requests.length, 2);
  const review = reviewFromReceipt(parseText('', 'image'), result.data.data);
  assert.equal(review.amount.value, '186000');
  assert.equal(review.date.value, '2025-06-29');
  assert.equal(review.merchant.value, 'JIMS HONEY');
  assert.equal(review.receipt!.items[1]!.unit_price, '350000');
  assert.equal(review.receipt!.items[1]!.line_total, '175000');
  assert.equal(review.receipt!.discount, '175000');
  assert.equal((await invoke(native)).data.cached, true);
  assert.equal(requests.length, 2);
  const nativeRequests = requests.slice();
  requests.length = 0;
  const web = localScanHandler({ ...options, enabled: true, fetch: fetcher });
  const originalRequest = Object.assign(Readable.from([]), { method: 'GET', headers: { host: 'localhost:5173' }, socket: { remoteAddress: '127.0.0.1' } }) as unknown as IncomingMessage;
  let discovery = '';
  await web(originalRequest, { writeHead() {}, end(value: string) { discovery = value; } } as unknown as ServerResponse);
  const webRequest = Object.assign(Readable.from([Buffer.from(body)]), { method: 'POST', headers: { host: 'localhost:5173', origin: 'http://localhost:5173', 'x-danarapi-local-scan': JSON.parse(discovery).token, 'content-type': 'application/json' }, socket: { remoteAddress: '127.0.0.1' } }) as unknown as IncomingMessage;
  let output = '';
  await web(webRequest, { writeHead() {}, end(value: string) { output = value; } } as unknown as ServerResponse);
  assert.deepEqual(JSON.parse(output).data, result.data.data);
  assert.deepEqual(requests, nativeRequests);
});

test('native image limits and invalid configuration fail before provider requests', async () => {
  let calls = 0;
  const handler = nativeScanHandler({ ...options, fetch: (async () => { calls++; throw new Error('must not call'); }) as typeof fetch });
  assert.equal((await invoke(handler, { headers: { 'content-length': '5700001' } })).status, 400);
  assert.equal((await invoke(handler, { headers: { 'content-type': 'text/plain' } })).status, 400);
  assert.equal((await invoke(handler, { body: '{broken' })).data.status, 'invalid_image');
  assert.equal((await invoke(handler, { body: JSON.stringify({ images: [] }) })).data.status, 'invalid_image');
  assert.equal(calls, 0);
  assert.throws(() => nativeScanHandler({ ...options, token: 'short' }));
  assert.throws(() => nativeScanHandler({ ...options, dailyLimit: NaN }));
  assert.throws(() => nativeScanHandler({ ...options, interval: -1 }));
});
