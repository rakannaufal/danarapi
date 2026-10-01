\set ON_ERROR_STOP on
begin;
set request.jwt.claims = '{"sub":"15000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

do $$
declare
  goal_id uuid := 'b1000000-0000-4000-8000-000000000001';
  account_id uuid := '25000000-0000-4000-8000-000000000001';
  category_id uuid := '35000000-0000-4000-8000-000000000001';
  response jsonb; replay jsonb; transaction_id uuid;
begin
  perform public.api_ensure_feature_categories();
  perform public.api_save_goal('b2000000-0000-4000-8000-000000000001',goal_id,'Laptop','2000000','0',null,0);
  response := public.api_create_transaction('b2000000-0000-4000-8000-000000000002','expense','70000',account_id,category_id,'2026-10-01T05:00:00Z',null,null,'manual',goal_id);
  replay := public.api_create_transaction('b2000000-0000-4000-8000-000000000002','expense','70000',account_id,category_id,'2026-10-01T05:00:00Z',null,null,'manual',goal_id);
  if response<>replay then raise exception 'Target replay changed response'; end if;
  transaction_id := (response->'data'->>'id')::uuid;
  if (select progress_amount from public.savings_goal_progress where id=goal_id)<>'70000' then raise exception 'Target progress mismatch'; end if;
  if not exists(select 1 from public.transactions transaction join public.categories category on category.id=transaction.category_id where transaction.id=transaction_id and category.system_key='goal') then raise exception 'Target category not authoritative'; end if;
  perform public.api_update_transaction('b2000000-0000-4000-8000-000000000003',transaction_id,1,'expense','100000',account_id,category_id,'2026-10-01T05:00:00Z',null,null,goal_id);
  if (select progress_amount from public.savings_goal_progress where id=goal_id)<>'100000' then raise exception 'Edited target progress mismatch'; end if;
  perform public.api_delete_transaction('b2000000-0000-4000-8000-000000000004',transaction_id,2);
  if (select progress_amount from public.savings_goal_progress where id=goal_id)<>'0' then raise exception 'Deleted contribution still counted'; end if;
  perform public.api_restore_transaction('b2000000-0000-4000-8000-000000000005',transaction_id,3);
  if (select progress_amount from public.savings_goal_progress where id=goal_id)<>'100000' then raise exception 'Restored contribution missing'; end if;
  perform public.api_save_goal('b2000000-0000-4000-8000-000000000006',goal_id,'Laptop baru','3000000','900000',null,1);
  if (select progress_amount from public.savings_goal_progress where id=goal_id)<>'100000' then raise exception 'Metadata editing manufactured progress'; end if;
  perform public.api_delete_goal('b2000000-0000-4000-8000-000000000007',goal_id,2);
  if (select transaction.goal_id from public.transactions transaction where id=transaction_id) is not null then raise exception 'Deleted goal kept transaction link'; end if;
  if (select cash_amount from public.ledger_entries where source_id=transaction_id and reversed_at is null)<>-100000 then raise exception 'Deleted goal refunded contribution'; end if;
end;
$$;

insert into public.review_items(id,user_id,source,status,extracted_fields) values('b3000000-0000-4000-8000-000000000001',auth.uid(),'qris','pending','{}');
do $$
declare response jsonb; replay jsonb; transaction_id uuid;
begin
  response := public.api_confirm_review_item('b4000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000001','income','75000','25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001','2026-10-01T05:00:00Z');
  replay := public.api_confirm_review_item('b4000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000001','income','75000','25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001','2026-10-01T05:00:00Z');
  if response<>replay then raise exception 'QRIS replay changed response'; end if;
  transaction_id := (response->'data'->>'id')::uuid;
  if not exists(select 1 from public.transactions transaction join public.categories category on category.id=transaction.category_id where transaction.id=transaction_id and transaction.type='expense' and transaction.source='qris' and category.system_key='qris') then raise exception 'QRIS kind/category mismatch'; end if;
  begin
    perform public.api_confirm_review_item('b4000000-0000-4000-8000-000000000002','b3000000-0000-4000-8000-000000000001','expense','75000','25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001','2026-10-01T05:00:00Z');
    raise exception 'QRIS charged twice';
  exception when sqlstate 'P0001' then if position('CONFLICT_VERSION' in sqlerrm)=0 then raise; end if; end;
  if (select count(*) from public.ledger_entries where source_id=transaction_id)<>1 then raise exception 'QRIS duplicate ledger'; end if;
end;
$$;
set request.jwt.claims = '{"sub":"15000000-0000-4000-8000-000000000002","role":"authenticated"}';
do $$ begin if exists(select 1 from public.savings_goal_progress) then raise exception 'Target view owner isolation failed'; end if; end; $$;
rollback;
