\set ON_ERROR_STOP on

set request.jwt.claims = '{"sub":"15000000-0000-4000-8000-000000000001","role":"authenticated"}';

do $$
declare bill_id uuid;
declare account_id uuid := '25000000-0000-4000-8000-000000000001';
declare category_id uuid := '35000000-0000-4000-8000-000000000001';
declare bill_time timestamptz;
begin
  select id, occurred_at into bill_id, bill_time
  from public.split_bills
  where user_id = '15000000-0000-4000-8000-000000000001' and title = 'Smoke Bill';

  perform public.api_update_split_bill(
    '77000000-0000-4000-8000-000000000001', bill_id, 1, '120000', 'Smoke Bill Metadata',
    'self', null, account_id, category_id, bill_time,
    '[{"id":"65000000-0000-4000-8000-000000000001","display_name":"Saya","is_self":true,"share_amount":"40000","sort_order":0},{"id":"65000000-0000-4000-8000-000000000002","display_name":"Ani","is_self":false,"share_amount":"40000","sort_order":1},{"id":"65000000-0000-4000-8000-000000000003","display_name":"Budi","is_self":false,"share_amount":"40000","sort_order":2}]',
    'metadata tetap boleh'
  );
  if (select version from public.split_bills where id = bill_id) <> 2 then raise exception 'metadata update version mismatch'; end if;

  begin
    perform public.api_update_split_bill(
      '77000000-0000-4000-8000-000000000002', bill_id, 2, '120001', 'Struktur terlarang',
      'self', null, account_id, category_id, bill_time,
      '[{"id":"65000000-0000-4000-8000-000000000001","display_name":"Saya","is_self":true,"share_amount":"40001","sort_order":0},{"id":"65000000-0000-4000-8000-000000000002","display_name":"Ani","is_self":false,"share_amount":"40000","sort_order":1},{"id":"65000000-0000-4000-8000-000000000003","display_name":"Budi","is_self":false,"share_amount":"40000","sort_order":2}]',
      null
    );
    raise exception 'active settlement allowed structural split update';
  exception when sqlstate 'P0001' then
    if position('STRUCTURE_LOCKED' in sqlerrm) = 0 then raise; end if;
  end;
end;
$$;

insert into public.review_items(id, user_id, source, status, extracted_fields)
values (
  '47000000-0000-4000-8000-000000000001',
  '15000000-0000-4000-8000-000000000001',
  'image', 'pending', '{}'::jsonb
);
insert into public.attachments(id, user_id, review_item_id, storage_key, mime, size_bytes, sha256)
values (
  '57000000-0000-4000-8000-000000000001',
  '15000000-0000-4000-8000-000000000001',
  '47000000-0000-4000-8000-000000000001',
  '15000000-0000-4000-8000-000000000001/57000000-0000-4000-8000-000000000001.png',
  'image/png', 8, repeat('0', 64)
);

select public.api_confirm_review_item(
  '77000000-0000-4000-8000-000000000003',
  '47000000-0000-4000-8000-000000000001',
  'expense', '12500',
  '25000000-0000-4000-8000-000000000001',
  '35000000-0000-4000-8000-000000000001',
  '2026-09-07T00:00:00Z', 'Smoke Receipt', null
);

do $$
begin
  if (select status from public.review_items where id = '47000000-0000-4000-8000-000000000001') <> 'saved' then raise exception 'review confirmation status mismatch'; end if;
  if not exists (
    select 1 from public.attachments
    where id = '57000000-0000-4000-8000-000000000001'
      and review_item_id is null and transaction_id is not null and split_bill_id is null
  ) then raise exception 'attachment was not moved to confirmed transaction'; end if;
end;
$$;

do $$
declare transaction_id uuid;
declare split_id uuid;
begin
  select a.transaction_id into transaction_id from public.attachments a where a.id = '57000000-0000-4000-8000-000000000001';
  perform public.api_convert_transaction_to_split_bill(
    '77000000-0000-4000-8000-000000000004', transaction_id, 1,
    '12500', 'Converted Receipt', 'self', null,
    '25000000-0000-4000-8000-000000000001',
    '35000000-0000-4000-8000-000000000001',
    '2026-09-07T00:00:00Z',
    '[{"id":"68000000-0000-4000-8000-000000000001","display_name":"Saya","is_self":true,"share_amount":"5000","sort_order":0},{"id":"68000000-0000-4000-8000-000000000002","display_name":"Ani","is_self":false,"share_amount":"7500","sort_order":1}]',
    null
  );
  select id into split_id from public.split_bills where user_id = '15000000-0000-4000-8000-000000000001' and title = 'Converted Receipt';
  if (select deleted_at from public.transactions where id = transaction_id) is null then raise exception 'converted transaction remained active'; end if;
  if exists (select 1 from public.ledger_entries where source_kind = 'transaction' and source_id = transaction_id and reversed_at is null) then raise exception 'converted transaction ledger remained active'; end if;
  if not exists (select 1 from public.ledger_entries where source_kind = 'split_bill' and source_id = split_id and reversed_at is null and personal_expense_amount = 5000) then raise exception 'converted split ledger mismatch'; end if;
  if not exists (select 1 from public.attachments a where a.id = '57000000-0000-4000-8000-000000000001' and a.transaction_id is null and a.split_bill_id = split_id) then raise exception 'converted attachment was not moved to split bill'; end if;
end;
$$;

select 'iOS R1 PostgreSQL smoke passed' as result;
