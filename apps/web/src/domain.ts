import { parseMoney } from './contracts.ts';
import { splitEqual, splitPercentage } from './split.ts';
import type { ItemSplit } from './item-split.ts';
import type { StoredReceipt } from './receipt.ts';
import { allocationBreakdown } from '../../../supabase/functions/_shared/planning.ts';

export type Kind = 'income' | 'expense';
export interface Account { id: string; name: string; kind: string; openingBalance: string; balance: string; openedAt: string; archived: boolean; version: number }
export interface Category { id: string; name: string; kind: Kind; systemKey?: string | null; archived: boolean; sortOrder: number; version: number }
export interface Transaction { id: string; kind: Kind; amount: string; accountID: string; categoryID: string; goalID?: string | null; occurredAt: string; merchant?: string; note?: string; source: string; deleted: boolean; version: number }
export interface Transfer { id: string; fromAccountID: string; toAccountID: string; amount: string; occurredAt: string; note?: string; deleted: boolean; version: number }
export interface Member { id: string; displayName: string; isSelf: boolean; shareAmount: string; settledAmount: string; resolvedAmount: string; sortOrder: number; obligationAmount?: string | null }
export interface BillEvent { id: string; memberID: string; accountID?: string; direction?: 'in' | 'out'; kind?: string; amount: string; occurredAt: string; reason?: string; note?: string; reversed: boolean; version: number }
export interface Bill { id: string; title: string; total: string; categoryID: string; payer: { selfPaid?: { accountID: string }; other?: { memberID: string } }; occurredAt: string; note?: string; itemSplit?: ItemSplit; members: Member[]; settlements: BillEvent[]; resolutions: BillEvent[]; deleted: boolean; version: number }
export interface Field { value: string | null; confidence: 'high' | 'medium' | 'low'; evidenceSpan: string | null; sourceType: string }
export interface Review { id: string; source: string; status: string; amount: Field; merchant: Field; date: Field; rawReference?: string; fingerprint?: string; duplicateCandidateID?: string | null; attachmentName?: string | null; createdAt: string; receipt?: StoredReceipt | null }
export interface Budget { id: string; categoryID: string; month: string; limitAmount: string; spentAmount: string }
export interface SavingsGoal { id: string; name: string; targetAmount: string; savedAmount: string; openingAmount?: string; targetDate: string | null; version: number }
export interface MerchantRule { id: string; matchType: string; normalizedPattern: string; categoryID: string; priority: number; version: number }
export interface Overview { accountBalance: string; receivables: string; payables: string; netPosition: string; personalIncome: string; personalExpense: string }
export interface Snapshot { accounts: Account[]; categories: Category[]; transactions: Transaction[]; transfers: Transfer[]; splitBills: Bill[]; reviewItems: Review[]; budgets: Budget[]; goals?: SavingsGoal[]; merchantRules: MerchantRule[]; overview: Overview; syncedAt?: string | null; timezone?: string }
export interface Report { personalIncome: string; personalExpense: string; categories: { categoryID: string; amount: string }[]; allocations?: { id: string; name: string; amount: string }[] }
export interface Filter { query: string; kind: string; account: string; category: string; from: string; to: string }
export interface ListRow { id: string; kind: string; amount: string; accountID: string; categoryID: string; goalID?: string | null; occurredAt: string; merchant?: string; note?: string; version: number }
export const emptySnapshot = (): Snapshot => ({ accounts: [], categories: [], transactions: [], transfers: [], splitBills: [], reviewItems: [], budgets: [], goals: [], merchantRules: [], overview: { accountBalance: '0', receivables: '0', payables: '0', netPosition: '0', personalIncome: '0', personalExpense: '0' } });
export const id = () => crypto.randomUUID();
export const normalize = (value: string) => value.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('id-ID').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
export const money = (amount: string | bigint) => `Rp${BigInt(amount).toLocaleString('id-ID')}`;
const dayFormatters = new Map<string, Intl.DateTimeFormat>();
export function localDay(date: string, timezone = 'Asia/Jakarta') {
  let formatter = dayFormatters.get(timezone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat('sv-SE', { timeZone: timezone });
    if (dayFormatters.size >= 32) dayFormatters.clear();
    dayFormatters.set(timezone, formatter);
  }
  return formatter.format(new Date(date));
}
export const selfShare = (bill: Bill) => BigInt(bill.members.find(member => member.isSelf)?.shareAmount ?? '0');
export const obligations = (bill: Bill) => bill.members.filter(member => bill.payer.selfPaid ? !member.isSelf : member.id === bill.payer.other?.memberID);
export const remaining = (bill: Bill, member: Member) => (bill.payer.selfPaid ? BigInt(member.shareAmount) : selfShare(bill)) - BigInt(member.settledAmount) - BigInt(member.resolvedAmount);
export const billRemaining = (bill: Bill) => obligations(bill).reduce((sum, member) => sum + remaining(bill, member), 0n);
export const billStatus = (bill: Bill) => billRemaining(bill) === 0n ? 'Lunas' : bill.settlements.some(event => !event.reversed) || bill.resolutions.some(event => !event.reversed) ? 'Lunas sebagian' : 'Belum lunas';
export function validateDate(value: unknown): string {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) throw new Error('Tanggal tidak valid.');
  return new Date(value).toISOString();
}
export function calculateShares(total: string, members: { id: string; value: string }[], method: string) {
  parseMoney(total);
  if (new Set(members.map(member => member.id)).size !== members.length) throw new Error('Peserta ganda.');
  if (method === 'equal') return splitEqual(total, members.map(member => ({ id: member.id, included: true })));
  if (method === 'percentage') return splitPercentage(total, members.map(member => ({ id: member.id, basis_points: Number(member.value) * 100 })));
  if (members.length < 2 || members.length > 20 || members.reduce((sum, member) => sum + parseMoney(member.value, true), 0n) !== BigInt(total)) throw new Error('Jumlah porsi harus sama dengan total.');
  return Object.fromEntries(members.map(member => [member.id, member.value]));
}
export function reportFor(data: Snapshot, from: string, to: string, timezone = 'Asia/Jakarta'): Report {
  const includes = (date: string) => { const day = localDay(date, timezone); return day >= from && day <= to; };
  let income = 0n, expense = 0n;
  const categories = new Map<string, bigint>();
  const addExpense = (category: string, amount: bigint) => { expense += amount; categories.set(category, (categories.get(category) ?? 0n) + amount); };
  for (const transaction of data.transactions.filter(row => !row.deleted && includes(row.occurredAt))) {
    if (transaction.kind === 'income') income += BigInt(transaction.amount); else addExpense(transaction.categoryID, BigInt(transaction.amount));
  }
  for (const bill of data.splitBills.filter(row => !row.deleted)) {
    if (includes(bill.occurredAt)) addExpense(bill.categoryID, selfShare(bill));
    for (const event of bill.resolutions.filter(row => !row.reversed && includes(row.occurredAt))) {
      if (bill.payer.selfPaid) addExpense(bill.categoryID, BigInt(event.amount)); else income += BigInt(event.amount);
    }
  }
  const categoryRows = [...categories].map(([categoryID, amount]) => ({ categoryID, amount: amount.toString() })).sort((left, right) => BigInt(left.amount) > BigInt(right.amount) ? -1 : 1);
  const contributions = data.transactions.filter(row => !row.deleted && row.kind === 'expense' && row.goalID && includes(row.occurredAt)).map(row => ({ categoryID: row.categoryID, goalID: row.goalID!, amount: row.amount }));
  const budgetCategories = new Set(data.budgets.filter(row => row.month.slice(0,7) >= from.slice(0,7) && row.month.slice(0,7) <= to.slice(0,7)).map(row => row.categoryID));
  return { personalIncome: income.toString(), personalExpense: expense.toString(), categories: categoryRows, allocations: allocationBreakdown(categoryRows, contributions, data.goals ?? [], data.categories, budgetCategories) };
}
export function derive(data: Snapshot, timezone = 'Asia/Jakarta'): Snapshot {
  for (const goal of data.goals ?? []) {
    goal.openingAmount ??= goal.savedAmount;
    goal.savedAmount = (BigInt(goal.openingAmount) + data.transactions.filter(row => !row.deleted && row.kind === 'expense' && row.goalID === goal.id).reduce((sum, row) => sum + BigInt(row.amount), 0n)).toString();
  }
  const cash = new Map(data.accounts.map(account => [account.id, BigInt(account.openingBalance)]));
  const addCash = (account: string, amount: bigint) => cash.set(account, (cash.get(account) ?? 0n) + amount);
  for (const transaction of data.transactions.filter(row => !row.deleted)) addCash(transaction.accountID, BigInt(transaction.amount) * (transaction.kind === 'income' ? 1n : -1n));
  for (const transfer of data.transfers.filter(row => !row.deleted)) { addCash(transfer.fromAccountID, -BigInt(transfer.amount)); addCash(transfer.toAccountID, BigInt(transfer.amount)); }
  let receivables = 0n, payables = 0n;
  for (const bill of data.splitBills.filter(row => !row.deleted)) {
    for (const member of bill.members) {
      member.settledAmount = bill.settlements.filter(event => !event.reversed && event.memberID === member.id).reduce((sum, event) => sum + BigInt(event.amount), 0n).toString();
      member.resolvedAmount = bill.resolutions.filter(event => !event.reversed && event.memberID === member.id).reduce((sum, event) => sum + BigInt(event.amount), 0n).toString();
    }
    if (bill.payer.selfPaid) { addCash(bill.payer.selfPaid.accountID, -BigInt(bill.total)); receivables += billRemaining(bill); } else payables += billRemaining(bill);
    for (const event of bill.settlements.filter(row => !row.reversed)) addCash(event.accountID!, BigInt(event.amount) * (event.direction === 'in' ? 1n : -1n));
  }
  for (const account of data.accounts) account.balance = (cash.get(account.id) ?? 0n).toString();
  const accountBalance = [...cash.values()].reduce((sum, amount) => sum + amount, 0n);
  const report = reportFor(data, '0001-01-01', '9999-12-31');
  data.overview = { accountBalance: accountBalance.toString(), receivables: receivables.toString(), payables: payables.toString(), netPosition: (accountBalance + receivables - payables).toString(), personalIncome: report.personalIncome, personalExpense: report.personalExpense };
  const budgetReports = new Map<string, Report>();
  for (const budget of data.budgets) {
    const month = budget.month.slice(0, 7);
    let monthReport = budgetReports.get(month);
    if (!monthReport) { monthReport = reportFor(data, `${month}-01`, `${month}-31`, timezone); budgetReports.set(month, monthReport); }
    budget.spentAmount = monthReport.categories.find(row => row.categoryID === budget.categoryID)?.amount ?? '0';
  }
  return data;
}
export function assertDecimalPayload(value: unknown, key = ''): void {
  if (Array.isArray(value)) { for (const row of value) assertDecimalPayload(row, key); return; }
  if (value && typeof value === 'object') { if (key === 'amount' && 'value' in value && value.value !== null && typeof value.value !== 'string') throw new Error('Kontrak ekstraksi: nominal harus string desimal.'); for (const [childKey, child] of Object.entries(value)) assertDecimalPayload(child, childKey); return; }
  if (['amount', 'total', 'balance', 'openingBalance', 'openingAmount', 'shareAmount', 'settledAmount', 'resolvedAmount', 'limitAmount', 'spentAmount', 'targetAmount', 'savedAmount', 'accountBalance', 'receivables', 'payables', 'netPosition', 'personalIncome', 'personalExpense'].includes(key) && (typeof value !== 'string' || !/^-?(0|[1-9][0-9]*)$/.test(value))) throw new Error(`Kontrak backend tidak valid: ${key} harus string desimal.`);
}
export function filterRows(data: Snapshot, filter: Filter, timezone = 'Asia/Jakarta'): ListRow[] {
  const rows: ListRow[] = [
    ...data.transactions.filter(row => !row.deleted),
    ...data.transfers.filter(row => !row.deleted).map(row => ({ ...row, kind: 'transfer', accountID: row.fromAccountID, categoryID: '', merchant: 'Transfer antar akun' })),
    ...data.splitBills.filter(row => !row.deleted).map(row => ({ ...row, kind: 'split', amount: row.total, accountID: row.payer.selfPaid?.accountID ?? '', merchant: row.title })),
  ];
  return rows.filter(row => (!filter.query || normalize(`${row.merchant ?? ''} ${row.note ?? ''}`).includes(normalize(filter.query))) && (!filter.kind || row.kind === filter.kind) && (!filter.category || row.categoryID === filter.category) && (!filter.account || row.accountID === filter.account || data.transfers.find(transfer => transfer.id === row.id)?.toAccountID === filter.account) && (!filter.from || localDay(row.occurredAt, timezone) >= filter.from) && (!filter.to || localDay(row.occurredAt, timezone) <= filter.to)).sort((left, right) => right.occurredAt.localeCompare(left.occurredAt) || right.id.localeCompare(left.id));
}
export function duplicateCandidates(data: Snapshot, item: Review, accountID: string) {
  const amount = item.amount.value, merchant = normalize(item.merchant.value ?? '');
  const date = item.date.value ? Date.parse(item.date.value) : NaN;
  return [...data.transactions.filter(row => !row.deleted).map(row => ({ id: row.id, amount: row.amount, merchant: row.merchant, occurredAt: row.occurredAt, accountID: row.accountID })), ...data.splitBills.filter(row => !row.deleted).map(row => ({ id: row.id, amount: row.total, merchant: row.title, occurredAt: row.occurredAt, accountID: row.payer.selfPaid?.accountID ?? '' }))].filter(row => row.id === item.duplicateCandidateID || (amount === row.amount && merchant && normalize(row.merchant ?? '') === merchant && (!accountID || row.accountID === accountID) && Number.isFinite(date) && Math.abs(Date.parse(row.occurredAt) - date) <= 2 * 86400000));
}
export function cashFlows(data: Snapshot, from: string, to: string, timezone = 'Asia/Jakarta') {
  const amounts = new Map(data.accounts.map(account => [account.id, { incoming: 0n, outgoing: 0n }]));
  const add = (accountID: string, amount: bigint, date: string) => {
    const day = localDay(date, timezone); if (day < from || day > to) return;
    const account = amounts.get(accountID); if (!account) return;
    if (amount > 0n) account.incoming += amount; else account.outgoing -= amount;
  };
  for (const row of data.transactions.filter(row => !row.deleted)) add(row.accountID, BigInt(row.amount) * (row.kind === 'income' ? 1n : -1n), row.occurredAt);
  for (const row of data.transfers.filter(row => !row.deleted)) { add(row.fromAccountID, -BigInt(row.amount), row.occurredAt); add(row.toAccountID, BigInt(row.amount), row.occurredAt); }
  for (const bill of data.splitBills.filter(row => !row.deleted)) {
    if (bill.payer.selfPaid) add(bill.payer.selfPaid.accountID, -BigInt(bill.total), bill.occurredAt);
    for (const event of bill.settlements.filter(row => !row.reversed)) add(event.accountID!, BigInt(event.amount) * (event.direction === 'in' ? 1n : -1n), event.occurredAt);
  }
  return data.accounts.map(account => { const row = amounts.get(account.id)!; return { accountID: account.id, incoming: row.incoming.toString(), outgoing: row.outgoing.toString(), net: (row.incoming - row.outgoing).toString() }; });
}
