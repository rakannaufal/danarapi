import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const files = [
  "contracts/design-tokens.json",
  "contracts/v1/errors.json",
  "contracts/v1/ledger.schema.json",
  "tests/fixtures/error-v1.json",
  "tests/fixtures/ledger-v1.json",
  "tests/fixtures/demo-seed-v1.json",
  "tests/fixtures/item-split-v1.json",
  "tests/fixtures/receipt-split-v2.json",
  "contracts/v1/planning.schema.json"
];

for (const file of files) JSON.parse(readFileSync(resolve(file), "utf8"));

const demo = JSON.parse(readFileSync(resolve("tests/fixtures/demo-seed-v1.json"), "utf8"));
if (demo.synthetic !== true || demo.transactions.length !== 200) throw new Error("Demo seed must contain exactly 200 synthetic transactions");
if (demo.transactions.some((item) => typeof item.amount !== "string")) throw new Error("Demo amounts must be decimal strings");
console.log(`Validated ${files.length} JSON files and 200 synthetic demo transactions.`);
