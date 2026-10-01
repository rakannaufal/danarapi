\set ON_ERROR_STOP on

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
  ('00000000-0000-0000-0000-000000000000','15000000-0000-4000-8000-000000000001','authenticated','authenticated','smoke-one@danarapi.invalid','',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','15000000-0000-4000-8000-000000000002','authenticated','authenticated','smoke-two@danarapi.invalid','',now(),'{}','{}',now(),now());
insert into public.accounts(id,user_id,name,kind,opening_balance,opened_at)
values ('25000000-0000-4000-8000-000000000001','15000000-0000-4000-8000-000000000001','Smoke Cash','cash',200000,'2026-01-01Z');
insert into public.categories(id,user_id,name,kind)
values ('35000000-0000-4000-8000-000000000001','15000000-0000-4000-8000-000000000001','Smoke Expense','expense');

set request.jwt.claims = '{"sub":"15000000-0000-4000-8000-000000000001","role":"authenticated"}';

do $$
declare first_response jsonb;
declare retry_response jsonb;
declare split_result jsonb;
begin
  split_result := public.api_calculate_split('100000','equal','[{"id":"self","included":true},{"id":"ani","included":true},{"id":"budi","included":true}]');
  if split_result->'data'->'participants'->0->>'share_amount' <> '33334' then raise exception 'equal split mismatch'; end if;

  first_response := public.api_create_transaction('75000000-0000-4000-8000-000000000001','expense','25000','25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001','2026-09-01Z',null,null,'manual');
  retry_response := public.api_create_transaction('75000000-0000-4000-8000-000000000001','expense','25000','25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001','2026-09-01Z',null,null,'manual');
  if first_response <> retry_response then raise exception 'idempotent response mismatch'; end if;

  perform public.api_create_split_bill(
    '75000000-0000-4000-8000-000000000002','120000','Smoke Bill','self',null,
    '25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001','2026-09-02Z',
    '[{"id":"65000000-0000-4000-8000-000000000001","display_name":"Saya","is_self":true,"share_amount":"40000","sort_order":0},{"id":"65000000-0000-4000-8000-000000000002","display_name":"Ani","is_self":false,"share_amount":"40000","sort_order":1},{"id":"65000000-0000-4000-8000-000000000003","display_name":"Budi","is_self":false,"share_amount":"40000","sort_order":2}]', null
  );
  perform public.api_record_split_settlement(
    '75000000-0000-4000-8000-000000000003',
    (select id from public.split_bills where title = 'Smoke Bill'),
    '65000000-0000-4000-8000-000000000002','25000000-0000-4000-8000-000000000001','15000','2026-09-03Z',null
  );

  begin
    perform public.api_record_split_settlement(
      '75000000-0000-4000-8000-000000000004',
      (select id from public.split_bills where title = 'Smoke Bill'),
      '65000000-0000-4000-8000-000000000002','25000000-0000-4000-8000-000000000001','25001','2026-09-03T01:00:00Z',null
    );
    raise exception 'overpay was accepted';
  exception when sqlstate 'P0001' then
    if position('OBLIGATION_EXCEEDED' in sqlerrm) = 0 then raise; end if;
  end;

  perform public.api_record_split_resolution(
    '75000000-0000-4000-8000-000000000005',
    (select id from public.split_bills where title = 'Smoke Bill'),
    '65000000-0000-4000-8000-000000000003','10000','2026-09-04Z','Tidak ditagih lagi'
  );
  if (select receivables from public.financial_overview where user_id = '15000000-0000-4000-8000-000000000001') <> 55000 then raise exception 'writeoff mismatch'; end if;
  perform public.api_reverse_split_resolution(
    '75000000-0000-4000-8000-000000000006',
    (select id from public.split_resolutions where member_id = '65000000-0000-4000-8000-000000000003'),
    1, 'Keputusan dibatalkan'
  );

  perform public.api_create_split_bill(
    '75000000-0000-4000-8000-000000000007','120000','Smoke Other Payer','other','65000000-0000-4000-8000-000000000012',
    null,'35000000-0000-4000-8000-000000000001','2026-09-05Z',
    '[{"id":"65000000-0000-4000-8000-000000000011","display_name":"Saya","is_self":true,"share_amount":"40000","sort_order":0},{"id":"65000000-0000-4000-8000-000000000012","display_name":"Ani","is_self":false,"share_amount":"40000","sort_order":1},{"id":"65000000-0000-4000-8000-000000000013","display_name":"Budi","is_self":false,"share_amount":"40000","sort_order":2}]', null
  );
  if (select payables from public.financial_overview where user_id = '15000000-0000-4000-8000-000000000001') <> 40000 then raise exception 'other-payer payable mismatch'; end if;
  perform public.api_record_split_settlement(
    '75000000-0000-4000-8000-000000000008',
    (select id from public.split_bills where title = 'Smoke Other Payer'),
    '65000000-0000-4000-8000-000000000012','25000000-0000-4000-8000-000000000001','40000','2026-09-06Z',null
  );
end;
$$;

do $$
begin
  if (select count(*) from public.transactions where user_id = '15000000-0000-4000-8000-000000000001') <> 1 then raise exception 'retry created duplicate transaction'; end if;
  if (select balance from public.account_balances where account_id = '25000000-0000-4000-8000-000000000001') <> 30000 then raise exception 'cash balance mismatch'; end if;
  if (select receivables from public.financial_overview where user_id = '15000000-0000-4000-8000-000000000001') <> 65000 then raise exception 'receivable mismatch'; end if;
  if (select payables from public.financial_overview where user_id = '15000000-0000-4000-8000-000000000001') <> 0 then raise exception 'payable settlement mismatch'; end if;
  if (select net_position from public.financial_overview where user_id = '15000000-0000-4000-8000-000000000001') <> 95000 then raise exception 'net position mismatch'; end if;
  if (select sum(personal_expense_amount) from public.ledger_entries where user_id = '15000000-0000-4000-8000-000000000001' and reversed_at is null) <> 105000 then raise exception 'personal expense mismatch'; end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claims','{"sub":"15000000-0000-4000-8000-000000000002","role":"authenticated"}',false);
do $$
begin
  if (select count(*) from public.accounts) <> 1 then raise exception 'RLS own onboarding account mismatch'; end if;
  if exists (select 1 from public.accounts where id = '25000000-0000-4000-8000-000000000001') then raise exception 'RLS cross-user read'; end if;
end;
$$;
reset role;

select 'plain PostgreSQL migration smoke passed' as result;
