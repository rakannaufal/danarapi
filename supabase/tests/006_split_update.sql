begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '16000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'split-update@danarapi.invalid', '', now(), '{}', '{}', now(), now());

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"16000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select lives_ok($sql$
  select public.api_create_split_bill(
    '76000000-0000-4000-8000-000000000001', '100000', 'Makan awal', 'self', null,
    (select id from public.accounts where user_id = '16000000-0000-4000-8000-000000000001' and name = 'Tunai'),
    (select id from public.categories where user_id = '16000000-0000-4000-8000-000000000001' and system_key = 'other_expense'),
    now(),
    '[{"id":"26000000-0000-4000-8000-000000000001","display_name":"Saya","is_self":true,"share_amount":"33334","sort_order":0},{"id":"26000000-0000-4000-8000-000000000002","display_name":"Ani","is_self":false,"share_amount":"33333","sort_order":1},{"id":"26000000-0000-4000-8000-000000000003","display_name":"Budi","is_self":false,"share_amount":"33333","sort_order":2}]'::jsonb,
    null
  )
$sql$, 'split bill can be created before update');

select lives_ok($sql$
  select public.api_update_split_bill(
    '76000000-0000-4000-8000-000000000002',
    (select id from public.split_bills where user_id = '16000000-0000-4000-8000-000000000001'),
    1, '120000', 'Makan diperbarui', 'self', null,
    (select id from public.accounts where user_id = '16000000-0000-4000-8000-000000000001' and name = 'Tunai'),
    (select id from public.categories where user_id = '16000000-0000-4000-8000-000000000001' and system_key = 'other_expense'),
    (select occurred_at from public.split_bills where user_id = '16000000-0000-4000-8000-000000000001'),
    '[{"id":"26000000-0000-4000-8000-000000000001","display_name":"Saya","is_self":true,"share_amount":"40000","sort_order":0},{"id":"26000000-0000-4000-8000-000000000002","display_name":"Ani","is_self":false,"share_amount":"40000","sort_order":1},{"id":"26000000-0000-4000-8000-000000000003","display_name":"Budi","is_self":false,"share_amount":"40000","sort_order":2}]'::jsonb,
    'baru'
  )
$sql$, 'split structure can be updated before child events');

select is(
  (select row(cash_amount, personal_expense_amount, receivable_delta)::text from public.ledger_entries where source_kind = 'split_bill' and user_id = '16000000-0000-4000-8000-000000000001'),
  '(-120000,40000,80000)',
  'split update replaces ledger projection atomically'
);

select lives_ok($sql$
  select public.api_record_split_settlement(
    '76000000-0000-4000-8000-000000000003',
    (select id from public.split_bills where user_id = '16000000-0000-4000-8000-000000000001'),
    '26000000-0000-4000-8000-000000000002',
    (select id from public.accounts where user_id = '16000000-0000-4000-8000-000000000001' and name = 'Tunai'),
    '10000', now(), null
  )
$sql$, 'settlement can be recorded after update');

select throws_ok($sql$
  select public.api_update_split_bill(
    '76000000-0000-4000-8000-000000000004',
    (select id from public.split_bills where user_id = '16000000-0000-4000-8000-000000000001'),
    2, '120001', 'Perubahan terlarang', 'self', null,
    (select id from public.accounts where user_id = '16000000-0000-4000-8000-000000000001' and name = 'Tunai'),
    (select id from public.categories where user_id = '16000000-0000-4000-8000-000000000001' and system_key = 'other_expense'),
    (select occurred_at from public.split_bills where user_id = '16000000-0000-4000-8000-000000000001'),
    '[{"id":"26000000-0000-4000-8000-000000000001","display_name":"Saya","is_self":true,"share_amount":"40001","sort_order":0},{"id":"26000000-0000-4000-8000-000000000002","display_name":"Ani","is_self":false,"share_amount":"40000","sort_order":1},{"id":"26000000-0000-4000-8000-000000000003","display_name":"Budi","is_self":false,"share_amount":"40000","sort_order":2}]'::jsonb,
    null
  )
$sql$, 'P0001', 'active settlement locks financial structure');

select lives_ok($sql$
  select public.api_update_split_bill(
    '76000000-0000-4000-8000-000000000005',
    (select id from public.split_bills where user_id = '16000000-0000-4000-8000-000000000001'),
    2, '120000', 'Judul setelah pelunasan', 'self', null,
    (select id from public.accounts where user_id = '16000000-0000-4000-8000-000000000001' and name = 'Tunai'),
    (select id from public.categories where user_id = '16000000-0000-4000-8000-000000000001' and system_key = 'other_expense'),
    (select occurred_at from public.split_bills where user_id = '16000000-0000-4000-8000-000000000001'),
    '[{"id":"26000000-0000-4000-8000-000000000001","display_name":"Saya","is_self":true,"share_amount":"40000","sort_order":0},{"id":"26000000-0000-4000-8000-000000000002","display_name":"Ani","is_self":false,"share_amount":"40000","sort_order":1},{"id":"26000000-0000-4000-8000-000000000003","display_name":"Budi","is_self":false,"share_amount":"40000","sort_order":2}]'::jsonb,
    'metadata tetap boleh'
  )
$sql$, 'metadata can be updated while a child event is active');

select * from finish();
rollback;
