import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { demoSeed } from '../../apps/web/src/demo.ts';
import { derive, localDay } from '../../apps/web/src/domain.ts';
import { exportCSVs } from '../../apps/web/src/export.ts';

const data = demoSeed();
data.reviewItems = [];
data.transactions.push({ ...data.transactions[0], id: 'parity-boundary', amount: '999999999999', merchant: '=SUM(1,2)', note: 'Baris satu\nBaris dua, "kutipan"', occurredAt: '2026-08-31T17:00:00.000Z' });
data.transactions.push({ ...data.transactions[0], id: 'parity-deleted', deleted: true });
data.transfers.push({ id: 'parity-transfer', fromAccountID: data.accounts[0].id, toAccountID: data.accounts[1].id, amount: '23456', occurredAt: '2026-09-02T04:00:00Z', deleted: false, version: 1, note: '-not-a-number' });
const ownBill = data.splitBills.find(bill => bill.payer.selfPaid)!;
ownBill.resolutions.push({ id: 'parity-writeoff', memberID: ownBill.members[2].id, kind: 'receivable_writeoff', amount: '1000', occurredAt: '2026-09-28T05:00:00Z', reversed: false, version: 1, reason: 'Pilihan pengguna' });
ownBill.settlements.push({ id: 'parity-reversed', memberID: ownBill.members[2].id, accountID: data.accounts[0].id, direction: 'in', amount: '1000', occurredAt: '2026-09-28T04:00:00Z', reversed: true, version: 2 });
const otherBill = data.splitBills.find(bill => bill.payer.other)!;
otherBill.members[0].shareAmount = '30000';
otherBill.members[1].shareAmount = '45000';
otherBill.members[2].shareAmount = (BigInt(otherBill.total) - 75000n).toString();
otherBill.resolutions.push({ id: 'parity-forgiveness', memberID: otherBill.payer.other!.memberID, kind: 'payable_forgiveness', amount: '1000', occurredAt: '2026-09-29T05:00:00Z', reversed: false, version: 1, reason: 'Dibebaskan' });
data.splitBills.push({ ...structuredClone(ownBill), id: 'parity-deleted-bill', deleted: true });
const snapshot = derive(data);
const input = `${process.argv[3]}/snapshot.json`;
writeFileSync(input, JSON.stringify({ ...snapshot, accounts: snapshot.accounts.map(row => ({ ...row, openedAt: new Date(row.openedAt).toISOString() })), budgets: snapshot.budgets.map(row => ({ ...row, month: new Date(row.month).toISOString() })), transactions: snapshot.transactions.map(row => ({ ...row, pendingSync: false })), transfers: snapshot.transfers.map(row => ({ ...row, pendingSync: false })), splitBills: snapshot.splitBills.map(bill => ({ ...bill, members: bill.members.map(member => ({ ...member, obligationAmount: bill.payer.other?.memberID === member.id ? bill.members.find(candidate => candidate.isSelf)?.shareAmount : null })) })) }));
const server: Record<string, string> = JSON.parse(execFileSync('deno', ['run', '--allow-env', `--allow-read=${input}`, 'tests/integration/server-export.ts', input], { encoding: 'utf8' }));
const native: Record<string, string> = JSON.parse(execFileSync(process.argv[2], [input], { encoding: 'utf8' }));

function parseCSV(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [], value = '', quoted = false;
  const source = text.replace(/^\ufeff/, '');
  for (let index = 0; index < source.length; index++) {
    const character = source[index];
    if (character === '"') { if (quoted && source[index + 1] === '"') { value += '"'; index++; } else quoted = !quoted; }
    else if (!quoted && character === ',') { row.push(value); value = ''; }
    else if (!quoted && character === '\r' && source[index + 1] === '\n') { row.push(value); rows.push(row); row = []; value = ''; index++; }
    else value += character;
  }
  assert.equal(quoted, false);
  assert.equal(value, '');
  return rows;
}
function canonical(rows: string[][]) {
  return [rows[0], ...rows.slice(1).map(row => row.map(value => /^\d{4}-\d\d-\d\dT/.test(value) ? new Date(value).toISOString() : value)).sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)))];
}
const web = exportCSVs(snapshot);
for (const [name, csv] of Object.entries(web)) {
  assert.deepEqual(canonical(parseCSV(server[name])), canonical(parseCSV(csv)), `server parity ${name}`);
  assert.deepEqual(canonical(parseCSV(native[name])), canonical(parseCSV(csv)), `Swift parity ${name}`);
}
for (const timezone of ['UTC', 'Asia/Jakarta', 'Asia/Makassar', 'Asia/Jayapura']) for (const month of ['2026-07', '2026-08', '2026-09']) {
  const from = `${month}-01`, to = `${month}-31`;
  const within = (timestamp: string) => localDay(timestamp, timezone) >= from && localDay(timestamp, timezone) <= to;
  const billIDs = new Set(snapshot.splitBills.filter(bill => within(bill.occurredAt)).map(bill => bill.id));
  const expected = exportCSVs(snapshot, from, to, timezone);
  for (const [name, csv] of Object.entries(expected)) for (const [client, files] of [['server', server], ['Swift', native]] as const) {
    const full = parseCSV(files[name]), timeColumn = full[0].indexOf('occurred_at');
    const filtered = [full[0], ...full.slice(1).filter(row => timeColumn >= 0 ? within(row[timeColumn]) : billIDs.has(row[0]))];
    assert.deepEqual(canonical(filtered), canonical(parseCSV(csv)), `${client} ${name} ${month} ${timezone}`);
  }
}
console.log('Export parity passed: 6 CSVs × 3 implementations; 12 month/timezone windows; negative numbers, formula escaping, multiline text, both payers, reversal, noncash, deleted records.');
