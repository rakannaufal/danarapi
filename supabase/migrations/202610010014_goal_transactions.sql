begin;

alter table public.savings_goals add constraint savings_goals_owner_id_unique unique(user_id,id);
alter table public.transactions add column goal_id uuid;
alter table public.transactions add constraint transactions_goal_owner_fk foreign key(user_id,goal_id) references public.savings_goals(user_id,id) on delete set null(goal_id);
alter table public.transactions add constraint transactions_goal_expense check(goal_id is null or type='expense');
create index transactions_goal_active on public.transactions(user_id,goal_id) where deleted_at is null and goal_id is not null;
alter table public.review_items add column confirmed_transaction_id uuid references public.transactions(id) on delete set null;
create unique index review_confirmed_transaction_unique on public.review_items(confirmed_transaction_id) where confirmed_transaction_id is not null;

create function private.feature_category(p_user_id uuid,p_feature text)
returns uuid language plpgsql set search_path=public,private,pg_temp as $$
declare category_id uuid; label text;
begin
  if p_feature not in ('goal','qris') then perform private.raise_app_error('VALIDATION','Kategori fitur tidak valid.'); end if;
  label := case when p_feature='goal' then 'Target' else 'QRIS' end;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || ':feature-categories',0));
  select id into category_id from public.categories where user_id=p_user_id and system_key=p_feature for update;
  if found then
    update public.categories set archived_at=null where id=category_id and archived_at is not null;
    return category_id;
  end if;
  select id into category_id from public.categories where user_id=p_user_id and kind='expense' and lower(btrim(name))=lower(label) for update;
  if found then update public.categories set system_key=p_feature,archived_at=null where id=category_id; return category_id; end if;
  insert into public.categories(user_id,name,kind,system_key,sort_order) values(p_user_id,label,'expense',p_feature,920) returning id into category_id;
  return category_id;
end;
$$;

create function public.api_ensure_feature_categories()
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare uid uuid := private.current_user_id();
begin
  return jsonb_build_object('goal',private.feature_category(uid,'goal'),'qris',private.feature_category(uid,'qris'));
end;
$$;
revoke all on function public.api_ensure_feature_categories() from public,anon;
grant execute on function public.api_ensure_feature_categories() to authenticated;

create function private.feature_transaction_category(p_user_id uuid,p_category_id uuid,p_type text,p_goal_id uuid,p_source text)
returns uuid language plpgsql set search_path=public,private,pg_temp as $$
begin
  if p_source='qris' then
    if p_type<>'expense' or p_goal_id is not null then perform private.raise_app_error('VALIDATION','QRIS dicatat sebagai pengeluaran.'); end if;
    return private.feature_category(p_user_id,'qris');
  end if;
  if p_goal_id is not null then
    if p_type<>'expense' then perform private.raise_app_error('VALIDATION','Progres target harus berupa pengeluaran.'); end if;
    perform 1 from public.savings_goals where user_id=p_user_id and id=p_goal_id for update;
    if not found then perform private.raise_app_error('VALIDATION','Target tidak ditemukan.'); end if;
    return private.feature_category(p_user_id,'goal');
  end if;
  if exists(select 1 from public.categories where user_id=p_user_id and id=p_category_id and system_key='goal') then perform private.raise_app_error('VALIDATION','Pilih target untuk pengeluaran ini.'); end if;
  return p_category_id;
end;
$$;

create view public.savings_goal_progress with(security_invoker=true) as
select goal.*,(goal.saved_amount::numeric+coalesce((select sum(transaction.amount) from public.transactions transaction where transaction.user_id=goal.user_id and transaction.goal_id=goal.id and transaction.deleted_at is null and transaction.type='expense'),0))::text as progress_amount
from public.savings_goals goal;
grant select on public.savings_goal_progress to authenticated;

drop function public.api_create_transaction(uuid,text,text,uuid,uuid,timestamptz,text,text,text);
drop function public.api_update_transaction(uuid,uuid,integer,text,text,uuid,uuid,timestamptz,text,text);

create or replace function public.api_create_transaction(
  p_client_mutation_id uuid,
  p_type text,
  p_amount text,
  p_account_id uuid,
  p_category_id uuid,
  p_occurred_at timestamptz,
  p_merchant text default null,
  p_note text default null,
  p_source text default 'manual',
  p_goal_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('type', p_type, 'amount', p_amount, 'account_id', p_account_id, 'category_id', p_category_id, 'occurred_at', p_occurred_at, 'merchant', p_merchant, 'note', p_note, 'goal_id', p_goal_id, 'source', p_source);
declare gate record;
declare feature_category uuid;
declare item public.transactions%rowtype;
declare parsed_amount bigint;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'create_transaction', payload);
  if not gate.is_new then return gate.cached_response; end if;
  if p_type not in ('income', 'expense') then perform private.raise_app_error('VALIDATION', 'Jenis transaksi tidak valid.'); end if;
  parsed_amount := private.parse_money(p_amount);
  perform private.assert_account(uid, p_account_id, p_occurred_at);
  feature_category := private.feature_transaction_category(uid, p_category_id, p_type, p_goal_id, p_source);
  perform private.assert_category(uid, feature_category, p_type);

  insert into public.transactions(user_id, type, amount, account_id, category_id, occurred_at, merchant, note, source, goal_id)
  values (uid, p_type, parsed_amount, p_account_id, feature_category, p_occurred_at, nullif(btrim(p_merchant), ''), nullif(btrim(p_note), ''), p_source, p_goal_id)
  returning * into item;
  insert into public.ledger_entries(user_id, account_id, category_id, source_kind, source_id, leg, occurred_at, cash_amount, personal_income_amount, personal_expense_amount)
  values (uid, p_account_id, feature_category, 'transaction', item.id, 'cash', p_occurred_at,
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
  p_note text default null,
  p_goal_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('id', p_transaction_id, 'expected_version', p_expected_version, 'type', p_type, 'amount', p_amount, 'account_id', p_account_id, 'category_id', p_category_id, 'occurred_at', p_occurred_at, 'merchant', p_merchant, 'note', p_note, 'goal_id', p_goal_id);
declare gate record;
declare feature_category uuid;
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
  feature_category := private.feature_transaction_category(uid, p_category_id, p_type, p_goal_id, item.source);
  perform private.assert_category(uid, feature_category, p_type);

  update public.transactions set type = p_type, amount = parsed_amount, account_id = p_account_id,
    category_id = feature_category, occurred_at = p_occurred_at, merchant = nullif(btrim(p_merchant), ''), note = nullif(btrim(p_note), ''), goal_id = p_goal_id
  where id = p_transaction_id returning * into item;
  update public.ledger_entries set account_id = p_account_id, category_id = feature_category, occurred_at = p_occurred_at,
    cash_amount = case when p_type = 'income' then parsed_amount else -parsed_amount end,
    personal_income_amount = case when p_type = 'income' then parsed_amount else 0 end,
    personal_expense_amount = case when p_type = 'expense' then parsed_amount else 0 end
  where user_id = uid and source_kind = 'transaction' and source_id = p_transaction_id and leg = 'cash';
  response := private.envelope(jsonb_build_object('id', item.id::text, 'amount', item.amount::text, 'type', item.type, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_save_goal(p_client_mutation_id uuid, p_id uuid, p_name text, p_target text, p_saved text, p_target_date date, p_expected_version integer)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id(); gate record; item public.savings_goals%rowtype; target bigint; saved bigint;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'save_goal', jsonb_build_object('id',p_id,'name',p_name,'target',p_target,'saved',p_saved,'date',p_target_date,'version',p_expected_version));
  if not gate.is_new then return gate.cached_response; end if;
  target := private.parse_money(p_target); saved := 0;
  if p_id is null or length(btrim(coalesce(p_name,''))) not between 1 and 100 then perform private.raise_app_error('VALIDATION','Nama goal wajib diisi, maksimal 100 karakter.'); end if;
  select * into item from public.savings_goals where id=p_id and user_id=uid for update;
  if found then
    if item.version is distinct from p_expected_version then perform private.raise_app_error('CONFLICT_VERSION','Goal sudah berubah. Muat ulang.'); end if;
    update public.savings_goals set name=btrim(p_name),target_amount=target,target_date=p_target_date where id=p_id and user_id=uid returning * into item;
  else
    if p_expected_version <> 0 or p_expected_version is null then perform private.raise_app_error('NOT_FOUND','Goal tidak ditemukan.'); end if;
    if private.parse_money(p_saved,true) <> 0 then perform private.raise_app_error('VALIDATION','Progres target dicatat melalui transaksi.'); end if;
    insert into public.savings_goals(id,user_id,name,target_amount,saved_amount,target_date) values(p_id,uid,btrim(p_name),target,saved,p_target_date) returning * into item;
  end if;
  return private.finish_mutation(uid,p_client_mutation_id,private.envelope(jsonb_build_object('id',item.id,'version',item.version)));
end;
$$;

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
  created_transaction_id uuid;
  response jsonb;
begin
  select * into item from public.review_items
  where user_id = uid and id = p_review_item_id
  for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Item tinjauan tidak ditemukan.'); end if;
  if item.status not in ('pending', 'saved') then perform private.raise_app_error('CONFLICT_VERSION', 'Item tinjauan sudah diselesaikan dengan tindakan lain.'); end if;
  if item.status='saved' and not exists(
    select 1 from public.mutation_receipts receipt where receipt.user_id=uid and receipt.client_mutation_id=p_client_mutation_id
      and receipt.operation='create_transaction' and (receipt.response->'data'->>'id')::uuid=item.confirmed_transaction_id
  ) then perform private.raise_app_error('CONFLICT_VERSION','Item tinjauan sudah dicatat.'); end if;
  if item.status='pending' and exists(select 1 from public.mutation_receipts where user_id=uid and client_mutation_id=p_client_mutation_id)
    then perform private.raise_app_error('DUPLICATE_MUTATION','ID mutasi sudah digunakan.'); end if;

  response := public.api_create_transaction(
    p_client_mutation_id, case when item.source='qris' then 'expense' else p_type end, p_amount, p_account_id, p_category_id,
    p_occurred_at, p_merchant, p_note, case when item.source='qris' then 'qris' else 'review' end
  );
  created_transaction_id := (response->'data'->>'id')::uuid;

  if item.status = 'pending' then
    update public.attachments set transaction_id = created_transaction_id, review_item_id = null
    where user_id = uid and review_item_id = p_review_item_id;
    update public.review_items set status = 'saved', duplicate_of = null, confirmed_transaction_id=created_transaction_id
    where user_id = uid and id = p_review_item_id;
  end if;
  return response;
end;
$$;
revoke all on function public.api_create_transaction(uuid,text,text,uuid,uuid,timestamptz,text,text,text,uuid), public.api_update_transaction(uuid,uuid,integer,text,text,uuid,uuid,timestamptz,text,text,uuid) from public,anon;
grant execute on function public.api_create_transaction(uuid,text,text,uuid,uuid,timestamptz,text,text,text,uuid), public.api_update_transaction(uuid,uuid,integer,text,text,uuid,uuid,timestamptz,text,text,uuid) to authenticated;
commit;
