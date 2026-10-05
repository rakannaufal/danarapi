begin;

create or replace function private.protect_last_active_account()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- Allow the authenticated user-deletion flow to cascade through all accounts.
  if tg_op = 'DELETE' and not exists (select 1 from auth.users where id = old.user_id) then return old; end if;
  if old.archived_at is null and (tg_op = 'DELETE' or new.archived_at is not null) then
    perform pg_advisory_xact_lock(hashtextextended(old.user_id::text, 21022));
    if not exists (select 1 from public.accounts where user_id = old.user_id and id <> old.id and archived_at is null) then
      perform private.raise_app_error('VALIDATION', 'Akun aktif terakhir tidak dapat dihapus. Tambahkan akun lain terlebih dahulu.');
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger accounts_protect_last_delete before delete on public.accounts
for each row execute function private.protect_last_active_account();

-- Serialize cash writes with balance corrections, including transfers and reversals.
create function private.lock_cash_owner()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(coalesce(new.user_id, old.user_id)::text, 21021));
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger ledger_cash_owner_lock before insert or update or delete on public.ledger_entries
for each row execute function private.lock_cash_owner();

create function public.api_edit_financial_account(
  p_client_mutation_id uuid, p_account_id uuid, p_expected_version integer,
  p_expected_balance text, p_name text, p_kind text, p_balance text,
  p_reason text default 'Koreksi saldo akun'
)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := private.current_user_id();
  receipt record;
  account public.accounts%rowtype;
  current_balance numeric;
  target bigint := private.parse_signed_money(p_balance);
  delta numeric;
  adjustment_id uuid := gen_random_uuid();
  adjustment_date timestamptz;
begin
  select * into receipt from private.start_mutation(uid, p_client_mutation_id, 'edit_financial_account',
    jsonb_build_object('id', p_account_id, 'version', p_expected_version, 'expectedBalance', p_expected_balance,
      'name', p_name, 'kind', p_kind, 'balance', p_balance, 'reason', p_reason));
  if not receipt.is_new then return receipt.cached_response; end if;
  if p_name is null or length(btrim(p_name)) not between 1 and 80 or p_kind is null
    or p_kind not in ('cash', 'bank', 'ewallet', 'other') or p_reason is null
    or length(btrim(p_reason)) not between 1 and 500
    or p_expected_balance is null or p_expected_balance !~ '^-?(0|[1-9][0-9]{0,19})$' then
    perform private.raise_app_error('VALIDATION', 'Nama, jenis, saldo, atau alasan tidak valid.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 21021));
  select * into account from public.accounts where user_id = uid and id = p_account_id for no key update;
  if not found or account.version <> p_expected_version then
    perform private.raise_app_error('CONFLICT_VERSION', 'Akun telah berubah. Buka ulang sebelum mengedit saldo.');
  end if;
  if account.archived_at is not null then
    perform private.raise_app_error('VALIDATION', 'Akun sudah diarsipkan.');
  end if;
  select account.opening_balance + coalesce(sum(cash_amount), 0) into current_balance
    from public.ledger_entries where user_id = uid and account_id = p_account_id and reversed_at is null;
  if current_balance <> p_expected_balance::numeric then
    perform private.raise_app_error('CONFLICT_VERSION', 'Saldo berubah karena aktivitas baru. Buka ulang sebelum menyimpan.');
  end if;
  delta := target - current_balance;
  if abs(delta) > 999999999999 then
    perform private.raise_app_error('VALIDATION', 'Selisih penyesuaian saldo melebihi batas nominal.');
  end if;
  update public.accounts set name = btrim(p_name), kind = p_kind where user_id = uid and id = p_account_id;
  if delta <> 0 then
    adjustment_date := greatest(now(), account.opened_at);
    insert into public.adjustments(id, user_id, account_id, signed_amount, reason, occurred_at)
      values (adjustment_id, uid, p_account_id, delta::bigint, btrim(p_reason), adjustment_date);
    insert into public.ledger_entries(user_id, account_id, source_kind, source_id, leg, occurred_at, cash_amount)
      values (uid, p_account_id, 'adjustment', adjustment_id, 'cash', adjustment_date, delta::bigint);
  end if;
  return private.finish_mutation(uid, p_client_mutation_id,
    private.envelope(jsonb_build_object('id', p_account_id, 'balance', target::text, 'adjustment', delta::text)));
end;
$$;

-- Referenced accounts/categories are archived so historical records remain valid.
create function public.api_delete_financial_record(
  p_client_mutation_id uuid, p_entity text, p_id uuid, p_expected_version integer
)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := private.current_user_id(); receipt record; row_version integer; system_category text; disposition text := 'deleted';
begin
  select * into receipt from private.start_mutation(uid, p_client_mutation_id, 'delete_financial_record',
    jsonb_build_object('entity', p_entity, 'id', p_id, 'version', p_expected_version));
  if not receipt.is_new then return receipt.cached_response; end if;
  if p_entity = 'account' then
    select version into row_version from public.accounts where user_id = uid and id = p_id for update;
  elsif p_entity = 'category' then
    select version, system_key into row_version, system_category from public.categories where user_id = uid and id = p_id for update;
    if system_category is not null then perform private.raise_app_error('VALIDATION', 'Kategori bawaan sistem tidak dapat dihapus.'); end if;
  else perform private.raise_app_error('VALIDATION', 'Jenis data tidak valid.');
  end if;
  if row_version is null or row_version <> p_expected_version then
    perform private.raise_app_error('CONFLICT_VERSION', 'Data telah berubah. Muat ulang sebelum menghapus.');
  end if;
  if p_entity = 'account' and exists (select 1 from public.accounts where user_id = uid and id = p_id and archived_at is null)
    and (select count(*) from public.accounts where user_id = uid and archived_at is null) <= 1 then
    perform private.raise_app_error('VALIDATION', 'Akun aktif terakhir tidak dapat dihapus. Tambahkan akun lain terlebih dahulu.');
  end if;
  begin
    if p_entity = 'account' then delete from public.accounts where user_id = uid and id = p_id;
    else delete from public.categories where user_id = uid and id = p_id; end if;
  exception when foreign_key_violation then
    disposition := 'archived';
    if p_entity = 'account' then update public.accounts set archived_at = coalesce(archived_at, now()) where user_id = uid and id = p_id;
    else update public.categories set archived_at = coalesce(archived_at, now()) where user_id = uid and id = p_id; end if;
  end;
  return private.finish_mutation(uid, p_client_mutation_id, private.envelope(jsonb_build_object('id', p_id, 'disposition', disposition)));
end;
$$;

create function public.api_delete_budget(p_id uuid, p_expected_limit text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.budgets where user_id = private.current_user_id() and id = p_id
    and limit_amount = private.parse_money(p_expected_limit);
  if not found then perform private.raise_app_error('CONFLICT_VERSION', 'Anggaran berubah. Muat ulang sebelum menghapus.'); end if;
end;
$$;

create function public.api_discard_review(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- Existing retention worker removes the file and attachment safely after this transition.
  update public.review_items set status = 'expired' where user_id = private.current_user_id() and id = p_id and status in ('pending', 'rejected');
  if not found and not exists (select 1 from public.review_items where user_id = private.current_user_id() and id = p_id and status = 'expired') then
    perform private.raise_app_error('CONFLICT_VERSION', 'Draft sudah diproses atau tidak tersedia.');
  end if;
end;
$$;

revoke all on function public.api_edit_financial_account(uuid,uuid,integer,text,text,text,text,text),
  public.api_delete_financial_record(uuid,text,uuid,integer), public.api_delete_budget(uuid,text), public.api_discard_review(uuid) from public, anon;
grant execute on function public.api_edit_financial_account(uuid,uuid,integer,text,text,text,text,text),
  public.api_delete_financial_record(uuid,text,uuid,integer), public.api_delete_budget(uuid,text), public.api_discard_review(uuid) to authenticated;
commit;
