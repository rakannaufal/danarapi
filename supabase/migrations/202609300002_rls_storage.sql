begin;

create or replace function private.current_user_id()
returns uuid language plpgsql stable set search_path = public, pg_temp as $$
declare uid uuid;
begin
  uid := auth.uid();
  if uid is null then
    raise exception using errcode = 'P0001', message = '{"code":"UNAUTHORIZED","message":"Sesi diperlukan."}';
  end if;
  return uid;
end;
$$;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles(user_id) values (new.id) on conflict do nothing;
  insert into public.categories(user_id, name, kind, system_key, sort_order)
  values
    (new.id, 'Lainnya', 'expense', 'other_expense', 900),
    (new.id, 'Pemasukan lain', 'income', 'other_income', 900),
    (new.id, 'Hadiah/Pembebasan utang', 'income', 'debt_forgiveness', 910)
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users for each row execute function private.handle_new_user();

create or replace function private.enforce_attachment_quota()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  item_count bigint;
  byte_count bigint;
begin
  select count(*), coalesce(sum(size_bytes), 0)
  into item_count, byte_count
  from public.attachments
  where user_id = new.user_id and (tg_op = 'INSERT' or id <> new.id);

  if item_count + 1 > 200 or byte_count + new.size_bytes > 104857600 then
    raise exception using errcode = 'P0001', message = '{"code":"QUOTA_EXCEEDED","message":"Kuota lampiran tercapai."}';
  end if;
  return new;
end;
$$;

create trigger attachments_quota
before insert or update of size_bytes on public.attachments
for each row execute function private.enforce_attachment_quota();

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'profiles','accounts','categories','transactions','transfers','adjustments',
    'split_bills','split_members','split_settlements','split_resolutions',
    'review_items','attachments','merchant_rules','budgets','ledger_entries','mutation_receipts'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'create policy %I_owner_select on public.%I for select to authenticated using ((select auth.uid()) = user_id)',
      table_name, table_name
    );
    execute format(
      'create policy %I_owner_insert on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)',
      table_name, table_name
    );
    execute format(
      'create policy %I_owner_update on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)',
      table_name, table_name
    );
    execute format(
      'create policy %I_owner_delete on public.%I for delete to authenticated using ((select auth.uid()) = user_id)',
      table_name, table_name
    );
  end loop;
end;
$$;

revoke all on all tables in schema public from anon;
grant select on public.profiles, public.accounts, public.categories, public.transactions,
  public.transfers, public.adjustments, public.split_bills, public.split_members,
  public.split_settlements, public.split_resolutions, public.review_items,
  public.attachments, public.merchant_rules, public.budgets, public.ledger_entries,
  public.account_balances, public.financial_overview, public.split_obligations,
  public.split_bill_summaries to authenticated;
grant update (timezone, locale, theme) on public.profiles to authenticated;
grant insert, update, delete on public.review_items, public.attachments,
  public.merchant_rules, public.budgets to authenticated;

revoke all on public.mutation_receipts from anon, authenticated;
revoke insert, update, delete on public.accounts, public.categories, public.transactions,
  public.transfers, public.adjustments, public.split_bills, public.split_members,
  public.split_settlements, public.split_resolutions, public.ledger_entries from authenticated;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'attachments',
  'attachments',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/heic', 'application/pdf']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy attachments_storage_select
on storage.objects for select to authenticated
using (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy attachments_storage_insert
on storage.objects for insert to authenticated
with check (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy attachments_storage_update
on storage.objects for update to authenticated
using (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text)
with check (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy attachments_storage_delete
on storage.objects for delete to authenticated
using (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);

commit;
