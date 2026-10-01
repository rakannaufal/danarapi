import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { calculateReceipt, splitItems, type ItemSplit } from "../src/item-split.ts";

const fixture = JSON.parse(readFileSync(new URL("../../../tests/fixtures/item-split-v1.json", import.meta.url), "utf8"));
test("item split matches the shared PostgreSQL and Swift golden fixture", () => {
  for (const example of fixture.cases) assert.deepEqual(splitItems(example.draft, example.memberIDs), example.expected, example.name);
});
test("item split rejects incomplete allocation, duplicates and monetary overflow", () => {
  const invalid = structuredClone(fixture.cases[0].draft);
  invalid.items[0].allocations[0].quantity = 0;
  assert.throws(() => splitItems(invalid, ["a", "b", "c"]), /VALIDATION/);
  const duplicate = structuredClone(fixture.cases[0].draft);
  duplicate.items[0].allocations[1].memberID = "a";
  assert.throws(() => splitItems(duplicate, ["a", "b", "c"]), /VALIDATION/);
  const overflow = structuredClone(fixture.cases[0].draft);
  overflow.items[0].unitPrice = "999999999999";
  assert.throws(() => splitItems(overflow, ["a", "b", "c"]), /VALIDATION/);
});
test("item split rejects non-string receipt and participant identities", () => {
  for (const field of ["id", "name"]) {
    const invalid = structuredClone(fixture.cases[0].draft);
    invalid.items[0][field] = 42;
    assert.throws(() => splitItems(invalid, ["a", "b", "c"]), /VALIDATION/);
  }
  assert.throws(() => splitItems(fixture.cases[0].draft, [1, "b", "c"] as unknown as string[]), /VALIDATION/);
});

function receipt(prices: string[], owners = prices.map((_, index) => [String(index)])): ItemSplit {
  return { items: prices.map((price, index) => ({ id: String(index), name: `Menu ${index}`, quantity: 1, unitPrice: price, allocations: owners[index]!.map(memberID => ({ memberID, quantity: 1 })) })), tax: '0', service: '0', discount: '0', settings: { serviceRate: 5, taxRate: 10, taxOnService: false } };
}
test('Restoran ABC matches every independently rounded column', () => {
  const result = calculateReceipt(receipt(['38000', '85000', '50000', '70000', '55000']), ['0', '1', '2', '3', '4']);
  assert.equal(result.total, '342700');
  assert.deepEqual(result.rows.map(row => row.total), ['43700', '97750', '57500', '80500', '63250']);
  assert.deepEqual(['subtotal', 'service', 'tax'].map(key => result.rows.reduce((sum, row) => sum + BigInt(row[key as 'subtotal']), 0n)), [298000n, 14900n, 29800n]);
});
test('shared quantities divide equally, each column reconciles, ties use participant order', () => {
  const draft = receipt(['10000'], [['a', 'b', 'c']]);
  draft.settings!.serviceRate = 0; draft.settings!.taxRate = 0;
  assert.deepEqual(calculateReceipt(draft, ['a', 'b', 'c']).rows.map(row => row.total), ['3334', '3333', '3333']);
  draft.items[0]!.quantity = 2; draft.items[0]!.unitPrice = '35000';
  draft.items[0]!.allocations = draft.items[0]!.allocations.filter(entry => entry.memberID !== 'c');
  assert.deepEqual(splitItems(draft, ['a', 'b']).shares, { a: '35000', b: '35000' });
});
test('unassigned menus warn, stale owners are ignored, empty price and zero quantity count as zero', () => {
  const draft = receipt(['10000', ''], [['deleted'], []]);
  const result = calculateReceipt(draft, ['a', 'b']);
  assert.deepEqual(result.unassigned, ['Menu 0']); assert.equal(result.total, '0');
  assert.throws(() => splitItems(draft, ['a', 'b']), /VALIDATION/);
  draft.items[0]!.quantity = 0;
  assert.deepEqual(calculateReceipt(draft, ['a', 'b']).unassigned, []);
});
test('tax includes service only when enabled; invalid rates and overflow reject', () => {
  const draft = receipt(['10000'], [['a', 'b']]); draft.settings!.taxOnService = true;
  assert.equal(splitItems(draft, ['a', 'b']).total, '11550');
  for (const rate of [-1, 101, 1.234, NaN, Infinity]) { draft.settings!.taxRate = rate; assert.throws(() => calculateReceipt(draft, ['a', 'b']), /VALIDATION/); }
  draft.settings!.taxRate = 10; draft.items[0]!.unitPrice = '999999999999';
  assert.throws(() => calculateReceipt(draft, ['a', 'b']), /VALIDATION/);
});
