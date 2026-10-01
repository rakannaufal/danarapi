#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"

USER_ID='13000000-0000-4000-8000-000000000001'
BILL_ID='63000000-0000-4000-8000-000000000001'
MEMBER_ID='63000000-0000-4000-8000-000000000002'
ACCOUNT_ID='23000000-0000-4000-8000-000000000001'
CATEGORY_ID='33000000-0000-4000-8000-000000000001'

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
begin;
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('00000000-0000-0000-0000-000000000000','$USER_ID','authenticated','authenticated','concurrency@danarapi.invalid','',now(),'{}','{}',now(),now()) on conflict do nothing;
insert into public.accounts(id,user_id,name,kind,opening_balance,opened_at) values ('$ACCOUNT_ID','$USER_ID','Concurrency Cash','cash',200000,'2026-01-01Z') on conflict do nothing;
insert into public.categories(id,user_id,name,kind) values ('$CATEGORY_ID','$USER_ID','Concurrency Expense','expense') on conflict do nothing;
insert into public.split_bills(id,user_id,total,title,payer_kind,payer_account_id,category_id,occurred_at) values ('$BILL_ID','$USER_ID',100000,'Concurrency Bill','self','$ACCOUNT_ID','$CATEGORY_ID','2026-09-01Z') on conflict do nothing;
insert into public.split_members(id,user_id,split_bill_id,display_name,is_self,share_amount,sort_order) values
('63000000-0000-4000-8000-000000000003','$USER_ID','$BILL_ID','Saya',true,50000,0),
('$MEMBER_ID','$USER_ID','$BILL_ID','Ani',false,50000,1) on conflict do nothing;
commit;
SQL

run_settlement() {
  mutation_id="$1"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"$USER_ID","role":"authenticated"}',true);
select public.api_record_split_settlement('$mutation_id','$BILL_ID','$MEMBER_ID','$ACCOUNT_ID','30000','2026-09-02Z',null);
commit;
SQL
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
run_settlement '73000000-0000-4000-8000-000000000001' >"$tmp_dir/one.log" 2>&1 &
pid_one=$!
run_settlement '73000000-0000-4000-8000-000000000002' >"$tmp_dir/two.log" 2>&1 &
pid_two=$!

success=0
if wait "$pid_one"; then success=$((success + 1)); fi
if wait "$pid_two"; then success=$((success + 1)); fi
test "$success" -eq 1

remaining="$(psql "$DATABASE_URL" -Atc "select original_amount-settled_amount-resolved_amount from public.split_obligations where split_bill_id='$BILL_ID' and member_id='$MEMBER_ID'")"
test "$remaining" = "20000"
echo "Concurrency invariant passed: one 30000 settlement committed, remaining 20000."
