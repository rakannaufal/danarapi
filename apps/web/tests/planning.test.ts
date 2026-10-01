import assert from 'node:assert/strict';
import test from 'node:test';
import { DemoRepository } from '../src/demo.ts';
import { assertDecimalPayload, type SavingsGoal } from '../src/domain.ts';
import { budgetPresets, goalCountdown, budgetStatus } from '../src/planning.ts';
import { allocationBreakdown } from '../../../supabase/functions/_shared/planning.ts';
import { hasRecentOAuth } from '../../../supabase/functions/_shared/oauth.ts';

const goal: SavingsGoal = { id: 'test-goal', name: 'Dana darurat', targetAmount: '5000000', savedAmount: '1000000', targetDate: '2026-10-31T00:00:00+07:00', version: 1 };
test('ten budget presets are unique; countdown follows calendar dates and completion', () => {
  assert.equal(budgetPresets.length, 10); assert.equal(new Set(budgetPresets).size, 10);
  assert.equal(goalCountdown(goal, '2026-10-01'), '30 hari lagi');
  assert.equal(goalCountdown(goal, '2026-10-31'), 'Jatuh tempo hari ini');
  assert.equal(goalCountdown(goal, '2026-11-02'), 'Lewat 2 hari');
  assert.equal(goalCountdown({ ...goal, targetDate: null }, '2026-10-01'), 'Tanpa tenggat');
  assert.equal(goalCountdown({ ...goal, savedAmount: '6000000' }, '2026-11-02'), 'Tercapai');
});
test('goal create, replay, update, conflict and delete leave financial balances unchanged', async () => {
  const repository = new DemoRepository(); const before = await repository.snapshot();
  const payload = { p_client_mutation_id: 'create-goal', p_id: goal.id, p_name: goal.name, p_target: goal.targetAmount, p_saved: '0', p_target_date: '2026-10-31', p_expected_version: 0 };
  await repository.mutate('save_goal', payload); await repository.mutate('save_goal', payload);
  let snapshot = await repository.snapshot(); assert.equal(snapshot.goals!.length, 1); assert.deepEqual(snapshot.overview, before.overview);
  assertDecimalPayload(snapshot); assert.throws(() => assertDecimalPayload({ savedAmount: 100 }), /string desimal/);
  await repository.mutate('save_goal', { ...payload, p_client_mutation_id: 'update-goal', p_saved: '2500000', p_expected_version: 1 });
  await assert.rejects(repository.mutate('save_goal', { ...payload, p_client_mutation_id: 'stale-goal', p_expected_version: 1 }), /CONFLICT_VERSION/);
  snapshot = await repository.snapshot(); assert.equal(snapshot.goals![0]!.savedAmount, '0'); assert.equal(snapshot.goals![0]!.version, 2);
  await assert.rejects(repository.mutate('save_goal', { ...payload, p_client_mutation_id: 'invalid-date', p_target_date: '2026-02-30', p_expected_version: 2 }), /Tanggal/);
  await repository.mutate('delete_goal', { p_client_mutation_id: 'delete-goal', p_id: goal.id, p_expected_version: 2 });
  snapshot = await repository.snapshot(); assert.equal(snapshot.goals!.length, 0); assert.deepEqual(snapshot.overview, before.overview);
});
test('custom category budget is month-specific and changes no account balance', async () => {
  const repository = new DemoRepository(); const before = await repository.snapshot();
  await repository.mutate('create_category', { p_client_mutation_id: 'new-category', p_name: 'Perawatan hewan', p_kind: 'expense', p_sort_order: 10 });
  const category = (await repository.snapshot()).categories.find(row => row.name === 'Perawatan hewan')!;
  await repository.mutate('upsert_budget', { category_id: category.id, month: '2026-10-01', limit_amount: '300000' });
  await repository.mutate('upsert_budget', { category_id: category.id, month: '2026-11-01', limit_amount: '500000' });
  const after = await repository.snapshot(); assert.equal(after.budgets.filter(row => row.categoryID === category.id).length, 2); assert.deepEqual(after.overview, before.overview);
});
test('budget thresholds distinguish 70 percent, exact limit and over limit', () => {
  for (const [spent, expected] of [['69', 'safe'], ['70', 'warning'], ['100', 'warning'], ['101', 'over']]) assert.equal(budgetStatus(spent!, '100'), expected);
  assert.equal(budgetStatus('0', '0'), 'safe');
  assert.equal(budgetStatus('1', '0'), 'over');
});
test('goal contributions affect selected account once, follow edits, delete, restore and metadata deletion', async () => {
  const repository = new DemoRepository();
  const before = await repository.snapshot();
  await repository.mutate('save_goal', { p_client_mutation_id: 'goal-new', p_id: goal.id, p_name: goal.name, p_target: goal.targetAmount, p_saved: '0', p_expected_version: 0 });
  await assert.rejects(repository.mutate('save_goal', { p_client_mutation_id: 'goal-bypass', p_id: 'bypass', p_name: 'Bypass', p_target: '100000', p_saved: '1', p_expected_version: 0 }), /transaksi/);
  const expense = { p_client_mutation_id: 'goal-expense', p_type: 'expense', p_amount: '70000', p_account_id: 'cash', p_category_id: 'food', p_goal_id: goal.id, p_occurred_at: '2026-10-01T05:00:00Z' };
  await repository.mutate('create_transaction', expense); await repository.mutate('create_transaction', expense);
  let snapshot = await repository.snapshot(); const transaction = snapshot.transactions.find(row => row.goalID === goal.id)!;
  assert.equal(transaction.categoryID, 'feature-goal');
  assert.equal(snapshot.goals![0]!.savedAmount, '70000');
  assert.equal(BigInt(snapshot.overview.accountBalance), BigInt(before.overview.accountBalance) - 70000n);
  assert.equal((await repository.snapshot()).goals![0]!.savedAmount, '70000');
  await repository.mutate('update_transaction', { ...expense, p_client_mutation_id: 'goal-edit', p_transaction_id: transaction.id, p_expected_version: 1, p_amount: '100000', p_account_id: 'bank' });
  snapshot = await repository.snapshot();
  assert.equal(snapshot.goals![0]!.savedAmount, '100000');
  assert.equal(snapshot.accounts.find(row => row.id === 'cash')!.balance, before.accounts.find(row => row.id === 'cash')!.balance);
  assert.equal(BigInt(snapshot.accounts.find(row => row.id === 'bank')!.balance), BigInt(before.accounts.find(row => row.id === 'bank')!.balance) - 100000n);
  await repository.mutate('delete_transaction', { p_client_mutation_id: 'goal-delete-tx', p_transaction_id: transaction.id, p_expected_version: 2 });
  snapshot = await repository.snapshot(); assert.equal(snapshot.goals![0]!.savedAmount, '0'); assert.equal(snapshot.overview.accountBalance, before.overview.accountBalance);
  await repository.mutate('restore_transaction', { p_client_mutation_id: 'goal-restore', p_transaction_id: transaction.id, p_expected_version: 3 });
  snapshot = await repository.snapshot(); assert.equal(snapshot.goals![0]!.savedAmount, '100000');
  await repository.mutate('delete_goal', { p_client_mutation_id: 'goal-delete', p_id: goal.id, p_expected_version: 1 });
  const deleted = await repository.snapshot(); assert.equal(deleted.transactions.find(row => row.id === transaction.id)!.goalID, null); assert.equal(deleted.overview.accountBalance, snapshot.overview.accountBalance);
});
test('QRIS review is always an expense in its own category; replay and invalid edits cannot double charge', async () => {
  const repository = new DemoRepository(); const before = await repository.snapshot();
  const payload = { p_client_mutation_id: 'qris-confirm', id: 'review-qris', transaction: { kind: 'income', amount: '75000', accountID: 'cash', categoryID: 'food', occurredAt: '2026-10-01T05:00:00Z' } };
  await repository.mutate('confirm_review_item', payload); await repository.mutate('confirm_review_item', payload);
  const snapshot = await repository.snapshot(), transaction = snapshot.transactions.find(row => row.source === 'qris')!;
  assert.equal(transaction.kind, 'expense'); assert.equal(transaction.categoryID, 'feature-qris');
  assert.equal(BigInt(snapshot.overview.accountBalance), BigInt(before.overview.accountBalance) - 75000n);
  await assert.rejects(repository.mutate('confirm_review_item', { ...payload, p_client_mutation_id: 'qris-repeat' }), /diproses/);
  await assert.rejects(repository.mutate('update_transaction', { p_client_mutation_id: 'qris-income', p_transaction_id: transaction.id, p_expected_version: 1, p_type: 'income', p_amount: '75000', p_account_id: 'cash', p_category_id: 'salary', p_occurred_at: transaction.occurredAt }), /pengeluaran/);
  assert.equal((await repository.snapshot()).overview.accountBalance, snapshot.overview.accountBalance);
});
test('allocation disjointly reconciles targets, budget categories and QRIS', () => {
  const rows = allocationBreakdown([{ categoryID: 'target', amount: '100000' }, { categoryID: 'food', amount: '70000' }, { categoryID: 'qris', amount: '75000' }], [{ categoryID: 'target', goalID: 'laptop', amount: '40000' }, { categoryID: 'target', goalID: 'emergency', amount: '60000' }], [{ id: 'laptop', name: 'Laptop' }, { id: 'emergency', name: 'Dana darurat' }], [{ id: 'food', name: 'Makan' }, { id: 'qris', name: 'QRIS' }], new Set(['target', 'food']));
  assert.equal(rows.reduce((sum, row) => sum + BigInt(row.amount), 0n), 245000n);
  assert.equal(rows.length, 4); assert.ok(rows.some(row => row.name === 'Anggaran · Makan'));
  assert.throws(() => allocationBreakdown([{ categoryID: 'target', amount: '1' }], [{ categoryID: 'target', goalID: 'x', amount: '2' }], [], [], new Set()), /sesuai/);
  assert.deepEqual(allocationBreakdown([], [], [], [], new Set()), []);
});
test('OAuth deletion requires recent validated claims from the same owner', () => {
  const claims = { sub: 'owner', amr: [{ method: 'oauth', timestamp: 1000 }] };
  assert.equal(hasRecentOAuth(claims, 'owner', 1200), true);
  assert.equal(hasRecentOAuth(claims, 'other', 1200), false);
  assert.equal(hasRecentOAuth(claims, 'owner', 1301), false);
  assert.equal(hasRecentOAuth(claims, 'owner', 960), false);
  assert.equal(hasRecentOAuth({ sub: 'owner' }, 'owner', 1200), false);
  assert.equal(hasRecentOAuth({ sub: 'owner', amr: [{ method: 'password', timestamp: 1100 }] }, 'owner', 1200), false);
});
