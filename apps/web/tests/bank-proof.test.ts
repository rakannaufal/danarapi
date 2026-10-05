import assert from 'node:assert/strict';
import test from 'node:test';
import { bankProofPrompt, normalizeBankProof, scanBankProof, validateBankProofInput } from '../../../supabase/functions/_shared/bank-proof.ts';
import { validateImages, type ScanStore } from '../../../supabase/functions/_shared/receipt-scan.ts';
import type { ScanResult } from '../../../supabase/functions/_shared/receipt.ts';

const bsi = { amount: 45900, merchant: 'Tokopedia', recipient: 'TPRTokopediaShop', date: '2026-10-05', time: '10:23:50', utc_offset: null, fee: 0, total: 45900, currency: 'IDR', provider: 'BYOND by BSI', reference: 'TEST-123', transaction_type: 'payment', transaction_status: 'success', unreadable_fields: [] };
const gopay = { ...bsi, amount: 10000, merchant: null, recipient: 'M Rakan Naufal', date: '2026-09-29', time: '13:10:00', total: 10000, provider: 'GoPay', transaction_type: 'transfer' };
class Store implements ScanStore {
  calls = 0; result?: ScanResult;
  async claim() { return this.result ? { state: 'cached' as const, result: this.result } : { state: 'new' as const }; }
  async reserve() { return this.calls++ * 0; }
  async finish(_owner: string, _hash: string, result: ScanResult) { this.result = result; }
}
const options = (store = new Store()) => ({ userID: 'user', hash: 'a'.repeat(64), images: [], text: 'Bukti sintetis', apiKey: 'test-key', model: 'gemini-3.5-flash-lite', store, sleep: async () => {} });
const response = (data: unknown) => Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ thought: true, text: 'Private reasoning' }, { text: JSON.stringify(data) }] } }] });

test('bank prompt separates source, destination, nominal, waived fees and untrusted instructions', () => {
  for (const phrase of ['bukan instruksi', 'pemilik rekening sumber', 'Gratis!', 'nomor rekening/VA/referensi', 'Waktu dan Tanggal', 'antar akun sendiri']) assert.ok(bankProofPrompt.includes(phrase));
});
test('BSI and GoPay structured data preserves destination, datetime and effective fee', () => {
  const bank = normalizeBankProof(bsi); assert.equal(bank.amount, 45900); assert.equal(bank.merchant, 'Tokopedia'); assert.equal(bank.recipient, 'TPRTokopediaShop'); assert.equal(bank.time, '10:23:50');
  const wallet = normalizeBankProof(gopay); assert.equal(wallet.amount, 10000); assert.equal(wallet.fee, 0); assert.equal(wallet.merchant, null); assert.equal(wallet.date, '2026-09-29'); assert.equal(wallet.time, '13:10:00'); assert.ok(wallet.warnings.some(v => v.includes('kepemilikan')));
});
test('unsafe, ambiguous, non-IDR and unsuccessful nominal remain empty without rewriting evidence', () => {
  for (const fields of [{ amount: 0 }, { amount: -1 }, { amount: 1.2 }, { amount: '45900' }, { amount: 1e15 }, { currency: 'USD' }, { currency: null }, { transaction_status: 'pending' }, { transaction_status: 'failed' }, { transaction_status: 'unknown' }, { total: 47900 }]) {
    const proof = normalizeBankProof({ ...bsi, ...fields }); assert.equal(proof.amount, null, JSON.stringify(fields)); assert.ok(proof.unreadable_fields.includes('amount'));
  }
  const malformed = normalizeBankProof({ ...bsi, date: '2026-02-30', time: '25:90:00', utc_offset: 'BAD' });
  assert.equal(malformed.date, null); assert.equal(malformed.time, null); assert.equal(malformed.utc_offset, null);
  const partial = normalizeBankProof({ ...bsi, fee: null }); assert.equal(partial.fee, null); assert.equal(partial.amount, 45900);
  assert.throws(() => normalizeBankProof(null));
});
test('missing critical fields requested by model suppress auto-fill', () => {
  const proof = normalizeBankProof({ ...bsi, unreadable_fields: ['amount', 'merchant'] });
  assert.ok(proof.unreadable_fields.includes('amount'));
  assert.equal(proof.amount, null); assert.equal(proof.merchant, null);
});
test('bank cache namespace differs from menu cache, accounts share no client identifier, text is bounded', async () => {
  const image = { mimeType: 'image/jpeg', data: btoa(String.fromCharCode(255, 216, 255, ...new Array(13).fill(0))) };
  const menu = await validateImages([image]); const bank = await validateBankProofInput({ images: [image] });
  assert.notEqual(menu.hash, bank.hash); assert.equal(bank.hash, (await validateBankProofInput({ images: [image] })).hash);
  assert.notEqual(bank.hash, (await validateBankProofInput({ images: [image], text: 'different proof' })).hash);
  assert.notEqual(bank.hash, (await validateBankProofInput({ images: [image], retryID: '01234567-1234-1234-1234-012345678901' })).hash);
  await assert.rejects(validateBankProofInput({ images: [image], retryID: 'unbounded-string' }));
  assert.equal((await validateBankProofInput({ images: [], text: 'Nominal Rp10.000' })).images.length, 0);
  for (const input of [{ images: [] }, { images: [], text: '\0abc' }, { images: [], text: 'x'.repeat(65537) }, { images: [], text: {} }, { images: [image, image, image, image] }]) await assert.rejects(validateBankProofInput(input));
});
test('AI transport sends dedicated schema, no menu rows; cached bank proof uses no extra calls', async () => {
  const store = new Store();
  const config = { ...options(store), fetch: (async (_url, request) => {
    const body = JSON.parse(String(request?.body)); assert.ok(body.systemInstruction.parts[0].text.includes('GoPay'));
    assert.equal(body.generationConfig.responseSchema.properties.items, undefined);
    assert.equal(body.contents[0].parts[1].text, 'Bukti sintetis');
    return response(gopay);
  }) as typeof fetch };
  const value = await scanBankProof(config); assert.equal(value.status, 'ok'); assert.equal(value.proof!.amount, 10000); assert.equal(value.data, undefined);
  assert.equal((await scanBankProof(config)).cached, true); assert.equal(store.calls, 1);
});
test('malformed response and transient failure retry at most once; blocked output never retries', async () => {
  for (const payload of [null, { candidates: [{ finishReason: 'MAX_TOKENS' }] }, { promptFeedback: { blockReason: 'SAFETY' } }]) {
    const store = new Store(); const value = await scanBankProof({ ...options(store), fetch: (async () => Response.json(payload)) as typeof fetch });
    assert.ok(['service_error', 'no_result'].includes(value.status)); assert.ok(store.calls <= 2); assert.equal(value.proof, undefined);
  }
  const store = new Store(); const value = await scanBankProof({ ...options(store), fetch: (async () => new Response('', { status: 503 })) as typeof fetch });
  assert.equal(value.status, 'service_error'); assert.equal(store.calls, 2);
  const recovered = new Store(); const success = await scanBankProof({ ...options(recovered), fetch: (async () => recovered.calls === 1 ? new Response('', { status: 503 }) : response(bsi)) as typeof fetch });
  assert.equal(success.proof!.merchant, 'Tokopedia'); assert.equal(recovered.calls, 2);
});
