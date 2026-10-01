import seed from '../../../tests/fixtures/demo-seed-v1.json' with { type: 'json' };
import { derive, emptySnapshot, id, normalize, remaining, obligations, validateDate } from './domain.ts';
import { parseMoney as parseMoneyPlaceholder } from './contracts.ts';
import { splitItems } from './item-split.ts';
import type { Snapshot, Member, Review } from './domain.ts';

export function demoSeed(): Snapshot {
  const data = emptySnapshot();
  data.accounts = seed.accounts.map(row => ({ id: row.id, name: row.name, kind: row.kind, openingBalance: row.opening_balance, balance: row.opening_balance, openedAt: seed.period.from, archived: false, version: 1 }));
  data.categories = seed.categories.map((row, index) => ({ id: row.id, name: row.name, kind: row.kind as 'income' | 'expense', archived: false, sortOrder: index, version: 1 }));
  for (const [systemKey, name] of [['goal', 'Target'], ['qris', 'QRIS']]) data.categories.push({ id: `feature-${systemKey}`, name, systemKey, kind: 'expense', archived: false, sortOrder: data.categories.length, version: 1 });
  data.transactions = seed.transactions.map(row => ({ id: row.id, kind: row.type as 'income' | 'expense', amount: row.amount, accountID: row.account_id, categoryID: row.category_id, occurredAt: row.occurred_at, merchant: row.merchant, source: 'demo', deleted: false, version: 1 }));
  data.budgets = seed.budgets.map((row, index) => ({ id: `budget-${index}`, categoryID: row.category_id, month: row.month, limitAmount: row.limit_amount, spentAmount: '0' }));
  data.splitBills = seed.split_bills.map((row, index) => {
    const members = ['Saya', 'Ani', 'Budi'].map((name, order) => ({ id: `bill${index + 1}-${name.toLowerCase()}`, displayName: name, isSelf: order === 0, shareAmount: row.self_share, settledAmount: '0', resolvedAmount: '0', sortOrder: order }));
    return { id: row.id, title: index === 0 ? 'Makan bersama' : 'Tiket konser', total: row.total, categoryID: index === 0 ? 'food' : 'household', payer: row.payer === 'self' ? { selfPaid: { accountID: 'cash' } } : { other: { memberID: members[1].id } }, occurredAt: index === 0 ? '2026-09-25T05:00:00Z' : '2026-09-20T05:00:00Z', members, settlements: row.settled_amount !== '0' ? [{ id: 'bill1-settlement', memberID: members[1].id, direction: 'in' as const, accountID: 'cash', amount: row.settled_amount, occurredAt: '2026-09-27T05:00:00Z', reversed: false, version: 1 }] : [], resolutions: [], deleted: false, version: 1 };
  });
  const field = (value: string | null, sourceType: string, evidenceSpan: string | null = value) => ({ value, confidence: value ? 'medium' as const : 'low' as const, evidenceSpan, sourceType });
  data.reviewItems = [{ id: 'review-qris', source: 'qris', status: 'pending', amount: field('75000', 'qris'), merchant: field('TOKO DEMO', 'qris'), date: field(null, 'qris'), createdAt: '2026-09-30T05:00:00Z' }, { id: 'review-text', source: 'pasted_text', status: 'pending', amount: field(null, 'pasted_text', 'Subtotal 50.000; Total 58.000'), merchant: field('Kedai Sore', 'pasted_text'), date: field('2026-09-29', 'pasted_text'), createdAt: '2026-09-30T04:00:00Z' }];
  data.merchantRules = [{ id: 'demo-rule-warung', matchType: 'contains', normalizedPattern: 'warung', categoryID: 'food', priority: 10, version: 1 }];
  return derive(data);
}

type Payload = Record<string, any>;
export class DemoRepository {
  data = demoSeed();
  timezone = 'Asia/Jakarta';
  private replays = new Map<string, string>();
  async snapshot() { return structuredClone(derive(this.data, this.timezone)); }
  reset() { this.data = demoSeed(); this.replays.clear(); }
  async mutate(operation: string, payload: Payload) {
    const key = payload.p_client_mutation_id as string | undefined;
    const canonical = JSON.stringify({ operation, payload });
    if (key && this.replays.has(key)) { if (this.replays.get(key) !== canonical) throw new Error('DUPLICATE_MUTATION'); return; }
    const previous = structuredClone(this.data);
    try { this.apply(operation, payload); derive(this.data); if (key) this.replays.set(key, canonical); }
    catch (error) { this.data = previous; throw error; }
  }
  private apply(operation: string, payload: Payload) {
    const data = this.data;
    if (operation === 'save_goal') {
      parseMoneyPlaceholder(payload.p_target); parseMoneyPlaceholder(payload.p_saved, true);
      if (!payload.p_id || !payload.p_name?.trim() || payload.p_name.trim().length > 100) throw new Error('Nama target wajib diisi, maksimal 100 karakter.');
      if (payload.p_target_date && (!/^\d{4}-\d{2}-\d{2}$/.test(payload.p_target_date) || new Date(`${payload.p_target_date}T00:00:00Z`).toISOString().slice(0, 10) !== payload.p_target_date)) throw new Error('Tanggal target tidak valid.');
      const goals = data.goals ??= [];
      const existing = goals.find(goal => goal.id === payload.p_id);
      if (!existing && payload.p_saved !== '0') throw new Error('Progres target dicatat melalui transaksi.');
      if (existing ? existing.version !== payload.p_expected_version : payload.p_expected_version !== 0) throw new Error('CONFLICT_VERSION: Muat ulang target.');
      const openingAmount = existing?.openingAmount ?? existing?.savedAmount ?? payload.p_saved;
      const fields = { name: payload.p_name.trim(), targetAmount: payload.p_target, savedAmount: existing?.savedAmount ?? openingAmount, openingAmount, targetDate: payload.p_target_date ?? null };
      if (existing) Object.assign(existing, fields, { version: existing.version + 1 });
      else goals.push({ id: payload.p_id, ...fields, version: 1 });
      return;
    }
    if (operation === 'delete_goal') {
      const goal = data.goals?.find(row => row.id === payload.p_id);
      if (!goal || goal.version !== payload.p_expected_version) throw new Error('CONFLICT_VERSION: Muat ulang target.');
      data.goals = data.goals!.filter(row => row.id !== goal.id);
      for (const transaction of data.transactions.filter(row => row.goalID === goal.id)) transaction.goalID = null;
      return;
    }
    if (operation === 'save_item_split_bill') {
      const result = splitItems(payload.p_item_split, payload.p_members.map((member: Payload) => member.id));
      if (result.total !== payload.p_total || payload.p_members.some((member: Payload) => result.shares[member.id] !== member.share_amount)) throw new Error('Porsi menu tidak sesuai hasil perhitungan.');
      const action = payload.p_split_bill_id ? 'update_split_bill' : payload.p_review_item_id ? 'create_split_bill_from_review' : payload.p_transaction_id ? 'convert_transaction_to_split_bill' : 'create_split_bill';
      this.apply(action, payload);
      const bill = payload.p_split_bill_id ? data.splitBills.find(row => row.id === payload.p_split_bill_id)! : data.splitBills.at(-1)!;
      bill.itemSplit = structuredClone(payload.p_item_split);
      return;
    }
    const account = (value: string) => { const row = data.accounts.find(item => item.id === value && !item.archived); if (!row) throw new Error('Akun aktif tidak ditemukan.'); return row; };
    const category = (value: string, kind = 'expense') => { const row = data.categories.find(item => item.id === value && !item.archived && item.kind === kind); if (!row) throw new Error('Kategori tidak sesuai jenis transaksi.'); return row; };
    const versioned = <T extends { id: string; version: number }>(rows: T[], value: string, version?: number) => { const row = rows.find(item => item.id === value); if (!row) throw new Error('Data tidak ditemukan.'); if (version !== undefined && row.version !== version) throw new Error('VERSION_CONFLICT: Muat ulang data sebelum mengubah.'); return row; };
    const unique = (rows: { id: string; name: string; archived: boolean }[], name: string, ownID?: string) => { if (!name?.trim() || rows.some(row => !row.archived && row.id !== ownID && normalize(row.name) === normalize(name))) throw new Error('Nama kosong atau sudah dipakai.'); };
    if (operation === 'create_account') { unique(data.accounts, payload.p_name); parseMoneyPlaceholder(payload.p_opening_balance, true); data.accounts.push({ id: id(), name: payload.p_name.trim(), kind: payload.p_kind, openingBalance: payload.p_opening_balance, balance: payload.p_opening_balance, openedAt: validateDate(payload.p_opened_at), archived: false, version: 1 }); return; }
    if (operation === 'update_account') { const row = versioned(data.accounts, payload.id, payload.version); unique(data.accounts, payload.name, row.id); parseMoneyPlaceholder(payload.openingBalance, true); Object.assign(row, payload, { version: row.version + 1 }); return; }
    if (operation === 'archive_account') { if (data.accounts.filter(row => !row.archived).length <= 1) throw new Error('Akun aktif terakhir tidak dapat diarsip.'); versioned(data.accounts, payload.id, payload.expected_version).archived = true; return; }
    if (operation === 'create_category') { unique(data.categories.filter(row => row.kind === payload.p_kind), payload.p_name); data.categories.push({ id: id(), name: payload.p_name.trim(), kind: payload.p_kind, archived: false, sortOrder: payload.p_sort_order, version: 1 }); return; }
    if (operation === 'update_category') { const row = versioned(data.categories, payload.id, payload.version); unique(data.categories.filter(item => item.kind === row.kind), payload.name, row.id); row.name = payload.name; row.sortOrder = payload.sortOrder; row.version++; return; }
    if (operation === 'archive_category') { versioned(data.categories, payload.id, payload.expected_version).archived = true; return; }
    if (['create_transaction', 'update_transaction', 'confirm_review_item'].includes(operation)) {
      const review = operation === 'confirm_review_item' ? data.reviewItems.find(item => item.id === payload.id && item.status === 'pending') : undefined;
      if (operation === 'confirm_review_item' && !review) throw new Error('Review sudah diproses.');
      const input = operation === 'confirm_review_item' ? { ...payload.transaction, source: review!.source } : { kind: payload.p_type, amount: payload.p_amount, accountID: payload.p_account_id, categoryID: payload.p_category_id, goalID: payload.p_goal_id ?? null, occurredAt: payload.p_occurred_at, merchant: payload.p_merchant, note: payload.p_note, source: operation === 'update_transaction' ? data.transactions.find(row => row.id === payload.p_transaction_id)?.source ?? 'manual' : payload.p_source ?? 'manual' };
      if (input.source === 'qris') {
        if (!review && (input.kind !== 'expense' || input.goalID)) throw new Error('QRIS dicatat sebagai pengeluaran.');
        input.kind = 'expense'; input.goalID = null; input.categoryID = data.categories.find(row => row.systemKey === 'qris')!.id;
      }
      if (input.goalID) {
        if (input.kind !== 'expense' || !data.goals?.some(goal => goal.id === input.goalID)) throw new Error('Pilih target aktif untuk pengeluaran ini.');
        input.categoryID = data.categories.find(row => row.systemKey === 'goal')!.id;
      } else if (data.categories.find(row => row.id === input.categoryID)?.systemKey === 'goal') throw new Error('Pilih target untuk kategori Target.');
      parseMoneyPlaceholder(input.amount); account(input.accountID); category(input.categoryID, input.kind); validateDate(input.occurredAt);
      if (operation === 'update_transaction') { const row = versioned(data.transactions, payload.p_transaction_id, payload.p_expected_version); if (row.deleted) throw new Error('Transaksi dihapus.'); Object.assign(row, input, { version: row.version + 1 }); } else data.transactions.push({ ...input, id: id(), deleted: false, version: 1 });
      if (review) review.status = 'saved'; return;
    }
    if (operation === 'delete_transaction' || operation === 'restore_transaction') { const row = versioned(data.transactions, payload.p_transaction_id, payload.p_expected_version); row.deleted = operation === 'delete_transaction'; row.version++; return; }
    if (operation === 'create_transfer' || operation === 'update_transfer') {
      account(payload.p_from_account_id); account(payload.p_to_account_id); parseMoneyPlaceholder(payload.p_amount);
      if (payload.p_from_account_id === payload.p_to_account_id) throw new Error('Akun asal dan tujuan harus berbeda.');
      const input = { fromAccountID: payload.p_from_account_id, toAccountID: payload.p_to_account_id, amount: payload.p_amount, occurredAt: validateDate(payload.p_occurred_at), note: payload.p_note };
      if (operation === 'update_transfer') { const row = versioned(data.transfers, payload.p_transfer_id, payload.p_expected_version); Object.assign(row, input, { version: row.version + 1 }); } else data.transfers.push({ ...input, id: id(), deleted: false, version: 1 }); return;
    }
    if (operation === 'delete_transfer' || operation === 'restore_transfer') { const row = versioned(data.transfers, payload.p_transfer_id, payload.p_expected_version); row.deleted = operation === 'delete_transfer'; row.version++; return; }
    if (['create_split_bill', 'update_split_bill', 'create_split_bill_from_review', 'convert_transaction_to_split_bill'].includes(operation)) {
      parseMoneyPlaceholder(payload.p_total); category(payload.p_category_id);
      const members: Member[] = payload.p_members.map((row: Payload) => ({ id: row.id, displayName: row.display_name.trim(), isSelf: row.is_self, shareAmount: row.share_amount, settledAmount: '0', resolvedAmount: '0', sortOrder: row.sort_order }));
      if (members.length < 2 || members.length > 20 || members.filter(row => row.isSelf).length !== 1 || new Set(members.map(row => normalize(row.displayName))).size !== members.length || members.some(row => !row.displayName) || members.reduce((sum, row) => sum + parseMoneyPlaceholder(row.shareAmount, true), 0n) !== BigInt(payload.p_total)) throw new Error('Peserta atau jumlah porsi tidak valid.');
      if (payload.p_payer_kind === 'self') account(payload.p_payer_account_id); else if (!members.some(row => row.id === payload.p_payer_member_id && !row.isSelf)) throw new Error('Pembayar tidak valid.');
      if (!payload.p_title?.trim()) throw new Error('Isi nama tagihan.');
      const input = { title: payload.p_title, total: payload.p_total, categoryID: payload.p_category_id, payer: payload.p_payer_kind === 'self' ? { selfPaid: { accountID: payload.p_payer_account_id } } : { other: { memberID: payload.p_payer_member_id } }, occurredAt: validateDate(payload.p_occurred_at), note: payload.p_note, members };
      if (operation === 'update_split_bill') { const row = versioned(data.splitBills, payload.p_split_bill_id, payload.p_expected_version); if ([...row.settlements, ...row.resolutions].some(event => !event.reversed)) throw new Error('Bill dengan kejadian aktif tidak dapat diubah.'); Object.assign(row, input, { version: row.version + 1 }); }
      else {
        if (operation === 'convert_transaction_to_split_bill') { const row = versioned(data.transactions, payload.p_transaction_id, payload.p_expected_version); if (row.deleted) throw new Error('Transaksi dihapus.'); row.deleted = true; row.version++; }
        if (operation === 'create_split_bill_from_review') { const review = data.reviewItems.find(row => row.id === payload.p_review_item_id && row.status === 'pending'); if (!review) throw new Error('Review sudah diproses.'); review.status = 'saved'; }
        data.splitBills.push({ ...input, id: id(), settlements: [], resolutions: [], deleted: false, version: 1 });
      } return;
    }
    if (operation === 'delete_split_bill' || operation === 'restore_split_bill') { const bill = versioned(data.splitBills, payload.p_split_bill_id, payload.p_expected_version); if ([...bill.settlements, ...bill.resolutions].some(event => !event.reversed)) throw new Error('Batalkan pelunasan/penghapusan kewajiban terlebih dahulu.'); bill.deleted = operation === 'delete_split_bill'; bill.version++; return; }
    if (operation === 'record_split_settlement' || operation === 'record_split_resolution') {
      const bill = data.splitBills.find(row => row.id === payload.p_split_bill_id && !row.deleted); if (!bill) throw new Error('Bill tidak ditemukan.');
      const member = obligations(bill).find(row => row.id === payload.p_member_id); if (!member) throw new Error('Peserta tanpa kewajiban.');
      const amount = parseMoneyPlaceholder(payload.p_amount); if (amount > remaining(bill, member)) throw new Error('Jumlah melebihi sisa kewajiban.');
      const event = { id: id(), memberID: member.id, amount: payload.p_amount, occurredAt: validateDate(payload.p_occurred_at), reversed: false, version: 1 };
      if (operation === 'record_split_settlement') { account(payload.p_account_id); bill.settlements.push({ ...event, accountID: payload.p_account_id, direction: bill.payer.selfPaid ? 'in' : 'out', note: payload.p_note }); }
      else { if (!payload.p_reason?.trim()) throw new Error('Alasan wajib diisi.'); bill.resolutions.push({ ...event, kind: bill.payer.selfPaid ? 'receivable_writeoff' : 'payable_forgiveness', reason: payload.p_reason }); } bill.version++; return;
    }
    if (operation === 'reverse_split_settlement' || operation === 'reverse_split_resolution') {
      if (!payload.p_reason?.trim()) throw new Error('Alasan pembatalan wajib diisi.');
      const resolution = operation === 'reverse_split_resolution';
      const bill = data.splitBills.find(row => (resolution ? row.resolutions : row.settlements).some(event => event.id === (payload.p_resolution_id ?? payload.p_settlement_id)));
      if (!bill) throw new Error('Kejadian tidak ditemukan.');
      const event = versioned(resolution ? bill.resolutions : bill.settlements, payload.p_resolution_id ?? payload.p_settlement_id, payload.p_expected_version); if (event.reversed) throw new Error('Kejadian sudah dibatalkan.'); event.reversed = true; event.reason = payload.p_reason; event.version++; bill.version++; return;
    }
    if (operation === 'add_review_item') { if (!data.reviewItems.some(row => row.fingerprint && row.fingerprint === payload.fingerprint)) data.reviewItems.push(payload as Review); return; }
    if (operation === 'update_review_item') { const row = data.reviewItems.find(item => item.id === payload.id && item.status === 'pending'); if (!row) throw new Error('Review tidak lagi menunggu pemeriksaan.'); Object.assign(row, { amount: payload.amount, merchant: payload.merchant, date: payload.date, rawReference: payload.rawReference, receipt: payload.receipt }); return; }
    if (['reject_review_item', 'restore_review_item', 'merge_review_item', 'clear_review_duplicate'].includes(operation)) { const row = data.reviewItems.find(item => item.id === payload.id); if (!row) throw new Error('Review tidak ditemukan.'); if (operation === 'merge_review_item' && !data.transactions.some(item => item.id === payload.transaction_id && !item.deleted) && !data.splitBills.some(item => item.id === payload.bill_id && !item.deleted)) throw new Error('Transaksi tujuan tidak ditemukan.'); if (operation === 'clear_review_duplicate') row.duplicateCandidateID = null; else row.status = operation === 'reject_review_item' ? 'rejected' : operation === 'restore_review_item' ? 'pending' : 'merged'; return; }
    if (operation === 'upsert_budget') { category(payload.category_id); parseMoneyPlaceholder(payload.limit_amount); const row = data.budgets.find(item => item.categoryID === payload.category_id && item.month.slice(0, 7) === payload.month.slice(0, 7)); if (row) row.limitAmount = payload.limit_amount; else data.budgets.push({ id: id(), categoryID: payload.category_id, month: payload.month, limitAmount: payload.limit_amount, spentAmount: '0' }); return; }
    if (operation === 'save_merchant_rule') { category(payload.categoryID); if (!normalize(payload.normalizedPattern)) throw new Error('Pola merchant kosong.'); const row = data.merchantRules.find(item => item.id === payload.id); if (row) Object.assign(row, payload, { version: row.version + 1 }); else data.merchantRules.push({ ...payload, version: 1 } as any); return; }
    if (operation === 'delete_merchant_rule') { data.merchantRules = data.merchantRules.filter(row => row.id !== payload.id); return; }
    throw new Error(`Operasi Demo tidak didukung: ${operation}`);
  }
}
