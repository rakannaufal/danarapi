begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

insert into auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '12000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ledger@danarapi.invalid', '', now(), '{}', '{}', now(), now());

insert into public.accounts(id, user_id, name, kind, opening_balance, opened_at)
values ('22000000-0000-4000-8000-000000000001', '12000000-0000-4000-8000-000000000001', 'Tunai Test', 'cash', 200000, '2026-01-01T00:00:00Z');
insert into public.categories(id, user_id, name, kind)
values ('32000000-0000-4000-8000-000000000001', '12000000-0000-4000-8000-000000000001', 'Makan Test', 'expense');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select is(
  public.api_calculate_split('100000', 'equal', '[{"id":"self","included":true},{"id":"ani","included":true},{"id":"budi","included":true}]'::jsonb)->'data'->'participants',
  '[{"id":"self","included":true,"share_amount":"33334"},{"id":"ani","included":true,"share_amount":"33333"},{"id":"budi","included":true,"share_amount":"33333"}]'::jsonb,
  'server equal split allocates remainder in visible order'
);
select is(
  public.api_calculate_split('100001', 'percentage', '[{"id":"self","basis_points":3334},{"id":"ani","basis_points":3333},{"id":"budi","basis_points":3333}]'::jsonb)->'data'->'participants',
  '[{"id":"self","basis_points":3334,"share_amount":"33341"},{"id":"ani","basis_points":3333,"share_amount":"33330"},{"id":"budi","basis_points":3333,"share_amount":"33330"}]'::jsonb,
  'server percentage split uses largest remainder'
);

select is(
  public.api_create_transaction('50000000-0000-4000-8000-000000000001', 'expense', '25000', '22000000-0000-4000-8000-000000000001', '32000000-0000-4000-8000-000000000001', '2026-09-01T00:00:00Z', 'Warung Test', null, 'manual'),
  public.api_create_transaction('50000000-0000-4000-8000-000000000001', 'expense', '25000', '22000000-0000-4000-8000-000000000001', '32000000-0000-4000-8000-000000000001', '2026-09-01T00:00:00Z', 'Warung Test', null, 'manual'),
  'same mutation returns identical response'
);
select is((select count(*)::integer from public.transactions), 1, 'retry creates one transaction');
select is((select balance::text from public.account_balances where account_id = '22000000-0000-4000-8000-000000000001'), '175000', 'transaction updates account projection once');
select throws_ok(
  $$select public.api_create_transaction('50000000-0000-4000-8000-000000000001', 'expense', '26000', '22000000-0000-4000-8000-000000000001', '32000000-0000-4000-8000-000000000001', '2026-09-01T00:00:00Z', null, null, 'manual')$$,
  'P0001', null, 'changed retry is rejected'
);
select lives_ok($sql$
  select public.api_delete_transaction(
    '50000000-0000-4000-8000-000000000003',
    (select id from public.transactions limit 1), 1
  )
$sql$, 'transaction can be soft deleted');
select is((select balance::text from public.account_balances where account_id = '22000000-0000-4000-8000-000000000001'), '200000', 'delete reverses ledger effect');
select lives_ok($sql$
  select public.api_restore_transaction(
    '50000000-0000-4000-8000-000000000004',
    (select id from public.transactions limit 1), 2
  )
$sql$, 'undo restores transaction');
select is((select balance::text from public.account_balances where account_id = '22000000-0000-4000-8000-000000000001'), '175000', 'undo restores one ledger effect');

select lives_ok($sql$
  select public.api_create_split_bill(
    '50000000-0000-4000-8000-000000000010', '120000', 'Makan bersama', 'self', null,
    '22000000-0000-4000-8000-000000000001', '32000000-0000-4000-8000-000000000001', '2026-09-02T00:00:00Z',
    '[{"id":"62000000-0000-4000-8000-000000000001","display_name":"Saya","is_self":true,"share_amount":"40000","sort_order":0},{"id":"62000000-0000-4000-8000-000000000002","display_name":"Ani","is_self":false,"share_amount":"40000","sort_order":1},{"id":"62000000-0000-4000-8000-000000000003","display_name":"Budi","is_self":false,"share_amount":"40000","sort_order":2}]'::jsonb,
    null
  )
$sql$, 'self-paid split bill is created');
select is((select balance::text from public.account_balances where account_id = '22000000-0000-4000-8000-000000000001'), '55000', 'bill debits full total');
select is((select receivables::text from public.financial_overview), '80000', 'bill records other shares as receivable');
select is((select payables::text from public.financial_overview), '0', 'self-paid bill has no payable');
select is((select net_position::text from public.financial_overview), '135000', 'net position preserves only personal expense and prior expense');

select lives_ok($sql$
  select public.api_record_split_settlement(
    '50000000-0000-4000-8000-000000000011',
    (select id from public.split_bills where title = 'Makan bersama'),
    '62000000-0000-4000-8000-000000000002', '22000000-0000-4000-8000-000000000001',
    '15000', '2026-09-03T00:00:00Z', null
  )
$sql$, 'partial settlement succeeds');
select is((select balance::text from public.account_balances where account_id = '22000000-0000-4000-8000-000000000001'), '70000', 'settlement increases cash');
select is((select receivables::text from public.financial_overview), '65000', 'settlement reduces receivable');
select is((select net_position::text from public.financial_overview), '135000', 'settlement leaves net position unchanged');
select throws_ok($sql$
  select public.api_record_split_settlement(
    '50000000-0000-4000-8000-000000000012',
    (select id from public.split_bills where title = 'Makan bersama'),
    '62000000-0000-4000-8000-000000000002', '22000000-0000-4000-8000-000000000001',
    '25001', '2026-09-03T01:00:00Z', null
  )
$sql$, 'P0001', null, 'overpay by one rupiah is rejected');

select lives_ok($sql$
  select public.api_record_split_resolution(
    '50000000-0000-4000-8000-000000000013',
    (select id from public.split_bills where title = 'Makan bersama'),
    '62000000-0000-4000-8000-000000000003', '10000', '2026-09-04T00:00:00Z', 'Tidak ditagih lagi'
  )
$sql$, 'receivable writeoff succeeds');
select is((select receivables::text from public.financial_overview), '55000', 'writeoff reduces receivable');
select is((select coalesce(sum(personal_expense_amount), 0)::text from public.ledger_entries where reversed_at is null), '75000', 'writeoff adds non-cash personal expense');
select is((select balance::text from public.account_balances where account_id = '22000000-0000-4000-8000-000000000001'), '70000', 'writeoff does not change cash');
select is((select status from public.split_bill_summaries where title = 'Makan bersama'), 'partially_settled', 'bill status is derived');

select * from finish();
rollback;
