begin;

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
  insert into public.accounts(user_id, name, kind, opening_balance, opened_at)
  values (new.id, 'Tunai', 'cash', 0, now())
  on conflict do nothing;
  return new;
end;
$$;

insert into public.accounts(user_id, name, kind, opening_balance, opened_at)
select users.id, 'Tunai', 'cash', 0, now()
from auth.users users
where not exists (select 1 from public.accounts account where account.user_id = users.id)
on conflict do nothing;

create or replace function private.protect_account_opening()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if (new.opening_balance, new.opened_at) is distinct from (old.opening_balance, old.opened_at)
     and exists (
       select 1 from public.ledger_entries
       where user_id = old.user_id and account_id = old.id and reversed_at is null
     ) then
    perform private.raise_app_error('STRUCTURE_LOCKED', 'Saldo awal hanya dapat diubah sebelum akun memiliki transaksi.');
  end if;
  return new;
end;
$$;

drop trigger if exists accounts_protect_opening on public.accounts;
create trigger accounts_protect_opening
before update of opening_balance, opened_at on public.accounts
for each row execute function private.protect_account_opening();

create or replace function private.protect_last_active_account()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if old.archived_at is null and new.archived_at is not null
     and not exists (select 1 from public.accounts where user_id = old.user_id and id <> old.id and archived_at is null) then
    perform private.raise_app_error('VALIDATION', 'Akun aktif terakhir tidak dapat diarsip.');
  end if;
  return new;
end;
$$;

drop trigger if exists accounts_protect_last_active on public.accounts;
create trigger accounts_protect_last_active
before update of archived_at on public.accounts
for each row execute function private.protect_last_active_account();

create or replace function public.api_update_transfer(
  p_client_mutation_id uuid,
  p_transfer_id uuid,
  p_expected_version integer,
  p_from_account_id uuid,
  p_to_account_id uuid,
  p_amount text,
  p_occurred_at timestamptz,
  p_note text default null
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare
  uid uuid := private.current_user_id();
  payload jsonb := jsonb_build_object('id', p_transfer_id, 'version', p_expected_version, 'from', p_from_account_id, 'to', p_to_account_id, 'amount', p_amount, 'occurred_at', p_occurred_at, 'note', p_note);
  gate record;
  item public.transfers%rowtype;
  parsed_amount bigint;
  response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'update_transfer', payload);
  if not gate.is_new then return gate.cached_response; end if;
  if p_from_account_id = p_to_account_id then perform private.raise_app_error('VALIDATION', 'Akun asal dan tujuan harus berbeda.'); end if;
  parsed_amount := private.parse_money(p_amount);
  perform private.assert_account(uid, p_from_account_id, p_occurred_at);
  perform private.assert_account(uid, p_to_account_id, p_occurred_at);
  select * into item from public.transfers where user_id = uid and id = p_transfer_id and deleted_at is null for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Transfer tidak ditemukan.'); end if;
  if item.version <> p_expected_version then perform private.raise_app_error('CONFLICT_VERSION', 'Versi transfer telah berubah.'); end if;
  update public.transfers set from_account_id = p_from_account_id, to_account_id = p_to_account_id, amount = parsed_amount, occurred_at = p_occurred_at, note = nullif(btrim(p_note), '')
  where id = p_transfer_id returning * into item;
  update public.ledger_entries set account_id = p_from_account_id, occurred_at = p_occurred_at, cash_amount = -parsed_amount
  where user_id = uid and source_kind = 'transfer' and source_id = p_transfer_id and leg = 'out' and reversed_at is null;
  update public.ledger_entries set account_id = p_to_account_id, occurred_at = p_occurred_at, cash_amount = parsed_amount
  where user_id = uid and source_kind = 'transfer' and source_id = p_transfer_id and leg = 'in' and reversed_at is null;
  response := private.envelope(jsonb_build_object('id', item.id::text, 'amount', item.amount::text, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

revoke all on function public.api_update_transfer(uuid,uuid,integer,uuid,uuid,text,timestamptz,text) from public;
grant execute on function public.api_update_transfer(uuid,uuid,integer,uuid,uuid,text,timestamptz,text) to authenticated;

create or replace function public.api_confirm_review_item(
  p_client_mutation_id uuid,
  p_review_item_id uuid,
  p_type text,
  p_amount text,
  p_account_id uuid,
  p_category_id uuid,
  p_occurred_at timestamptz,
  p_merchant text default null,
  p_note text default null
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare
  uid uuid := private.current_user_id();
  item public.review_items%rowtype;
  response jsonb;
begin
  response := public.api_create_transaction(
    p_client_mutation_id, p_type, p_amount, p_account_id, p_category_id,
    p_occurred_at, p_merchant, p_note, 'review'
  );

  select * into item
  from public.review_items
  where user_id = uid and id = p_review_item_id
  for update;
  if not found then
    perform private.raise_app_error('NOT_FOUND', 'Item tinjauan tidak ditemukan.');
  end if;
  if item.status = 'pending' then
    update public.review_items
    set status = 'saved', duplicate_of = null
    where user_id = uid and id = p_review_item_id;
  elsif item.status <> 'saved' then
    perform private.raise_app_error('CONFLICT_VERSION', 'Item tinjauan sudah diselesaikan dengan tindakan lain.');
  end if;
  return response;
end;
$$;

revoke all on function public.api_confirm_review_item(uuid,uuid,text,text,uuid,uuid,timestamptz,text,text) from public;
grant execute on function public.api_confirm_review_item(uuid,uuid,text,text,uuid,uuid,timestamptz,text,text) to authenticated;

commit;
