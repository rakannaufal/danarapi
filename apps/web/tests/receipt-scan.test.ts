import assert from 'node:assert/strict';
import test from 'node:test';
import { normalizeAmount, normalizeReceipt, validateReceipt, type ScanResult } from '../src/receipt.ts';
import { scanReceipt, validateImages, readBounded, receiptSchema, type ScanStore } from '../../../supabase/functions/_shared/receipt-scan.ts';

test('bounded HTTP reader preserves payload when network chunks reuse a buffer', async () => {
  const original = JSON.stringify({ images: [{ mimeType: 'image/png', data: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.repeat(4096) }] });
  const bytes = new TextEncoder().encode(original);
  const scratch = new Uint8Array(1024);
  let offset = 0;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (offset === bytes.length) { controller.close(); return; }
      const count = Math.min(scratch.length, bytes.length - offset);
      scratch.set(bytes.subarray(offset, offset + count));
      offset += count;
      controller.enqueue(scratch.subarray(0, count));
    },
  }, { highWaterMark: 0 });
  const result = await readBounded(new Response(body), bytes.length);
  assert.equal(new TextDecoder().decode(result), original);
});
import { calculateReceipt, type ItemSplit } from '../src/item-split.ts';
import { DemoRepository } from '../src/demo.ts';
import { readFileSync } from 'node:fs';

const receipt = { merchant: 'RESTORAN ABC', date: '2026-10-01', items: [{ name: 'NASI GORENG', qty: 1, unit_price: 10000, line_total: 10000, note: null }], subtotal: 10000, service_charge: 500, tax: 1000, discount: 0, rounding: 0, grand_total: 11500, tax_included_in_price: false, unreadable_fields: [] };
test('wholesale quantities remain exact; printed inconsistency is isolated without changing receipt', () => {
  const data = normalizeReceipt(JSON.parse(readFileSync(new URL('../../../tests/fixtures/receipt-wholesale.json', import.meta.url), 'utf8')));
  assert.deepEqual(data.items.map(item => item.qty), [4000, 1600, 1600, 800, 8000, 1600, 1600, 800]);
  assert.deepEqual(data.unreadable_fields, []);
  assert.equal(data.items[7]!.line_total, 7800000);
  assert.equal(data.items.reduce((sum, item) => sum + item.line_total!, 0), 200600000);
  const validation = validateReceipt(data);
  assert.deepEqual(validation.baris_bermasalah, [7]);
  assert.equal(validation.masalah.length, 2);
  assert.match(validation.masalah[0]!.pesan, /Kardus Packing.*600\.000/);
  assert.equal(validation.masalah[1]!.selisih, 600000);
  const draft: ItemSplit = { items: data.items.map((item, index) => ({ id: String(index), name: item.name, quantity: item.qty, unitPrice: String(item.unit_price), allocations: ['a', 'b', 'c'].map(memberID => ({ memberID, quantity: 1 })) })), tax: '0', service: '0', discount: '0', settings: { serviceRate: 0, taxRate: 0, taxOnService: false } };
  const result = calculateReceipt(draft, ['a', 'b', 'c']);
  assert.equal(result.total, '200000000');
  assert.equal(result.rows.reduce((sum, row) => sum + BigInt(row.total), 0n), 200000000n);
  for (const qty of [0, -1, 1000000, 1.5]) {
    const invalid = normalizeReceipt({ ...data, items: [{ ...data.items[0], qty }] });
    assert.equal(invalid.items[0]!.qty, Number.isInteger(qty) ? qty : 1);
    assert.ok(invalid.unreadable_fields.includes('items[0].qty'));
    assert.equal(validateReceipt(invalid).lolos, false);
  }
  draft.items[0]!.quantity = 1000000;
  assert.throws(() => calculateReceipt(draft, ['a', 'b', 'c']), /VALIDATION/);
});
test('large amounts and stable rounding match the shared Swift/PostgreSQL receipt fixture', () => {
  const fixture = JSON.parse(readFileSync(new URL('../../../tests/fixtures/receipt-split-v2.json', import.meta.url), 'utf8'));
  for (const example of fixture.cases) { const result = calculateReceipt(example.draft, example.memberIDs); assert.deepEqual({ total: result.total, shares: result.shares }, example.expected, example.name); }
});
class MemoryStore implements ScanStore {
  result?: ScanResult; claimed = false; calls = 0; quota = false;
  async claim() { if (this.result) return { state: 'cached' as const, result: this.result }; if (this.quota) return { state: 'quota_exceeded' as const }; if (this.claimed) return { state: 'busy' as const }; this.claimed = true; return { state: 'new' as const }; }
  async reserve() { assert.ok(this.calls < 2); this.calls++; return 0; }
  async finish(_userID: string, _hash: string, result: ScanResult) { this.result = result; }
}
const options = (store = new MemoryStore()) => ({ userID: 'user', hash: 'a'.repeat(64), images: [{ mimeType: 'image/jpeg', data: '/9j/AAAA' }], apiKey: 'test-key', model: 'gemini-3.5-flash-lite', store });
const gemini = (data: unknown) => Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ thought: true, text: 'Internal analysis, not JSON' }, { text: JSON.stringify(data) }] } }] });
test('Gemini request schema avoids the maxItems constraint rejected by the configured provider', () => {
  assert.equal('maxItems' in receiptSchema.properties.items, false);
  assert.equal(receiptSchema.properties.items.type, 'ARRAY');
});
test('normalization preserves unreadable totals, cleans prices, fills missing unit price, handles discount and date', () => {
  assert.equal(normalizeAmount('Rp 30.000'), 30000);
  assert.equal(normalizeAmount('Rp 30,000'), 30000);
  const data = normalizeReceipt({ ...receipt, discount: '-1.000', subtotal: null, date: '2026-02-30', items: [{ ...receipt.items[0], qty: 2, unit_price: null, line_total: 'Rp 30.000', name: '  NASI   GORENG  ' }] });
  assert.equal(data.items[0]!.unit_price, 15000); assert.equal(data.items[0]!.name, 'Nasi Goreng'); assert.equal(data.discount, 1000); assert.equal(data.subtotal, null); assert.equal(data.date, null);
  assert.equal(normalizeAmount('<script>'), null);
});
test('validation passes exact receipt, flags line mismatch and subtotal/total differences, tax-inclusive skips added charges', () => {
  const data = normalizeReceipt(receipt); assert.equal(validateReceipt(data).lolos, true);
  data.items[0]!.line_total = 9000;
  const validation = validateReceipt(data); assert.equal(validation.lolos, false); assert.deepEqual(validation.baris_bermasalah, [0]); assert.ok(validation.masalah.some(issue => issue.cek === 2));
  assert.equal(validateReceipt(normalizeReceipt({ ...receipt, tax_included_in_price: true, grand_total: 10000 })).lolos, true);
  assert.equal(validateReceipt(normalizeReceipt({ ...receipt, service_charge: 5000, grand_total: 16000 })).peringatan.length, 1);
});
test('valid receipt uses one Gemini call; cached image uses none', async () => {
  const store = new MemoryStore(); let calls = 0;
  const config = { ...options(store), fetch: (async (url, request) => { calls++; const body = JSON.parse(String(request?.body)); assert.equal(String(url), 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent'); assert.equal(new Headers(request?.headers).get('x-goog-api-key'), 'test-key'); assert.equal(new Headers(request?.headers).get('authorization'), null); assert.ok(body.systemInstruction.parts[0].text); assert.equal(body.generationConfig.maxOutputTokens, 8192); assert.equal(body.generationConfig.responseMimeType, 'application/json'); assert.equal(body.generationConfig.responseSchema.type, 'OBJECT'); assert.equal(body.generationConfig.responseSchema.properties.items.items.type, 'OBJECT'); assert.equal(body.generationConfig.responseSchema.properties.subtotal.type, 'INTEGER'); assert.equal(body.generationConfig.responseSchema.properties.subtotal.nullable, true); assert.equal(body.generationConfig.responseFormat, undefined); assert.deepEqual(body.contents[0].parts[1].inlineData, { mimeType: 'image/jpeg', data: '/9j/AAAA' }); return gemini(receipt); }) as typeof fetch, sleep: async () => {} };
  assert.equal((await scanReceipt(config)).validasi!.lolos, true); assert.equal(calls, 1);
  assert.equal((await scanReceipt(config)).cached, true); assert.equal(calls, 1);
});
test('bad extraction followed by valid extraction uses exactly two calls', async () => {
  const store = new MemoryStore(); let calls = 0;
  const result = await scanReceipt({ ...options(store), sleep: async () => {}, fetch: (async (_url, request) => { calls++; if (calls === 2) assert.match(String(request?.body), /tidak konsisten/); return gemini(calls === 1 ? { ...receipt, subtotal: 9000 } : receipt); }) as typeof fetch });
  assert.equal(result.validasi!.lolos, true); assert.equal(calls, 2); assert.equal(store.calls, 2);
});
test('two inconsistent extractions remain editable and never trigger a third call', async () => {
  const store = new MemoryStore(); const result = await scanReceipt({ ...options(store), sleep: async () => {}, fetch: (async () => gemini({ ...receipt, grand_total: 50000 })) as typeof fetch });
  assert.equal(result.status, 'ok'); assert.equal(result.validasi!.lolos, false); assert.equal(store.calls, 2);
});
test('malformed JSON retries once, invalid second response stops', async () => {
  const store = new MemoryStore(); const result = await scanReceipt({ ...options(store), sleep: async () => {}, fetch: (async () => Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: '{broken' }] } }] })) as typeof fetch });
  assert.equal(result.status, 'service_error'); assert.equal(store.calls, 2);
});
test('429 backoff and optional fallback share hard two-call budget', async () => {
  const store = new MemoryStore(); const waits: number[] = []; const urls: string[] = [];
  const result = await scanReceipt({ ...options(store), fallbackModel: 'fallback', sleep: async wait => { waits.push(wait); }, fetch: (async url => { urls.push(String(url)); return new Response('', { status: 429 }); }) as typeof fetch });
  assert.equal(result.status, 'quota_exceeded'); assert.equal(store.calls, 2); assert.equal(waits[1], 2000); assert.match(urls[1]!, /models\/fallback:generateContent$/);
});
test('configuration errors, daily limits, blocked output, non-receipt and pending cache provide manual fallback', async () => {
  for (const status of [400, 403]) { const store = new MemoryStore(); assert.equal((await scanReceipt({ ...options(store), fetch: (async () => new Response('', { status })) as typeof fetch, sleep: async () => {} })).status, 'config_error'); assert.equal(store.calls, 1); }
  const quota = new MemoryStore(); quota.quota = true; assert.equal((await scanReceipt(options(quota))).status, 'quota_exceeded'); assert.equal(quota.calls, 0);
  const pending = new MemoryStore(); pending.claimed = true; assert.equal((await scanReceipt(options(pending))).status, 'busy');
  assert.equal((await scanReceipt({ ...options(), apiKey: '' })).status, 'config_error');
  assert.equal((await scanReceipt({ ...options(), fetch: (async () => Response.json({ promptFeedback: { blockReason: 'SAFETY' } })) as typeof fetch, sleep: async () => {} })).status, 'no_result');
  assert.equal((await scanReceipt({ ...options(), fetch: (async () => gemini({ ...receipt, items: [] })) as typeof fetch, sleep: async () => {} })).status, 'not_a_receipt');
});
test('incomplete, empty, safety-blocked and thought-only responses stop without billing a retry', async () => {
  for (const payload of [{ candidates: [{ finishReason: 'MAX_TOKENS', content: { parts: [{ text: JSON.stringify(receipt) }] } }] }, { candidates: [] }, { candidates: [{ finishReason: 'SAFETY' }] }, { candidates: [{ finishReason: 'STOP', content: { parts: [{ thought: true, text: JSON.stringify(receipt) }] } }] }, { candidates: [{ content: { parts: [{ text: JSON.stringify(receipt) }] } }] }]) {
    const store = new MemoryStore(); const result = await scanReceipt({ ...options(store), sleep: async () => {}, fetch: (async () => Response.json(payload)) as typeof fetch });
    assert.equal(result.status, 'no_result'); assert.equal(store.calls, 1);
  }
});
test('failed correction retains the first editable receipt', async () => {
  for (const status of [200, 401, 429, 503]) {
    const store = new MemoryStore(); let calls = 0;
    const result = await scanReceipt({ ...options(store), sleep: async () => {}, fetch: (async () => ++calls === 1 ? gemini({ ...receipt, grand_total: 50000 }) : Response.json({ candidates: [{ finishReason: 'MAX_TOKENS' }] }, { status })) as typeof fetch });
    assert.equal(result.status, 'ok'); assert.equal(result.data!.grand_total, 50000); assert.equal(result.validasi!.lolos, false); assert.equal(store.calls, 2);
  }
});
test('network and 5xx errors retry only once', async () => {
  for (const throws of [false, true]) { const store = new MemoryStore(); const result = await scanReceipt({ ...options(store), sleep: async () => {}, fetch: (async () => { if (throws) throw new Error('timeout'); return new Response('', { status: 503 }); }) as typeof fetch }); assert.equal(result.status, 'service_error'); assert.equal(store.calls, 2); }
});
test('image checks enforce type, magic bytes, count, size and deterministic hash', async () => {
  const image = { mimeType: 'image/jpeg', data: btoa(String.fromCharCode(255, 216, 255, ...new Array(13).fill(0))) };
  assert.equal((await validateImages([image])).hash, (await validateImages([image])).hash);
  const bytes = Uint8Array.from(atob(image.data), character => character.charCodeAt(0));
  const legacy = new Uint8Array(bytes.length + 4); new DataView(legacy.buffer).setUint32(0, bytes.length); legacy.set(bytes, 4);
  const oldHash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', legacy))].map(value => value.toString(16).padStart(2, '0')).join('');
  assert.notEqual((await validateImages([image])).hash, oldHash);
  await assert.rejects(validateImages([{ ...image, mimeType: 'image/png' }]), /invalid_image/);
  await assert.rejects(validateImages(new Array(4).fill(image)), /invalid_image/);
  await assert.rejects(validateImages([{ ...image, data: 'a'.repeat(6000000) }]), /invalid_image/);
  await assert.rejects(readBounded(new Response('12345'), 4), /size_limit/);
});
test('discount, inclusive tax and signed rounding reconcile independently across columns', () => {
  const draft: ItemSplit = { items: [{ id: 'menu', name: 'Bersama', quantity: 1, unitPrice: '10000', allocations: ['a', 'b', 'c'].map(memberID => ({ memberID, quantity: 1 })) }], discount: '1000', tax: '0', service: '0', rounding: '-1', settings: { serviceRate: 5, taxRate: 10, taxOnService: false } };
  const first = calculateReceipt(draft, ['a', 'b', 'c']); assert.equal(first.total, '10349'); assert.equal(first.rows.reduce((sum, row) => sum + BigInt(row.discount), 0n), 1000n); assert.equal(first.rows.reduce((sum, row) => sum + BigInt(row.rounding), 0n), -1n);
  draft.settings!.taxIncluded = true; assert.equal(calculateReceipt(draft, ['a', 'b', 'c']).total, '8999');
  draft.rounding = '1'; assert.equal(calculateReceipt(draft, ['a', 'b', 'c']).total, '9001');
});
test('demo stores item details and rejects client tampering without altering ledger', async () => {
  const repository = new DemoRepository(); const snapshot = await repository.snapshot();
  const draft: ItemSplit = { items: [{ id: 'menu', name: 'Bersama', quantity: 1, unitPrice: '10000', allocations: ['a', 'b'].map(memberID => ({ memberID, quantity: 1 })) }], discount: '0', tax: '0', service: '0', settings: { serviceRate: 0, taxRate: 0, taxOnService: false } };
  const payload = { p_client_mutation_id: 'scan-test', p_total: '10000', p_title: 'Scan test', p_item_split: draft, p_payer_kind: 'self', p_payer_account_id: snapshot.accounts[0]!.id, p_category_id: snapshot.categories.find(row => row.kind === 'expense')!.id, p_occurred_at: '2026-10-01T00:00:00Z', p_members: ['a', 'b'].map((id, sort_order) => ({ id, sort_order, display_name: id, is_self: id === 'a', share_amount: '5000' })) };
  await repository.mutate('save_item_split_bill', payload);
  assert.deepEqual((await repository.snapshot()).splitBills.at(-1)!.itemSplit, draft);
  await assert.rejects(repository.mutate('save_item_split_bill', { ...payload, p_client_mutation_id: 'tampered', p_total: '1' }));
});
