begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '11000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rls-one@danarapi.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '11000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rls-two@danarapi.invalid', '', now(), '{}', '{}', now(), now());

insert into public.accounts(id, user_id, name, kind, opened_at)
values
  ('21000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Akun User 1', 'cash', now()),
  ('21000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000002', 'Akun User 2', 'cash', now());

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is((select count(*)::integer from public.accounts), 2, 'user one reads own onboarding and fixture accounts');
select is((select name from public.accounts where id = '21000000-0000-4000-8000-000000000001'), 'Akun User 1', 'user one reads own fixture account');
select is((select count(*)::integer from public.accounts where user_id = '11000000-0000-4000-8000-000000000002'), 0, 'user one cannot read user two accounts');
select lives_ok($$insert into public.review_items(id, user_id, source) values ('41000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'pasted_text')$$, 'user one writes own review item');
select throws_ok($$insert into public.review_items(id, user_id, source) values ('41000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000002', 'pasted_text')$$, '42501', null, 'user one cannot write user two review item');
select throws_ok($$update public.review_items set user_id = '11000000-0000-4000-8000-000000000002' where id = '41000000-0000-4000-8000-000000000001'$$, 'P0001', null, 'owner cannot be changed');
select lives_ok($$insert into storage.objects(bucket_id, name, owner) values ('attachments', '11000000-0000-4000-8000-000000000001/receipt.png', '11000000-0000-4000-8000-000000000001')$$, 'user one writes own storage path');
select throws_ok($$insert into storage.objects(bucket_id, name, owner) values ('attachments', '11000000-0000-4000-8000-000000000002/receipt.png', '11000000-0000-4000-8000-000000000001')$$, '42501', null, 'user one cannot write user two storage path');

select set_config('request.jwt.claims', '{"sub":"11000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select is((select count(*)::integer from public.accounts), 2, 'user two reads own onboarding and fixture accounts');
select is((select name from public.accounts where id = '21000000-0000-4000-8000-000000000002'), 'Akun User 2', 'user two reads own fixture account');
select is((select count(*)::integer from public.accounts where user_id = '11000000-0000-4000-8000-000000000001'), 0, 'user two cannot read user one accounts');
select is((select count(*)::integer from public.review_items), 0, 'user two cannot read user one review item');

select * from finish();
rollback;
