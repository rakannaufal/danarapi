import assert from 'node:assert/strict';
import test from 'node:test';
import { DemoRepository, demoSeed } from '../src/demo.ts';
import { assertDecimalPayload, billStatus, cashFlows, localDay, reportFor } from '../src/domain.ts';

test('showcase fills every finance page, uses elapsed days across three local months', () => {
  for (const instant of ['2026-10-05T01:00:00Z', '2027-01-01T00:00:00Z', '2028-02-29T16:59:00Z', '2026-09-30T17:01:00Z']) {
    const data = demoSeed(new Date(instant)), today = localDay(instant), month = today.slice(0, 7);
    assert.equal(data.accounts.length, 3);
    assert.equal(data.goals?.length, 3);
    assert.equal(data.reviewItems.length, 3);
    assert.equal(data.merchantRules.length, 6);
    assert.equal(new Set(data.transactions.map(row => localDay(row.occurredAt).slice(0, 7))).size, 3);
    assert.ok(data.transactions.every(row => row.occurredAt <= instant));
    assert.ok([...data.transfers, ...data.splitBills, ...data.splitBills.flatMap(row => row.settlements)].every(row => row.occurredAt <= instant));
    const report = reportFor(data, `${month}-01`, today);
    assert.ok(BigInt(report.personalIncome) > 0n);
    assert.ok(BigInt(report.personalExpense) > 0n);
    assert.equal(data.budgets.filter(row => row.month === month).length, 7);
    assert.deepEqual(new Set(data.splitBills.map(billStatus)), new Set(['Belum lunas', 'Lunas sebagian', 'Lunas']));
    assert.ok(data.reviewItems.every(row => row.status === 'pending'));
    assert.equal(data.reviewItems.find(row => row.id === 'review-ambiguous')?.amount.value, null);
    assertDecimalPayload(data);
  }
});

test('showcase cash, goals, obligations, category budgets reconcile to the ledger', () => {
  const data = demoSeed(new Date('2026-10-05T01:00:00Z'));
  for (const row of data.transactions) {
    assert.ok(data.accounts.some(account => account.id === row.accountID));
    assert.ok(data.categories.some(category => category.id === row.categoryID && category.kind === row.kind));
    if (row.goalID) assert.ok(data.goals?.some(goal => goal.id === row.goalID));
  }
  const opening = data.accounts.reduce((sum, row) => sum + BigInt(row.openingBalance), 0n);
  const cash = cashFlows(data, '0001-01-01', '9999-12-31');
  for (const account of data.accounts) {
    assert.equal(BigInt(account.balance), BigInt(account.openingBalance) + BigInt(cash.find(row => row.accountID === account.id)!.net));
    assert.ok(BigInt(account.balance) > 0n);
  }
  assert.equal(BigInt(data.overview.netPosition), opening + BigInt(data.overview.personalIncome) - BigInt(data.overview.personalExpense));
  for (const goal of data.goals ?? []) assert.equal(BigInt(goal.savedAmount), data.transactions.filter(row => row.goalID === goal.id).reduce((sum, row) => sum + BigInt(row.amount), 0n));
  for (const budget of data.budgets) assert.equal(budget.spentAmount, reportFor(data, `${budget.month}-01`, `${budget.month}-31`).categories.find(row => row.categoryID === budget.categoryID)?.amount ?? '0');
  assert.equal(data.overview.receivables, '110000');
  assert.equal(data.overview.payables, '60000');
  const current = reportFor(data, '2026-10-01', '2026-10-05');
  assert.equal(current.personalIncome, '8500000');
  assert.equal(current.personalExpense, '5108000');
});

test('showcase repository mutations affect real values, reset restores populated data', async () => {
  const repository = new DemoRepository(new Date());
  const initial = await repository.snapshot();
  await repository.mutate('create_transaction', { p_type: 'expense', p_amount: '25000', p_account_id: 'cash', p_category_id: 'food', p_occurred_at: new Date().toISOString(), p_merchant: 'Makan sore' });
  const changed = await repository.snapshot();
  assert.equal(BigInt(changed.overview.accountBalance), BigInt(initial.overview.accountBalance) - 25000n);
  assert.equal(BigInt(changed.overview.personalExpense), BigInt(initial.overview.personalExpense) + 25000n);
  repository.reset();
  assert.deepEqual(await repository.snapshot(), initial);
});
