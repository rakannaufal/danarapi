import { zipSync, strToU8 } from 'fflate';
import { filterRows, obligations, remaining, selfShare, billRemaining, localDay, type Snapshot, type Filter } from './domain.ts';
import { fingerprint } from './import.ts';

export function csv(rows: unknown[][], numericColumns: number[] = []) {
  return '\ufeff' + rows.map((row, rowIndex) => row.map((value, column) => {
    let text = String(value ?? '');
    if (/^[=+\-@\t\r]/.test(text) && !(rowIndex > 0 && numericColumns.includes(column) && /^-?\d+$/.test(text))) text = `'${text}`;
    return `"${text.replaceAll('"', '""')}"`;
  }).join(',')).join('\r\n') + '\r\n';
}
export function filteredCSV(data: Snapshot, filter: Filter, timezone: string) { return csv([['event_id', 'kind', 'occurred_at', 'amount', 'account_id', 'category_id', 'merchant', 'note'], ...filterRows(data, filter, timezone).map(row => [row.id, row.kind, row.occurredAt, row.amount, row.accountID, row.categoryID, row.merchant, row.note])], [3]); }
export function exportCSVs(data: Snapshot, from = '0001-01-01', to = '9999-12-31', timezone = 'Asia/Jakarta') {
  const includes = (date: string) => { const day = localDay(date, timezone); return day >= from && day <= to; };
  const categoryName = (value: string) => data.categories.find(row => row.id === value)?.name ?? '';
  const accountName = (value?: string) => data.accounts.find(row => row.id === value)?.name ?? '';
  const expenses: unknown[][] = [['event_id', 'source_bill_id', 'occurred_at', 'type', 'amount', 'category', 'merchant', 'is_non_cash']];
  const cash: unknown[][] = [['event_id', 'source_bill_id', 'occurred_at', 'type', 'amount', 'account', 'note']];
  const bills: unknown[][] = [['source_bill_id', 'occurred_at', 'title', 'total', 'payer', 'self_share', 'status', 'remaining']];
  const members: unknown[][] = [['source_bill_id', 'member_id', 'display_name', 'is_self', 'share_amount', 'settled_amount', 'resolved_amount', 'remaining_amount']];
  const settlements: unknown[][] = [['event_id', 'source_bill_id', 'member_id', 'direction', 'account', 'amount', 'occurred_at', 'reversed', 'note']];
  const resolutions: unknown[][] = [['event_id', 'source_bill_id', 'member_id', 'kind', 'amount', 'occurred_at', 'reversed', 'reason']];
  for (const row of data.transactions.filter(row => !row.deleted && includes(row.occurredAt))) { if (row.kind === 'expense') expenses.push([row.id, '', row.occurredAt, row.kind, row.amount, categoryName(row.categoryID), row.merchant, false]); cash.push([row.id, '', row.occurredAt, row.kind, row.kind === 'income' ? row.amount : `-${row.amount}`, accountName(row.accountID), row.note]); }
  for (const row of data.transfers.filter(row => !row.deleted && includes(row.occurredAt))) { cash.push([`${row.id}-out`, '', row.occurredAt, 'transfer_out', `-${row.amount}`, accountName(row.fromAccountID), row.note]); cash.push([`${row.id}-in`, '', row.occurredAt, 'transfer_in', row.amount, accountName(row.toAccountID), row.note]); }
  for (const row of (data.adjustments ?? []).filter(row => includes(row.occurredAt))) cash.push([row.id, '', row.occurredAt, 'adjustment', row.signedAmount, accountName(row.accountID), row.reason]);
  for (const bill of data.splitBills.filter(row => !row.deleted)) {
    const owed = obligations(bill);
    if (includes(bill.occurredAt)) {
      const status = billRemaining(bill) === 0n ? 'settled' : owed.some(member => BigInt(member.settledAmount) + BigInt(member.resolvedAmount) > 0n) ? 'partially_settled' : 'unsettled';
      bills.push([bill.id, bill.occurredAt, bill.title, bill.total, bill.payer.selfPaid ? 'Saya' : bill.members.find(row => row.id === bill.payer.other?.memberID)?.displayName, selfShare(bill), status, owed.reduce((sum, member) => sum + remaining(bill, member), 0n)]);
      expenses.push([bill.id, bill.id, bill.occurredAt, 'split_personal_share', selfShare(bill), categoryName(bill.categoryID), bill.title, false]);
      if (bill.payer.selfPaid) cash.push([bill.id, bill.id, bill.occurredAt, 'split_bill_paid', `-${bill.total}`, accountName(bill.payer.selfPaid.accountID), bill.title]);
      for (const member of bill.members) members.push([bill.id, member.id, member.displayName, member.isSelf, member.shareAmount, member.settledAmount, member.resolvedAmount, owed.includes(member) ? remaining(bill, member) : '0']);
    }
    for (const event of bill.settlements.filter(row => includes(row.occurredAt))) { settlements.push([event.id, bill.id, event.memberID, event.direction, accountName(event.accountID), event.amount, event.occurredAt, event.reversed, event.note]); if (!event.reversed) cash.push([event.id, bill.id, event.occurredAt, `split_settlement_${event.direction}`, event.direction === 'in' ? event.amount : `-${event.amount}`, accountName(event.accountID), event.note]); }
    for (const event of bill.resolutions.filter(row => includes(row.occurredAt))) { resolutions.push([event.id, bill.id, event.memberID, event.kind, event.amount, event.occurredAt, event.reversed, event.reason]); if (!event.reversed && bill.payer.selfPaid) expenses.push([event.id, bill.id, event.occurredAt, event.kind, event.amount, categoryName(bill.categoryID), bill.title, true]); }
  }
  return { 'personal_expenses.csv': csv(expenses, [4]), 'cash_flow.csv': csv(cash, [4]), 'split_bills.csv': csv(bills, [3, 5, 7]), 'split_members.csv': csv(members, [4, 5, 6, 7]), 'split_settlements.csv': csv(settlements, [5]), 'split_resolutions.csv': csv(resolutions, [4]) };
}
export async function demoArchive(data: Snapshot, attachments: Map<string, File>) {
  const files: Record<string, Uint8Array> = { 'data.json': strToU8(JSON.stringify({ schema_version: '1.0.0', synthetic: true, ...data }, null, 2)) };
  for (const [name, text] of Object.entries(exportCSVs(data))) files[name] = strToU8(text);
  for (const [reviewID, file] of attachments) files[`attachments/${reviewID.replaceAll(':', '_')}.${file.type === 'application/pdf' ? 'pdf' : file.type === 'image/png' ? 'png' : 'jpg'}`] = new Uint8Array(await file.arrayBuffer());
  const manifest = await Promise.all(Object.entries(files).map(async ([name, bytes]) => ({ name, bytes: bytes.length, sha256: await fingerprint(bytes) })));
  files['manifest.json'] = strToU8(JSON.stringify({ schema_version: '1.0.0', synthetic: true, file_count: manifest.length, files: manifest }, null, 2));
  return new Blob([new Uint8Array(zipSync(files))], { type: 'application/zip' });
}
export function download(name: string, value: Blob | string) {
  const url = URL.createObjectURL(value instanceof Blob ? value : new Blob([value], { type: 'text/csv;charset=utf-8' }));
  const anchor = document.createElement('a'); anchor.href = url; anchor.download = name; anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
