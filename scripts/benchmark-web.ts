import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { demoSeed } from '../apps/web/src/demo.ts';
import { derive, filterRows, reportFor } from '../apps/web/src/domain.ts';
import { exportCSVs } from '../apps/web/src/export.ts';

const results = [];
for (const count of [10000, 50000]) {
  const data = demoSeed(), source = [...data.transactions];
  data.transactions = Array.from({ length: count }, (_, index) => ({ ...source[index % source.length], id: `performance-${index}` }));
  const initial = performance.now();
  derive(data);
  const derived = performance.now();
  const rows = filterRows(data, { query: 'warung', kind: '', account: '', category: '', from: '', to: '' }, 'Asia/Jakarta');
  const filtered = performance.now();
  const report = reportFor(data, '2026-09-01', '2026-09-30', 'Asia/Jakarta');
  const reported = performance.now();
  const files = exportCSVs(data);
  const exported = performance.now();
  assert.equal(data.transactions.length, count);
  assert.equal(Object.keys(files).length, 6);
  assert.match(report.personalExpense, /^\d+$/);
  results.push({ transactions: count, filteredRows: rows.length, deriveMs: +(derived - initial).toFixed(1), filterMs: +(filtered - derived).toFixed(1), reportMs: +(reported - filtered).toFixed(1), exportMs: +(exported - reported).toFixed(1), csvBytes: Object.values(files).reduce((total, text) => total + Buffer.byteLength(text), 0) });
}
console.log(JSON.stringify({ scope: 'Node domain/export synthetic benchmark; not HTTP prefetch, browser main thread, ZIP or production SLA', results }, null, 2));
