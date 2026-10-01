begin;

create or replace function private.raise_app_error(p_code text, p_message text, p_details jsonb default '{}'::jsonb)
returns void language plpgsql set search_path = public, pg_temp as $$
begin
  raise exception using
    errcode = 'P0001',
    message = jsonb_build_object('code', p_code, 'message', p_message, 'details', p_details)::text;
end;
$$;

create or replace function private.parse_money(p_value text, p_allow_zero boolean default false)
returns bigint language plpgsql immutable set search_path = public, pg_temp as $$
declare parsed numeric;
begin
  if p_value is null or p_value !~ '^(0|[1-9][0-9]{0,11})$' then
    perform private.raise_app_error('VALIDATION', 'Nominal harus berupa string Rupiah bulat.', jsonb_build_object('field', 'amount'));
  end if;
  parsed := p_value::numeric;
  if parsed > 999999999999 or (not p_allow_zero and parsed = 0) then
    perform private.raise_app_error('VALIDATION', 'Nominal berada di luar batas produk.', jsonb_build_object('field', 'amount'));
  end if;
  return parsed::bigint;
end;
$$;

create or replace function private.parse_signed_money(p_value text)
returns bigint language plpgsql immutable set search_path = public, pg_temp as $$
declare parsed numeric;
begin
  if p_value is null or p_value !~ '^-?(0|[1-9][0-9]{0,11})$' then
    perform private.raise_app_error('VALIDATION', 'Nominal bertanda harus berupa string Rupiah bulat.');
  end if;
  parsed := p_value::numeric;
  if abs(parsed) > 999999999999 then
    perform private.raise_app_error('VALIDATION', 'Nominal berada di luar batas produk.');
  end if;
  return parsed::bigint;
end;
$$;

create or replace function private.start_mutation(
  p_user_id uuid,
  p_client_mutation_id uuid,
  p_operation text,
  p_payload jsonb
)
returns table(is_new boolean, cached_response jsonb)
language plpgsql
set search_path = public, extensions, pg_temp
as $$
declare
  expected_hash text := encode(digest(p_payload::text, 'sha256'), 'hex');
  inserted_count integer;
  receipt public.mutation_receipts%rowtype;
begin
  if p_client_mutation_id is null then
    perform private.raise_app_error('VALIDATION', 'client_mutation_id wajib diisi.');
  end if;

  insert into public.mutation_receipts(user_id, client_mutation_id, operation, payload_hash)
  values (p_user_id, p_client_mutation_id, p_operation, expected_hash)
  on conflict do nothing;
  get diagnostics inserted_count = row_count;

  if inserted_count = 1 then
    return query select true, null::jsonb;
    return;
  end if;

  select * into receipt
  from public.mutation_receipts
  where user_id = p_user_id and client_mutation_id = p_client_mutation_id;

  if receipt.operation <> p_operation or receipt.payload_hash <> expected_hash then
    perform private.raise_app_error('DUPLICATE_MUTATION', 'ID mutasi telah dipakai dengan payload berbeda.');
  end if;
  if receipt.response is null then
    perform private.raise_app_error('INTERNAL', 'Receipt mutasi belum lengkap.');
  end if;
  return query select false, receipt.response;
end;
$$;

create or replace function private.finish_mutation(
  p_user_id uuid,
  p_client_mutation_id uuid,
  p_response jsonb
)
returns jsonb language plpgsql set search_path = public, pg_temp as $$
begin
  update public.mutation_receipts
  set response = p_response, applied_at = now()
  where user_id = p_user_id and client_mutation_id = p_client_mutation_id;
  return p_response;
end;
$$;

create or replace function private.envelope(p_data jsonb)
returns jsonb language sql volatile set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'schema_version', '1.0.0',
    'request_id', gen_random_uuid()::text,
    'data', p_data
  );
$$;

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
  if p_occurred_at < result.opened_at then
    perform private.raise_app_error('VALIDATION', 'Tanggal transaksi lebih lama dari tanggal pembukaan akun.', jsonb_build_object('field', 'occurred_at'));
  end if;
  return result;
end;
$$;

create or replace function private.assert_category(p_user_id uuid, p_category_id uuid, p_kind text)
returns void language plpgsql set search_path = public, pg_temp as $$
begin
  if not exists (
    select 1 from public.categories
    where user_id = p_user_id and id = p_category_id and kind = p_kind and archived_at is null
  ) then
    perform private.raise_app_error('VALIDATION', 'Kategori tidak sesuai atau sudah diarsip.', jsonb_build_object('field', 'category_id'));
  end if;
end;
$$;

create or replace function private.obligation_original(
  p_user_id uuid,
  p_bill_id uuid,
  p_member_id uuid
)
returns table(obligation_kind text, original_amount bigint)
language plpgsql set search_path = public, pg_temp as $$
declare bill public.split_bills%rowtype;
declare member public.split_members%rowtype;
declare self_share bigint;
begin
  select * into bill from public.split_bills where user_id = p_user_id and id = p_bill_id and deleted_at is null;
  if not found then
    perform private.raise_app_error('NOT_FOUND', 'Split bill tidak ditemukan.');
  end if;
  select * into member from public.split_members where user_id = p_user_id and id = p_member_id and split_bill_id = p_bill_id;
  if not found then
    perform private.raise_app_error('VALIDATION', 'Peserta bukan bagian dari split bill.');
  end if;

  if bill.payer_kind = 'self' and not member.is_self then
    return query select 'receivable'::text, member.share_amount::bigint;
  elsif bill.payer_kind = 'other' and bill.payer_member_id = member.id then
    select share_amount into self_share from public.split_members where split_bill_id = p_bill_id and is_self;
    return query select 'payable'::text, self_share;
  else
    perform private.raise_app_error('VALIDATION', 'Peserta tidak memiliki kewajiban terhadap pengguna.');
  end if;
end;
$$;

create or replace function private.enforce_obligation_limit()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare
  original_kind text;
  original_amount bigint;
  active_settlements bigint;
  active_resolutions bigint;
begin
  perform 1 from public.split_bills where id = new.split_bill_id and user_id = new.user_id for update;
  select o.obligation_kind, o.original_amount into original_kind, original_amount
  from private.obligation_original(new.user_id, new.split_bill_id, new.member_id) o;

  select coalesce(sum(amount), 0) into active_settlements
  from public.split_settlements
  where split_bill_id = new.split_bill_id and member_id = new.member_id and reversed_at is null
    and (tg_table_name <> 'split_settlements' or id <> new.id);
  select coalesce(sum(amount), 0) into active_resolutions
  from public.split_resolutions
  where split_bill_id = new.split_bill_id and member_id = new.member_id and reversed_at is null
    and (tg_table_name <> 'split_resolutions' or id <> new.id);

  if tg_table_name = 'split_settlements' then
    if new.direction <> (case when original_kind = 'receivable' then 'in' else 'out' end) then
      perform private.raise_app_error('VALIDATION', 'Arah pelunasan tidak sesuai kewajiban.');
    end if;
    active_settlements := active_settlements + new.amount;
  else
    if new.kind <> (case when original_kind = 'receivable' then 'receivable_writeoff' else 'payable_forgiveness' end) then
      perform private.raise_app_error('VALIDATION', 'Jenis penghapusan tidak sesuai kewajiban.');
    end if;
    active_resolutions := active_resolutions + new.amount;
  end if;

  if new.reversed_at is null and active_settlements + active_resolutions > original_amount then
    perform private.raise_app_error('OBLIGATION_EXCEEDED', 'Pelunasan atau penghapusan melebihi sisa kewajiban.');
  end if;
  return new;
end;
$$;

create trigger split_settlements_limit
before insert or update of amount, member_id, reversed_at on public.split_settlements
for each row execute function private.enforce_obligation_limit();

create or replace function public.api_calculate_split(
  p_total text,
  p_method text,
  p_participants jsonb
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare parsed_total bigint := private.parse_money(p_total);
declare participant_count integer;
declare included_count integer;
declare basis_point_total integer;
declare allocation jsonb;
begin
  if jsonb_typeof(p_participants) <> 'array' then
    perform private.raise_app_error('VALIDATION', 'Peserta harus berupa array.');
  end if;
  participant_count := jsonb_array_length(p_participants);
  if participant_count not between 2 and 20 then
    perform private.raise_app_error('VALIDATION', 'Split bill harus memiliki 2 sampai 20 peserta.');
  end if;

  if p_method = 'equal' then
    select count(*) filter (where coalesce((value->>'included')::boolean, true))
    into included_count from jsonb_array_elements(p_participants);
    if included_count = 0 then perform private.raise_app_error('VALIDATION', 'Setidaknya satu peserta harus ikut pembagian.'); end if;

    with rows as (
      select value, ordinality::integer as ord, coalesce((value->>'included')::boolean, true) as included
      from jsonb_array_elements(p_participants) with ordinality
    ), ranked as (
      select *, count(*) filter (where included) over (order by ord rows between unbounded preceding and current row) as included_rank
      from rows
    )
    select jsonb_agg(
      value || jsonb_build_object(
        'share_amount',
        case when not included then '0'
          else ((parsed_total / included_count) + case when included_rank <= (parsed_total % included_count) then 1 else 0 end)::bigint::text
        end
      ) order by ord
    ) into allocation from ranked;
  elsif p_method = 'percentage' then
    select coalesce(sum((value->>'basis_points')::integer), 0)
    into basis_point_total from jsonb_array_elements(p_participants);
    if basis_point_total <> 10000 or exists (
      select 1 from jsonb_array_elements(p_participants)
      where (value->>'basis_points') is null
        or (value->>'basis_points') !~ '^[0-9]{1,5}$'
        or (value->>'basis_points')::integer not between 0 and 10000
    ) then
      perform private.raise_app_error('VALIDATION', 'Persentase harus berjumlah tepat 100,00%.');
    end if;

    with rows as (
      select value, ordinality::integer as ord, (value->>'basis_points')::integer as bp
      from jsonb_array_elements(p_participants) with ordinality
    ), amounts as (
      select *, floor(parsed_total::numeric * bp / 10000)::bigint as floor_amount,
        (parsed_total::numeric * bp)::bigint % 10000 as fractional
      from rows
    ), totals as (
      select *, parsed_total - sum(floor_amount) over () as remainder,
        row_number() over (order by fractional desc, ord) as remainder_rank
      from amounts
    )
    select jsonb_agg(
      value || jsonb_build_object('share_amount', (floor_amount + case when remainder_rank <= remainder then 1 else 0 end)::bigint::text)
      order by ord
    ) into allocation from totals;
  else
    perform private.raise_app_error('VALIDATION', 'Metode pembagian tidak didukung.');
  end if;

  return private.envelope(jsonb_build_object('method', p_method, 'total', parsed_total::text, 'participants', allocation));
end;
$$;

create trigger split_resolutions_limit
before insert or update of amount, member_id, reversed_at on public.split_resolutions
for each row execute function private.enforce_obligation_limit();

create or replace function public.api_create_account(
  p_client_mutation_id uuid,
  p_name text,
  p_kind text,
  p_opening_balance text,
  p_opened_at timestamptz
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare
  uid uuid := private.current_user_id();
  payload jsonb := jsonb_build_object('name', p_name, 'kind', p_kind, 'opening_balance', p_opening_balance, 'opened_at', p_opened_at);
  gate record;
  item public.accounts%rowtype;
  response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'create_account', payload);
  if not gate.is_new then return gate.cached_response; end if;
  if p_kind not in ('cash', 'bank', 'ewallet', 'other') or length(btrim(coalesce(p_name, ''))) not between 1 and 80 then
    perform private.raise_app_error('VALIDATION', 'Nama atau jenis akun tidak valid.');
  end if;

  insert into public.accounts(user_id, name, kind, opening_balance, opened_at)
  values (uid, btrim(p_name), p_kind, private.parse_signed_money(p_opening_balance), p_opened_at)
  returning * into item;

  response := private.envelope(jsonb_build_object(
    'id', item.id::text, 'name', item.name, 'kind', item.kind,
    'opening_balance', item.opening_balance::text, 'version', item.version
  ));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_create_category(
  p_client_mutation_id uuid,
  p_name text,
  p_kind text,
  p_sort_order integer default 0
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('name', p_name, 'kind', p_kind, 'sort_order', p_sort_order);
declare gate record;
declare item public.categories%rowtype;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'create_category', payload);
  if not gate.is_new then return gate.cached_response; end if;
  if p_kind not in ('income', 'expense') or length(btrim(coalesce(p_name, ''))) not between 1 and 80 then
    perform private.raise_app_error('VALIDATION', 'Nama atau jenis kategori tidak valid.');
  end if;
  insert into public.categories(user_id, name, kind, sort_order)
  values (uid, btrim(p_name), p_kind, greatest(p_sort_order, 0)) returning * into item;
  response := private.envelope(jsonb_build_object('id', item.id::text, 'name', item.name, 'kind', item.kind, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_create_transaction(
  p_client_mutation_id uuid,
  p_type text,
  p_amount text,
  p_account_id uuid,
  p_category_id uuid,
  p_occurred_at timestamptz,
  p_merchant text default null,
  p_note text default null,
  p_source text default 'manual'
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('type', p_type, 'amount', p_amount, 'account_id', p_account_id, 'category_id', p_category_id, 'occurred_at', p_occurred_at, 'merchant', p_merchant, 'note', p_note, 'source', p_source);
declare gate record;
declare item public.transactions%rowtype;
declare parsed_amount bigint;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'create_transaction', payload);
  if not gate.is_new then return gate.cached_response; end if;
  if p_type not in ('income', 'expense') then perform private.raise_app_error('VALIDATION', 'Jenis transaksi tidak valid.'); end if;
  parsed_amount := private.parse_money(p_amount);
  perform private.assert_account(uid, p_account_id, p_occurred_at);
  perform private.assert_category(uid, p_category_id, p_type);

  insert into public.transactions(user_id, type, amount, account_id, category_id, occurred_at, merchant, note, source)
  values (uid, p_type, parsed_amount, p_account_id, p_category_id, p_occurred_at, nullif(btrim(p_merchant), ''), nullif(btrim(p_note), ''), p_source)
  returning * into item;
  insert into public.ledger_entries(user_id, account_id, category_id, source_kind, source_id, leg, occurred_at, cash_amount, personal_income_amount, personal_expense_amount)
  values (uid, p_account_id, p_category_id, 'transaction', item.id, 'cash', p_occurred_at,
    case when p_type = 'income' then parsed_amount else -parsed_amount end,
    case when p_type = 'income' then parsed_amount else 0 end,
    case when p_type = 'expense' then parsed_amount else 0 end);

  response := private.envelope(jsonb_build_object('id', item.id::text, 'amount', item.amount::text, 'type', item.type, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_update_transaction(
  p_client_mutation_id uuid,
  p_transaction_id uuid,
  p_expected_version integer,
  p_type text,
  p_amount text,
  p_account_id uuid,
  p_category_id uuid,
  p_occurred_at timestamptz,
  p_merchant text default null,
  p_note text default null
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('id', p_transaction_id, 'expected_version', p_expected_version, 'type', p_type, 'amount', p_amount, 'account_id', p_account_id, 'category_id', p_category_id, 'occurred_at', p_occurred_at, 'merchant', p_merchant, 'note', p_note);
declare gate record;
declare item public.transactions%rowtype;
declare parsed_amount bigint;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'update_transaction', payload);
  if not gate.is_new then return gate.cached_response; end if;
  select * into item from public.transactions where user_id = uid and id = p_transaction_id and deleted_at is null for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Transaksi tidak ditemukan.'); end if;
  if item.version <> p_expected_version then perform private.raise_app_error('CONFLICT_VERSION', 'Versi transaksi telah berubah.', jsonb_build_object('server_version', item.version)); end if;
  if p_type not in ('income', 'expense') then perform private.raise_app_error('VALIDATION', 'Jenis transaksi tidak valid.'); end if;
  parsed_amount := private.parse_money(p_amount);
  perform private.assert_account(uid, p_account_id, p_occurred_at);
  perform private.assert_category(uid, p_category_id, p_type);

  update public.transactions set type = p_type, amount = parsed_amount, account_id = p_account_id,
    category_id = p_category_id, occurred_at = p_occurred_at, merchant = nullif(btrim(p_merchant), ''), note = nullif(btrim(p_note), '')
  where id = p_transaction_id returning * into item;
  update public.ledger_entries set account_id = p_account_id, category_id = p_category_id, occurred_at = p_occurred_at,
    cash_amount = case when p_type = 'income' then parsed_amount else -parsed_amount end,
    personal_income_amount = case when p_type = 'income' then parsed_amount else 0 end,
    personal_expense_amount = case when p_type = 'expense' then parsed_amount else 0 end
  where user_id = uid and source_kind = 'transaction' and source_id = p_transaction_id and leg = 'cash';
  response := private.envelope(jsonb_build_object('id', item.id::text, 'amount', item.amount::text, 'type', item.type, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_delete_transaction(
  p_client_mutation_id uuid,
  p_transaction_id uuid,
  p_expected_version integer
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('id', p_transaction_id, 'expected_version', p_expected_version);
declare gate record;
declare item public.transactions%rowtype;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'delete_transaction', payload);
  if not gate.is_new then return gate.cached_response; end if;
  select * into item from public.transactions where user_id = uid and id = p_transaction_id and deleted_at is null for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Transaksi tidak ditemukan.'); end if;
  if item.version <> p_expected_version then perform private.raise_app_error('CONFLICT_VERSION', 'Versi transaksi telah berubah.', jsonb_build_object('server_version', item.version)); end if;
  update public.transactions set deleted_at = now() where id = p_transaction_id returning * into item;
  update public.ledger_entries set reversed_at = now() where user_id = uid and source_kind = 'transaction' and source_id = p_transaction_id and reversed_at is null;
  response := private.envelope(jsonb_build_object('id', item.id::text, 'deleted_at', item.deleted_at, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_restore_transaction(
  p_client_mutation_id uuid,
  p_transaction_id uuid,
  p_expected_version integer
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('id', p_transaction_id, 'expected_version', p_expected_version);
declare gate record;
declare item public.transactions%rowtype;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'restore_transaction', payload);
  if not gate.is_new then return gate.cached_response; end if;
  select * into item from public.transactions where user_id = uid and id = p_transaction_id and deleted_at is not null for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Transaksi terhapus tidak ditemukan.'); end if;
  if item.version <> p_expected_version then perform private.raise_app_error('CONFLICT_VERSION', 'Versi transaksi telah berubah.', jsonb_build_object('server_version', item.version)); end if;
  update public.transactions set deleted_at = null where id = p_transaction_id returning * into item;
  update public.ledger_entries set reversed_at = null where user_id = uid and source_kind = 'transaction' and source_id = p_transaction_id;
  response := private.envelope(jsonb_build_object('id', item.id::text, 'deleted_at', null, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_create_transfer(
  p_client_mutation_id uuid,
  p_from_account_id uuid,
  p_to_account_id uuid,
  p_amount text,
  p_occurred_at timestamptz,
  p_note text default null
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('from', p_from_account_id, 'to', p_to_account_id, 'amount', p_amount, 'occurred_at', p_occurred_at, 'note', p_note);
declare gate record;
declare item public.transfers%rowtype;
declare parsed_amount bigint;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'create_transfer', payload);
  if not gate.is_new then return gate.cached_response; end if;
  if p_from_account_id = p_to_account_id then perform private.raise_app_error('VALIDATION', 'Akun asal dan tujuan harus berbeda.'); end if;
  parsed_amount := private.parse_money(p_amount);
  perform private.assert_account(uid, p_from_account_id, p_occurred_at);
  perform private.assert_account(uid, p_to_account_id, p_occurred_at);
  insert into public.transfers(user_id, from_account_id, to_account_id, amount, occurred_at, note)
  values (uid, p_from_account_id, p_to_account_id, parsed_amount, p_occurred_at, nullif(btrim(p_note), '')) returning * into item;
  insert into public.ledger_entries(user_id, account_id, source_kind, source_id, leg, occurred_at, cash_amount)
  values
    (uid, p_from_account_id, 'transfer', item.id, 'out', p_occurred_at, -parsed_amount),
    (uid, p_to_account_id, 'transfer', item.id, 'in', p_occurred_at, parsed_amount);
  response := private.envelope(jsonb_build_object('id', item.id::text, 'amount', item.amount::text, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_delete_transfer(
  p_client_mutation_id uuid,
  p_transfer_id uuid,
  p_expected_version integer
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('id', p_transfer_id, 'expected_version', p_expected_version);
declare gate record;
declare item public.transfers%rowtype;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'delete_transfer', payload);
  if not gate.is_new then return gate.cached_response; end if;
  select * into item from public.transfers where user_id = uid and id = p_transfer_id and deleted_at is null for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Transfer tidak ditemukan.'); end if;
  if item.version <> p_expected_version then perform private.raise_app_error('CONFLICT_VERSION', 'Versi transfer telah berubah.'); end if;
  update public.transfers set deleted_at = now() where id = p_transfer_id returning * into item;
  update public.ledger_entries set reversed_at = now() where user_id = uid and source_kind = 'transfer' and source_id = p_transfer_id and reversed_at is null;
  response := private.envelope(jsonb_build_object('id', item.id::text, 'deleted_at', item.deleted_at, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_create_split_bill(
  p_client_mutation_id uuid,
  p_total text,
  p_title text,
  p_payer_kind text,
  p_payer_member_id uuid,
  p_payer_account_id uuid,
  p_category_id uuid,
  p_occurred_at timestamptz,
  p_members jsonb,
  p_note text default null
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('total', p_total, 'title', p_title, 'payer_kind', p_payer_kind, 'payer_member_id', p_payer_member_id, 'payer_account_id', p_payer_account_id, 'category_id', p_category_id, 'occurred_at', p_occurred_at, 'members', p_members, 'note', p_note);
declare gate record;
declare item public.split_bills%rowtype;
declare parsed_total bigint;
declare self_share bigint;
declare member_record jsonb;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'create_split_bill', payload);
  if not gate.is_new then return gate.cached_response; end if;
  parsed_total := private.parse_money(p_total);
  if p_payer_kind not in ('self', 'other') or jsonb_typeof(p_members) <> 'array' or jsonb_array_length(p_members) not between 2 and 20 then
    perform private.raise_app_error('VALIDATION', 'Struktur split bill tidak valid.');
  end if;
  if length(btrim(coalesce(p_title, ''))) not between 1 and 160 then perform private.raise_app_error('VALIDATION', 'Judul split bill wajib diisi.'); end if;
  perform private.assert_category(uid, p_category_id, 'expense');
  if p_payer_kind = 'self' then
    if p_payer_account_id is null or p_payer_member_id is not null then perform private.raise_app_error('VALIDATION', 'Akun pembayar wajib saat Saya membayar.'); end if;
    perform private.assert_account(uid, p_payer_account_id, p_occurred_at);
  elsif p_payer_account_id is not null or p_payer_member_id is null then
    perform private.raise_app_error('VALIDATION', 'Peserta pembayar wajib saat teman membayar.');
  end if;

  insert into public.split_bills(user_id, total, title, payer_kind, payer_member_id, payer_account_id, category_id, occurred_at, note)
  values (uid, parsed_total, btrim(p_title), p_payer_kind, p_payer_member_id, p_payer_account_id, p_category_id, p_occurred_at, nullif(btrim(p_note), ''))
  returning * into item;

  for member_record in select value from jsonb_array_elements(p_members)
  loop
    insert into public.split_members(id, user_id, split_bill_id, display_name, is_self, share_amount, sort_order)
    values (
      (member_record->>'id')::uuid,
      uid,
      item.id,
      member_record->>'display_name',
      (member_record->>'is_self')::boolean,
      private.parse_money(member_record->>'share_amount', true),
      (member_record->>'sort_order')::integer
    );
  end loop;
  perform private.validate_split_bill(item.id);
  select share_amount into self_share from public.split_members where split_bill_id = item.id and is_self;

  if p_payer_kind = 'self' then
    insert into public.ledger_entries(user_id, account_id, category_id, source_kind, source_id, leg, occurred_at, cash_amount, personal_expense_amount, receivable_delta)
    values (uid, p_payer_account_id, p_category_id, 'split_bill', item.id, 'initial', p_occurred_at, -parsed_total, self_share, parsed_total - self_share);
  elsif self_share > 0 then
    insert into public.ledger_entries(user_id, category_id, source_kind, source_id, leg, occurred_at, personal_expense_amount, payable_delta)
    values (uid, p_category_id, 'split_bill', item.id, 'initial', p_occurred_at, self_share, self_share);
  end if;

  response := private.envelope(jsonb_build_object(
    'id', item.id::text, 'total', item.total::text, 'self_share', self_share::text,
    'payer_kind', item.payer_kind, 'status', case when parsed_total = self_share and p_payer_kind = 'self' then 'settled' when self_share = 0 and p_payer_kind = 'other' then 'settled' else 'unsettled' end,
    'version', item.version
  ));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_record_split_settlement(
  p_client_mutation_id uuid,
  p_split_bill_id uuid,
  p_member_id uuid,
  p_account_id uuid,
  p_amount text,
  p_occurred_at timestamptz,
  p_note text default null
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('bill_id', p_split_bill_id, 'member_id', p_member_id, 'account_id', p_account_id, 'amount', p_amount, 'occurred_at', p_occurred_at, 'note', p_note);
declare gate record;
declare item public.split_settlements%rowtype;
declare bill public.split_bills%rowtype;
declare obligation record;
declare parsed_amount bigint;
declare remaining bigint;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'record_split_settlement', payload);
  if not gate.is_new then return gate.cached_response; end if;
  select * into bill from public.split_bills where user_id = uid and id = p_split_bill_id and deleted_at is null for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Split bill tidak ditemukan.'); end if;
  parsed_amount := private.parse_money(p_amount);
  perform private.assert_account(uid, p_account_id, p_occurred_at);
  select * into obligation from private.obligation_original(uid, p_split_bill_id, p_member_id);
  select original_amount - settled_amount - resolved_amount into remaining
  from public.split_obligations where user_id = uid and split_bill_id = p_split_bill_id and member_id = p_member_id;
  if parsed_amount > remaining then perform private.raise_app_error('OBLIGATION_EXCEEDED', 'Pelunasan melebihi sisa kewajiban.', jsonb_build_object('remaining', remaining::text)); end if;

  insert into public.split_settlements(user_id, split_bill_id, member_id, direction, account_id, amount, occurred_at, note)
  values (uid, p_split_bill_id, p_member_id, case when obligation.obligation_kind = 'receivable' then 'in' else 'out' end, p_account_id, parsed_amount, p_occurred_at, nullif(btrim(p_note), ''))
  returning * into item;
  insert into public.ledger_entries(user_id, account_id, source_kind, source_id, leg, occurred_at, cash_amount, receivable_delta, payable_delta)
  values (uid, p_account_id, 'split_settlement', item.id, 'cash', p_occurred_at,
    case when obligation.obligation_kind = 'receivable' then parsed_amount else -parsed_amount end,
    case when obligation.obligation_kind = 'receivable' then -parsed_amount else 0 end,
    case when obligation.obligation_kind = 'payable' then -parsed_amount else 0 end);
  response := private.envelope(jsonb_build_object('id', item.id::text, 'amount', item.amount::text, 'direction', item.direction, 'remaining', (remaining - parsed_amount)::text, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_reverse_split_settlement(
  p_client_mutation_id uuid,
  p_settlement_id uuid,
  p_expected_version integer,
  p_reason text
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('id', p_settlement_id, 'expected_version', p_expected_version, 'reason', p_reason);
declare gate record;
declare item public.split_settlements%rowtype;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'reverse_split_settlement', payload);
  if not gate.is_new then return gate.cached_response; end if;
  select * into item from public.split_settlements where user_id = uid and id = p_settlement_id for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Pelunasan tidak ditemukan.'); end if;
  perform 1 from public.split_bills where id = item.split_bill_id for update;
  if item.version <> p_expected_version then perform private.raise_app_error('CONFLICT_VERSION', 'Versi pelunasan telah berubah.'); end if;
  if item.reversed_at is not null then perform private.raise_app_error('VALIDATION', 'Pelunasan sudah dibatalkan.'); end if;
  if length(btrim(coalesce(p_reason, ''))) = 0 then perform private.raise_app_error('VALIDATION', 'Alasan pembatalan wajib diisi.'); end if;
  update public.split_settlements set reversed_at = now(), reversal_reason = btrim(p_reason) where id = p_settlement_id returning * into item;
  update public.ledger_entries set reversed_at = now() where user_id = uid and source_kind = 'split_settlement' and source_id = p_settlement_id and reversed_at is null;
  response := private.envelope(jsonb_build_object('id', item.id::text, 'reversed_at', item.reversed_at, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_record_split_resolution(
  p_client_mutation_id uuid,
  p_split_bill_id uuid,
  p_member_id uuid,
  p_amount text,
  p_occurred_at timestamptz,
  p_reason text
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('bill_id', p_split_bill_id, 'member_id', p_member_id, 'amount', p_amount, 'occurred_at', p_occurred_at, 'reason', p_reason);
declare gate record;
declare item public.split_resolutions%rowtype;
declare bill public.split_bills%rowtype;
declare obligation record;
declare parsed_amount bigint;
declare remaining bigint;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'record_split_resolution', payload);
  if not gate.is_new then return gate.cached_response; end if;
  if length(btrim(coalesce(p_reason, ''))) = 0 then perform private.raise_app_error('VALIDATION', 'Alasan penghapusan wajib diisi.'); end if;
  select * into bill from public.split_bills where user_id = uid and id = p_split_bill_id and deleted_at is null for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Split bill tidak ditemukan.'); end if;
  parsed_amount := private.parse_money(p_amount);
  select * into obligation from private.obligation_original(uid, p_split_bill_id, p_member_id);
  select original_amount - settled_amount - resolved_amount into remaining
  from public.split_obligations where user_id = uid and split_bill_id = p_split_bill_id and member_id = p_member_id;
  if parsed_amount > remaining then perform private.raise_app_error('OBLIGATION_EXCEEDED', 'Penghapusan melebihi sisa kewajiban.', jsonb_build_object('remaining', remaining::text)); end if;

  insert into public.split_resolutions(user_id, split_bill_id, member_id, kind, amount, occurred_at, reason)
  values (uid, p_split_bill_id, p_member_id,
    case when obligation.obligation_kind = 'receivable' then 'receivable_writeoff' else 'payable_forgiveness' end,
    parsed_amount, p_occurred_at, btrim(p_reason)) returning * into item;
  insert into public.ledger_entries(user_id, category_id, source_kind, source_id, leg, occurred_at, personal_income_amount, personal_expense_amount, receivable_delta, payable_delta, is_non_cash)
  values (uid,
    case when obligation.obligation_kind = 'receivable' then bill.category_id else (select id from public.categories where user_id = uid and system_key = 'debt_forgiveness') end,
    'split_resolution', item.id, 'non_cash', p_occurred_at,
    case when obligation.obligation_kind = 'payable' then parsed_amount else 0 end,
    case when obligation.obligation_kind = 'receivable' then parsed_amount else 0 end,
    case when obligation.obligation_kind = 'receivable' then -parsed_amount else 0 end,
    case when obligation.obligation_kind = 'payable' then -parsed_amount else 0 end,
    true);
  response := private.envelope(jsonb_build_object('id', item.id::text, 'amount', item.amount::text, 'kind', item.kind, 'remaining', (remaining - parsed_amount)::text, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_reverse_split_resolution(
  p_client_mutation_id uuid,
  p_resolution_id uuid,
  p_expected_version integer,
  p_reason text
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('id', p_resolution_id, 'expected_version', p_expected_version, 'reason', p_reason);
declare gate record;
declare item public.split_resolutions%rowtype;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'reverse_split_resolution', payload);
  if not gate.is_new then return gate.cached_response; end if;
  select * into item from public.split_resolutions where user_id = uid and id = p_resolution_id for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Penghapusan kewajiban tidak ditemukan.'); end if;
  perform 1 from public.split_bills where id = item.split_bill_id for update;
  if item.version <> p_expected_version then perform private.raise_app_error('CONFLICT_VERSION', 'Versi penghapusan telah berubah.'); end if;
  if item.reversed_at is not null then perform private.raise_app_error('VALIDATION', 'Penghapusan sudah dibalik.'); end if;
  if length(btrim(coalesce(p_reason, ''))) = 0 then perform private.raise_app_error('VALIDATION', 'Alasan reversal wajib diisi.'); end if;
  update public.split_resolutions set reversed_at = now(), reversal_reason = btrim(p_reason) where id = p_resolution_id returning * into item;
  update public.ledger_entries set reversed_at = now() where user_id = uid and source_kind = 'split_resolution' and source_id = p_resolution_id and reversed_at is null;
  response := private.envelope(jsonb_build_object('id', item.id::text, 'reversed_at', item.reversed_at, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_delete_split_bill(
  p_client_mutation_id uuid,
  p_split_bill_id uuid,
  p_expected_version integer
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('id', p_split_bill_id, 'expected_version', p_expected_version);
declare gate record;
declare item public.split_bills%rowtype;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'delete_split_bill', payload);
  if not gate.is_new then return gate.cached_response; end if;
  select * into item from public.split_bills where user_id = uid and id = p_split_bill_id and deleted_at is null for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Split bill tidak ditemukan.'); end if;
  if item.version <> p_expected_version then perform private.raise_app_error('CONFLICT_VERSION', 'Versi split bill telah berubah.'); end if;
  if exists (select 1 from public.split_settlements where split_bill_id = item.id and reversed_at is null)
    or exists (select 1 from public.split_resolutions where split_bill_id = item.id and reversed_at is null) then
    perform private.raise_app_error('STRUCTURE_LOCKED', 'Batalkan pelunasan dan penghapusan aktif sebelum menghapus bill.');
  end if;
  update public.split_bills set deleted_at = now() where id = item.id returning * into item;
  update public.ledger_entries set reversed_at = now() where user_id = uid and source_kind = 'split_bill' and source_id = item.id and reversed_at is null;
  response := private.envelope(jsonb_build_object('id', item.id::text, 'deleted_at', item.deleted_at, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_restore_split_bill(
  p_client_mutation_id uuid,
  p_split_bill_id uuid,
  p_expected_version integer
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('id', p_split_bill_id, 'expected_version', p_expected_version);
declare gate record;
declare item public.split_bills%rowtype;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'restore_split_bill', payload);
  if not gate.is_new then return gate.cached_response; end if;
  select * into item from public.split_bills where user_id = uid and id = p_split_bill_id and deleted_at is not null for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Split bill terhapus tidak ditemukan.'); end if;
  if item.version <> p_expected_version then perform private.raise_app_error('CONFLICT_VERSION', 'Versi split bill telah berubah.'); end if;
  if exists (select 1 from public.split_settlements where split_bill_id = item.id and reversed_at is null)
    or exists (select 1 from public.split_resolutions where split_bill_id = item.id and reversed_at is null) then
    perform private.raise_app_error('STRUCTURE_LOCKED', 'Split bill memiliki kejadian turunan aktif.');
  end if;
  update public.split_bills set deleted_at = null where id = item.id returning * into item;
  update public.ledger_entries set reversed_at = null where user_id = uid and source_kind = 'split_bill' and source_id = item.id;
  response := private.envelope(jsonb_build_object('id', item.id::text, 'deleted_at', null, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

revoke all on function public.api_create_account(uuid,text,text,text,timestamptz) from public;
revoke all on function public.api_calculate_split(text,text,jsonb) from public;
revoke all on function public.api_create_category(uuid,text,text,integer) from public;
revoke all on function public.api_create_transaction(uuid,text,text,uuid,uuid,timestamptz,text,text,text) from public;
revoke all on function public.api_update_transaction(uuid,uuid,integer,text,text,uuid,uuid,timestamptz,text,text) from public;
revoke all on function public.api_delete_transaction(uuid,uuid,integer) from public;
revoke all on function public.api_restore_transaction(uuid,uuid,integer) from public;
revoke all on function public.api_create_transfer(uuid,uuid,uuid,text,timestamptz,text) from public;
revoke all on function public.api_delete_transfer(uuid,uuid,integer) from public;
revoke all on function public.api_create_split_bill(uuid,text,text,text,uuid,uuid,uuid,timestamptz,jsonb,text) from public;
revoke all on function public.api_record_split_settlement(uuid,uuid,uuid,uuid,text,timestamptz,text) from public;
revoke all on function public.api_reverse_split_settlement(uuid,uuid,integer,text) from public;
revoke all on function public.api_record_split_resolution(uuid,uuid,uuid,text,timestamptz,text) from public;
revoke all on function public.api_reverse_split_resolution(uuid,uuid,integer,text) from public;
revoke all on function public.api_delete_split_bill(uuid,uuid,integer) from public;
revoke all on function public.api_restore_split_bill(uuid,uuid,integer) from public;

grant execute on function public.api_create_account(uuid,text,text,text,timestamptz) to authenticated;
grant execute on function public.api_calculate_split(text,text,jsonb) to authenticated;
grant execute on function public.api_create_category(uuid,text,text,integer) to authenticated;
grant execute on function public.api_create_transaction(uuid,text,text,uuid,uuid,timestamptz,text,text,text) to authenticated;
grant execute on function public.api_update_transaction(uuid,uuid,integer,text,text,uuid,uuid,timestamptz,text,text) to authenticated;
grant execute on function public.api_delete_transaction(uuid,uuid,integer) to authenticated;
grant execute on function public.api_restore_transaction(uuid,uuid,integer) to authenticated;
grant execute on function public.api_create_transfer(uuid,uuid,uuid,text,timestamptz,text) to authenticated;
grant execute on function public.api_delete_transfer(uuid,uuid,integer) to authenticated;
grant execute on function public.api_create_split_bill(uuid,text,text,text,uuid,uuid,uuid,timestamptz,jsonb,text) to authenticated;
grant execute on function public.api_record_split_settlement(uuid,uuid,uuid,uuid,text,timestamptz,text) to authenticated;
grant execute on function public.api_reverse_split_settlement(uuid,uuid,integer,text) to authenticated;
grant execute on function public.api_record_split_resolution(uuid,uuid,uuid,text,timestamptz,text) to authenticated;
grant execute on function public.api_reverse_split_resolution(uuid,uuid,integer,text) to authenticated;
grant execute on function public.api_delete_split_bill(uuid,uuid,integer) to authenticated;
grant execute on function public.api_restore_split_bill(uuid,uuid,integer) to authenticated;

commit;
