begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

select has_function('public', 'api_update_transfer', array['uuid','uuid','integer','uuid','uuid','text','timestamptz','text'], 'transfer update RPC exists');
select has_function('public', 'api_confirm_review_item', array['uuid','uuid','text','text','uuid','uuid','timestamptz','text','text'], 'review confirmation RPC exists');
select has_function('public', 'api_update_split_bill', array['uuid','uuid','integer','text','text','text','uuid','uuid','uuid','timestamptz','jsonb','text'], 'split bill update RPC exists');
select has_function('public', 'api_merge_review_item', array['uuid','uuid','uuid'], 'review merge RPC exists');
select has_function('public', 'api_create_split_bill_from_review', array['uuid','uuid','text','text','text','uuid','uuid','uuid','timestamptz','jsonb','text'], 'review to split RPC exists');
select has_function('public', 'api_convert_transaction_to_split_bill', array['uuid','uuid','integer','text','text','text','uuid','uuid','uuid','timestamptz','jsonb','text'], 'transaction conversion RPC exists');

insert into auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '15000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ios-support@danarapi.invalid', '', now(), '{}', '{}', now(), now());

select is((select count(*)::integer from public.accounts where user_id = '15000000-0000-4000-8000-000000000001' and name = 'Tunai'), 1, 'new user receives one Tunai account');
select throws_ok($sql$
  update public.accounts set archived_at = now()
  where user_id = '15000000-0000-4000-8000-000000000001' and name = 'Tunai'
$sql$, 'P0001', 'last active account cannot be archived');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"15000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select lives_ok($sql$
  select public.api_create_transaction(
    '75000000-0000-4000-8000-000000000001', 'expense', '1000',
    (select id from public.accounts where user_id = '15000000-0000-4000-8000-000000000001' and name = 'Tunai'),
    (select id from public.categories where user_id = '15000000-0000-4000-8000-000000000001' and system_key = 'other_expense'),
    now(), null, null, 'manual'
  )
$sql$, 'transaction can be created on onboarding account');
select throws_ok($sql$
  update public.accounts set opening_balance = 5000
  where user_id = '15000000-0000-4000-8000-000000000001' and name = 'Tunai'
$sql$, 'P0001', 'opening balance is locked after activity');

select * from finish();
rollback;
