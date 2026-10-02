create or replace function private.assert_account(
  p_user_id uuid,
  p_account_id uuid,
  p_occurred_at timestamptz
)
returns public.accounts language plpgsql set search_path = public, pg_temp as $$
declare result public.accounts%rowtype;
begin
  select * into result from public.accounts
  where user_id = p_user_id and id = p_account_id and archived_at is null;
  if not found then
    perform private.raise_app_error('VALIDATION', 'Akun tidak tersedia.', jsonb_build_object('field', 'account_id'));
  end if;
  if p_occurred_at is null or not isfinite(p_occurred_at) then
    perform private.raise_app_error('VALIDATION', 'Pilih tanggal transaksi yang valid.', jsonb_build_object('field', 'occurred_at'));
  end if;
  return result;
end;
$$;
