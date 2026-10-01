import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { parseMoney } from "../src/contracts.ts";
import { splitEqual, splitPercentage } from "../src/split.ts";

const fixturePath = fileURLToPath(new URL("../../../tests/fixtures/ledger-v1.json", import.meta.url));
const fixture = JSON.parse(readFileSync(fixturePath, "utf8"));

test("golden fixture uses contract v1", () => {
  assert.equal(fixture.schema_version, "1.0.0");
});

test("IDR JSON boundary accepts decimal strings only", () => {
  for (const value of fixture.money.valid) assert.doesNotThrow(() => parseMoney(value, value === "0"));
  for (const value of fixture.money.invalid) assert.throws(() => parseMoney(value, true), /VALIDATION/);
});

test("equal split distributes remainder in visible order", () => {
  for (const item of fixture.split_rounding.filter((entry: any) => entry.method === "equal")) {
    assert.deepEqual(splitEqual(item.total, item.participants), item.expected, item.id);
  }
});

test("percentage split uses largest remainder and stable order", () => {
  for (const item of fixture.split_rounding.filter((entry: any) => entry.method === "percentage")) {
    assert.deepEqual(splitPercentage(item.total, item.participants), item.expected, item.id);
  }
});

test("all expected financial amounts remain JSON strings", () => {
  const walk = (value: unknown, key = "") => {
    if (Array.isArray(value)) return value.forEach((entry) => walk(entry, key));
    if (value && typeof value === "object") {
      for (const [childKey, child] of Object.entries(value)) walk(child, childKey);
      return;
    }
    if (/amount|balance|cash|receivable|payable|expense|income|position|total|share|remaining/.test(key) && typeof value === "number") {
      assert.fail(`${key} must not be a JSON number`);
    }
  };
  walk(fixture);
});
