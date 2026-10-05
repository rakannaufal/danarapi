import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { showcase } from "./demo-showcase.mjs";

let state = 0x0d4a4a91;
function random() {
  state ^= state << 13;
  state ^= state >>> 17;
  state ^= state << 5;
  return (state >>> 0) / 0x1_0000_0000;
}

const accounts = [
  { id: "cash", name: "Tunai", kind: "cash", opening_balance: "500000" },
  { id: "bank", name: "Bank Demo", kind: "bank", opening_balance: "2500000" }
];
const categories = [
  { id: "food", name: "Makan", kind: "expense" },
  { id: "transport", name: "Transportasi", kind: "expense" },
  { id: "household", name: "Rumah", kind: "expense" },
  { id: "salary", name: "Gaji", kind: "income" }
];
const merchants = ["Warung Pagi", "Pasar Lokal", "Bus Kota", "Toko Buku", "Kedai Sore", "Apotek Demo"];

const transactions = Array.from({ length: 200 }, (_, index) => {
  const date = new Date(Date.UTC(2026, 6, 1 + (index % 92), 1 + (index % 10), (index * 7) % 60));
  const isIncome = index % 47 === 0;
  const category = isIncome ? categories[3] : categories[index % 3];
  const amount = isIncome ? 4_500_000 : 8_000 + Math.floor(random() * 142_000);
  return {
    id: `demo-transaction-${String(index + 1).padStart(3, "0")}`,
    type: isIncome ? "income" : "expense",
    amount: String(amount),
    account_id: index % 4 === 0 ? "cash" : "bank",
    category_id: category.id,
    merchant: isIncome ? "Pemberi kerja sintetis" : merchants[index % merchants.length],
    occurred_at: date.toISOString()
  };
});

const fixture = {
  schema_version: "1.0.0",
  seed: "danarapi-demo-v1",
  synthetic: true,
  showcase,
  timezone: "Asia/Jakarta",
  period: { from: "2026-07-01T00:00:00.000Z", to: "2026-09-30T23:59:59.999Z" },
  accounts,
  categories,
  budgets: [
    { category_id: "food", month: "2026-09", limit_amount: "1800000" },
    { category_id: "transport", month: "2026-09", limit_amount: "700000" }
  ],
  split_bills: [
    { id: "demo-bill-self", total: "120000", self_share: "40000", payer: "self", status: "partially_settled", settled_amount: "15000", resolved_amount: "0" },
    { id: "demo-bill-other", total: "90000", self_share: "30000", payer: "Ani", status: "unsettled", settled_amount: "0", resolved_amount: "0" }
  ],
  transactions
};

const output = resolve(process.cwd(), "tests/fixtures/demo-seed-v1.json");
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(fixture, null, 2)}\n`);
