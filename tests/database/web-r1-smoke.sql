\set ON_ERROR_STOP on
begin;
set request.jwt.claims = '{"sub":"15000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

do $$
declare account_a uuid := '25000000-0000-4000-8000-000000000001';
declare account_b uuid;
declare category_id uuid := '35000000-0000-4000-8000-000000000001';
declare web_row jsonb;
declare transaction_id uuid;
declare transfer_id uuid;
declare before_cash bigint;
declare after_cash bigint;
declare result jsonb;
declare bill_id uuid;
declare before_ledger bigint;
begin
  result := public.api_create_account('a1000000-0000-4000-8000-000000000001', 'Web interop bank', 'bank', '0', '2026-07-01T00:00:00Z');
  account_b := (result->'data'->>'id')::uuid;
  web_row := public.api_create_transaction('a1000000-0000-4000-8000-000000000002', 'expense', '12500', account_a, category_id, '2026-09-30T05:00:00Z', 'Catatan dari web', null, 'manual');
  transaction_id := (web_row->'data'->>'id')::uuid;
  if (select amount from public.transactions where id = transaction_id) <> 12500 then raise exception 'iOS read after web mutation differs'; end if;
  perform public.api_update_transaction('a1000000-0000-4000-8000-000000000003', transaction_id, 1, 'expense', '14000', account_a, category_id, '2026-09-30T05:00:00Z', 'Koreksi dari iOS', null);
  if (select amount from public.transactions where id = transaction_id) <> 14000 then raise exception 'web read after iOS mutation differs'; end if;
  begin
    perform public.api_update_transaction('a1000000-0000-4000-8000-000000000004', transaction_id, 1, 'expense', '15000', account_a, category_id, '2026-09-30T05:00:00Z', null, null);
    raise exception 'stale web version overwrote iOS change';
  exception when sqlstate 'P0001' then
    if position('CONFLICT_VERSION' in sqlerrm) = 0 then raise; end if;
  end;
  select coalesce(sum(cash_amount),0) into before_cash from public.ledger_entries where account_id = account_a and reversed_at is null;
  result := public.api_create_transfer('a1000000-0000-4000-8000-000000000005', account_a, account_b, '10000', '2026-09-30T05:00:00Z', 'Transfer web');
  transfer_id := (result->'data'->>'id')::uuid;
  perform public.api_delete_transfer('a1000000-0000-4000-8000-000000000006', transfer_id, 1);
  perform public.api_restore_transfer('a1000000-0000-4000-8000-000000000007', transfer_id, 2);
  perform public.api_restore_transfer('a1000000-0000-4000-8000-000000000007', transfer_id, 2);
  select coalesce(sum(cash_amount),0) into after_cash from public.ledger_entries where account_id = account_a and reversed_at is null;
  if after_cash <> before_cash - 10000 then raise exception 'restore/retry double counted transfer'; end if;
  if (select sum(cash_amount) from public.ledger_entries where source_id = transfer_id and reversed_at is null) <> 0 then raise exception 'transfer legs not balanced'; end if;
  insert into public.review_items(id,user_id,source,status,extracted_fields)
    values ('a2000000-0000-4000-8000-000000000001','15000000-0000-4000-8000-000000000001','pasted_text','pending','{"fingerprint":"web-exact-source"}');
  begin
    insert into public.review_items(id,user_id,source,status,extracted_fields)
      values ('a2000000-0000-4000-8000-000000000002','15000000-0000-4000-8000-000000000001','pasted_text','pending','{"fingerprint":"web-exact-source"}');
    raise exception 'exact duplicate source allowed';
  exception when unique_violation then null;
  end;
  select id into bill_id from public.split_bills where user_id = '15000000-0000-4000-8000-000000000001' and deleted_at is null limit 1;
  if bill_id is null then raise exception 'missing bill for merge test'; end if;
  begin
    update public.review_items set duplicate_bill_id = gen_random_uuid() where id = 'a2000000-0000-4000-8000-000000000001';
    raise exception 'unowned duplicate bill allowed';
  exception when foreign_key_violation then null;
  end;
  insert into public.attachments(id,user_id,review_item_id,storage_key,mime,size_bytes,sha256)
    values ('a3000000-0000-4000-8000-000000000001','15000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000001','15000000-0000-4000-8000-000000000001/web-merge.png','image/png',8,repeat('1',64));
  select count(*) into before_ledger from public.ledger_entries;
  perform public.api_merge_review_item_to_bill('a1000000-0000-4000-8000-000000000008','a2000000-0000-4000-8000-000000000001',bill_id);
  perform public.api_merge_review_item_to_bill('a1000000-0000-4000-8000-000000000008','a2000000-0000-4000-8000-000000000001',bill_id);
  if not exists (select 1 from public.attachments where id = 'a3000000-0000-4000-8000-000000000001' and split_bill_id = bill_id and review_item_id is null) then raise exception 'merge did not move attachment'; end if;
  if not exists (select 1 from public.review_items where id = 'a2000000-0000-4000-8000-000000000001' and duplicate_bill_id = bill_id and duplicate_of is null and status = 'merged') then raise exception 'merge target not persisted'; end if;
  if (select count(*) from public.ledger_entries) <> before_ledger then raise exception 'duplicate merge created ledger event'; end if;
  select coalesce(sum(cash_amount),0) into before_cash from public.ledger_entries where account_id = account_a and reversed_at is null;
  if before_cash <> after_cash then raise exception 'duplicate merge changed cash'; end if;
end;
$$;
rollback;
select 'Web/iOS shared RPC read-write, stale version, transfer undo/replay and exact source guard passed' as result;
