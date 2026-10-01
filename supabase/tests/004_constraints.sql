begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '14000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'constraint-one@danarapi.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '14000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'constraint-two@danarapi.invalid', '', now(), '{}', '{}', now(), now());
insert into public.accounts(id, user_id, name, kind, opened_at)
values ('24000000-0000-4000-8000-000000000001', '14000000-0000-4000-8000-000000000001', 'Constraint Cash', 'cash', '2026-09-01Z');
insert into public.categories(id, user_id, name, kind)
values
  ('34000000-0000-4000-8000-000000000001', '14000000-0000-4000-8000-000000000001', 'Expense One', 'expense'),
  ('34000000-0000-4000-8000-000000000002', '14000000-0000-4000-8000-000000000002', 'Expense Two', 'expense');

select throws_ok($sql$
  insert into public.transactions(user_id,type,amount,account_id,category_id,occurred_at)
  values ('14000000-0000-4000-8000-000000000001','expense',1000,'24000000-0000-4000-8000-000000000001','34000000-0000-4000-8000-000000000002','2026-09-02Z')
$sql$, '23503', null, 'composite FK rejects cross-owner category');
select throws_ok($sql$
  insert into public.transactions(user_id,type,amount,account_id,category_id,occurred_at)
  values ('14000000-0000-4000-8000-000000000001','expense',0,'24000000-0000-4000-8000-000000000001','34000000-0000-4000-8000-000000000001','2026-09-02Z')
$sql$, '23514', null, 'zero transaction amount is rejected');
select throws_ok($sql$
  insert into public.transfers(user_id,from_account_id,to_account_id,amount,occurred_at)
  values ('14000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000001','24000000-0000-4000-8000-000000000001',1000,'2026-09-02Z')
$sql$, '23514', null, 'transfer to the same account is rejected');
select throws_ok($sql$
  insert into public.attachments(user_id,transaction_id,review_item_id,storage_key,mime,size_bytes,sha256)
  values ('14000000-0000-4000-8000-000000000001',gen_random_uuid(),gen_random_uuid(),'14000000-0000-4000-8000-000000000001/x','image/png',10,repeat('a',64))
$sql$, '23514', null, 'attachment requires exactly one parent');

insert into public.split_bills(id,user_id,total,title,payer_kind,payer_account_id,category_id,occurred_at)
values ('64000000-0000-4000-8000-000000000001','14000000-0000-4000-8000-000000000001',100000,'Invalid total','self','24000000-0000-4000-8000-000000000001','34000000-0000-4000-8000-000000000001','2026-09-02Z');
insert into public.split_members(id,user_id,split_bill_id,display_name,is_self,share_amount,sort_order)
values
  ('64000000-0000-4000-8000-000000000002','14000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','Saya',true,40000,0),
  ('64000000-0000-4000-8000-000000000003','14000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','Ani',false,50000,1);
select throws_ok($$select private.validate_split_bill('64000000-0000-4000-8000-000000000001')$$, '23514', null, 'split shares must exactly equal total');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"14000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select throws_ok($sql$
  select public.api_create_transaction('74000000-0000-4000-8000-000000000001','expense','1000','24000000-0000-4000-8000-000000000001','34000000-0000-4000-8000-000000000001','2026-08-31Z',null,null,'manual')
$sql$, 'P0001', null, 'transaction before account opening is rejected');

select * from finish();
rollback;
