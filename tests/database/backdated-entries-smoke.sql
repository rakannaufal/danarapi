\set ON_ERROR_STOP on
begin;
set request.jwt.claims = '{"sub":"15000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

do $$
declare
  source_account_id uuid;
  destination_id uuid;
  category_id uuid := '35000000-0000-4000-8000-000000000001';
  income_category_id uuid;
  transaction_id uuid;
  test_goal_id uuid := gen_random_uuid();
  bill_id uuid;
  self_member_id uuid := gen_random_uuid();
  other_member_id uuid := gen_random_uuid();
  result jsonb;
  replay jsonb;
  opening_date timestamptz := '2026-10-02T05:00:00Z';
  historical_date timestamptz := '2026-10-01T00:00:00+07:00';
begin
  result := public.api_create_account(gen_random_uuid(), 'Backdated bank', 'bank', '40000', opening_date);
  source_account_id := (result->'data'->>'id')::uuid;
  result := public.api_create_account(gen_random_uuid(), 'Backdated cash', 'cash', '0', opening_date);
  destination_id := (result->'data'->>'id')::uuid;
  result := public.api_create_category(gen_random_uuid(), 'Backdated income', 'income', 999);
  income_category_id := (result->'data'->>'id')::uuid;

  result := public.api_create_transaction('d2000000-0000-4000-8000-000000000001', 'expense', '5000', source_account_id, category_id, historical_date, null, null, 'manual');
  replay := public.api_create_transaction('d2000000-0000-4000-8000-000000000001', 'expense', '5000', source_account_id, category_id, historical_date, null, null, 'manual');
  if result <> replay then raise exception 'Backdated retry was not idempotent'; end if;
  transaction_id := (result->'data'->>'id')::uuid;
  perform public.api_update_transaction(gen_random_uuid(), transaction_id, 1, 'expense', '6000', source_account_id, category_id, '2025-09-30T00:00:00+07:00', null, null);
  if (select occurred_at from public.transactions where id = transaction_id) <> '2025-09-30T00:00:00+07:00'::timestamptz then raise exception 'Backdated update changed the chosen date'; end if;

  perform public.api_create_transaction(gen_random_uuid(), 'income', '15000', source_account_id, income_category_id, historical_date, null, null, 'manual');
  perform public.api_create_transfer(gen_random_uuid(), source_account_id, destination_id, '10000', historical_date, null);
  perform public.api_save_goal(gen_random_uuid(), test_goal_id, 'Backdated target', '100000', '0', null, 0);
  perform public.api_create_transaction(gen_random_uuid(), 'expense', '2000', source_account_id, category_id, historical_date, null, null, 'manual', test_goal_id);
  if (select progress_amount from public.savings_goal_progress where id = test_goal_id) <> '2000' then raise exception 'Backdated target progress missing'; end if;
  result := public.api_create_split_bill(gen_random_uuid(), '6000', 'Backdated split', 'self', null, source_account_id, category_id, historical_date,
    jsonb_build_array(jsonb_build_object('id', self_member_id, 'display_name', 'Saya', 'is_self', true, 'share_amount', '3000', 'sort_order', 0), jsonb_build_object('id', other_member_id, 'display_name', 'Teman', 'is_self', false, 'share_amount', '3000', 'sort_order', 1)), null);
  bill_id := (result->'data'->>'id')::uuid;
  perform public.api_record_split_settlement(gen_random_uuid(), bill_id, other_member_id, source_account_id, '1000', historical_date, null);
  if (select balance from public.account_balances where account_id = source_account_id) <> 32000 then raise exception 'Backdated entries changed the balance incorrectly'; end if;
  if (select balance from public.account_balances where account_id = destination_id) <> 10000 then raise exception 'Backdated transfer balance mismatch'; end if;
  if (select opened_at from public.accounts where id = source_account_id) <> opening_date then raise exception 'Recording history changed account opening metadata'; end if;
  if (select opening_balance from public.accounts where id = source_account_id) <> 40000 then raise exception 'Recording history changed the opening balance'; end if;

  begin
    perform public.api_create_transaction(gen_random_uuid(), 'expense', '1', '25000000-0000-4000-8000-000000000099', category_id, historical_date, null, null, 'manual');
    raise exception 'Missing account accepted';
  exception when sqlstate 'P0001' then
    if position('Akun tidak tersedia' in sqlerrm) = 0 then raise; end if;
  end;
  perform set_config('danarapi.test_account', source_account_id::text, true);
end;
$$;
reset role;
update public.accounts set archived_at = now() where id = current_setting('danarapi.test_account')::uuid;
set local role authenticated;
do $$
declare source_account_id uuid := current_setting('danarapi.test_account')::uuid;
begin
  begin
    perform public.api_create_transaction(gen_random_uuid(), 'expense', '1', source_account_id, '35000000-0000-4000-8000-000000000001', '2026-10-01Z', null, null, 'manual');
    raise exception 'Archived account accepted';
  exception when sqlstate 'P0001' then
    if position('Akun tidak tersedia' in sqlerrm) = 0 then raise; end if;
  end;
end;
$$;
rollback;
