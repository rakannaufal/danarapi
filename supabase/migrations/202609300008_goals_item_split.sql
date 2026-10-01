begin;

alter function private.validate_split_bill_trigger() security definer;
alter function private.validate_split_bill_row_trigger() security definer;

create table public.savings_goals (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 100),
  target_amount bigint not null check (target_amount between 1 and 999999999999),
  saved_amount bigint not null default 0 check (saved_amount between 0 and 999999999999),
  target_date date,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.savings_goals enable row level security;
create policy goals_owner on public.savings_goals for select to authenticated using (user_id = auth.uid());
grant select on public.savings_goals to authenticated;
create trigger savings_goals_touch before update on public.savings_goals for each row execute function private.touch_version();
create trigger savings_goals_owner before update on public.savings_goals for each row execute function private.reject_user_change();
alter table public.split_bills add column item_split jsonb;

create function public.api_save_goal(p_client_mutation_id uuid, p_id uuid, p_name text, p_target text, p_saved text, p_target_date date, p_expected_version integer)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id(); gate record; item public.savings_goals%rowtype; target bigint; saved bigint;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'save_goal', jsonb_build_object('id',p_id,'name',p_name,'target',p_target,'saved',p_saved,'date',p_target_date,'version',p_expected_version));
  if not gate.is_new then return gate.cached_response; end if;
  target := private.parse_money(p_target); saved := private.parse_money(p_saved,true);
  if p_id is null or length(btrim(coalesce(p_name,''))) not between 1 and 100 then perform private.raise_app_error('VALIDATION','Nama goal wajib diisi, maksimal 100 karakter.'); end if;
  select * into item from public.savings_goals where id=p_id and user_id=uid for update;
  if found then
    if item.version is distinct from p_expected_version then perform private.raise_app_error('CONFLICT_VERSION','Goal sudah berubah. Muat ulang.'); end if;
    update public.savings_goals set name=btrim(p_name),target_amount=target,saved_amount=saved,target_date=p_target_date where id=p_id and user_id=uid returning * into item;
  else
    if p_expected_version <> 0 or p_expected_version is null then perform private.raise_app_error('NOT_FOUND','Goal tidak ditemukan.'); end if;
    insert into public.savings_goals(id,user_id,name,target_amount,saved_amount,target_date) values(p_id,uid,btrim(p_name),target,saved,p_target_date) returning * into item;
  end if;
  return private.finish_mutation(uid,p_client_mutation_id,private.envelope(jsonb_build_object('id',item.id,'version',item.version)));
end;
$$;

create function public.api_delete_goal(p_client_mutation_id uuid, p_id uuid, p_expected_version integer)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id(); gate record; item public.savings_goals%rowtype;
begin
  select * into gate from private.start_mutation(uid,p_client_mutation_id,'delete_goal',jsonb_build_object('id',p_id,'version',p_expected_version));
  if not gate.is_new then return gate.cached_response; end if;
  select * into item from public.savings_goals where id=p_id and user_id=uid for update;
  if not found then perform private.raise_app_error('NOT_FOUND','Goal tidak ditemukan.'); end if;
  if item.version is distinct from p_expected_version then perform private.raise_app_error('CONFLICT_VERSION','Goal sudah berubah.'); end if;
  delete from public.savings_goals where id=p_id and user_id=uid;
  return private.finish_mutation(uid,p_client_mutation_id,private.envelope(jsonb_build_object('id',p_id)));
end;
$$;

create function public.api_calculate_item_split(p_item_split jsonb, p_member_ids jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare
  line jsonb; allocation jsonb; member_id text; seen_ids text[] := '{}'; allocation_ids text[];
  quantities integer; quantity integer; price bigint; subtotal bigint := 0; total bigint; tax bigint; service bigint; discount bigint;
  shares jsonb := '{}'; bases jsonb := '{}'; assigned bigint := 0; amount bigint; remainder_count integer; candidate record;
begin
  if jsonb_typeof(p_member_ids) is distinct from 'array' or jsonb_array_length(p_member_ids) not between 2 and 20
    or jsonb_typeof(p_item_split->'items') is distinct from 'array' or jsonb_array_length(p_item_split->'items') not between 1 and 100 then
    perform private.raise_app_error('VALIDATION','Diperlukan 2–20 peserta dan 1–100 menu.');
  end if;
  if exists(select 1 from jsonb_array_elements(p_member_ids) where jsonb_typeof(value) is distinct from 'string') then
    perform private.raise_app_error('VALIDATION','ID peserta harus string.');
  end if;
  for member_id in select jsonb_array_elements_text(p_member_ids) loop
    if member_id is null or length(member_id)=0 or bases ? member_id then perform private.raise_app_error('VALIDATION','ID peserta harus unik.'); end if;
    bases := bases || jsonb_build_object(member_id,'0');
  end loop;
  for line in select value from jsonb_array_elements(p_item_split->'items') loop
    if jsonb_typeof(line->'unitPrice') is distinct from 'string' or jsonb_typeof(line->'id') is distinct from 'string'
      or jsonb_typeof(line->'name') is distinct from 'string' or length(btrim(coalesce(line->>'name',''))) not between 1 and 160
      or coalesce(line->>'id','')='' or (line->>'id')=any(seen_ids)
      or jsonb_typeof(line->'quantity') is distinct from 'number' or coalesce(line->>'quantity','') !~ '^[1-9][0-9]{0,2}$'
      or jsonb_typeof(line->'allocations') is distinct from 'array' or jsonb_array_length(line->'allocations') > 20 then
      perform private.raise_app_error('VALIDATION','Menu, jumlah, harga atau pembagian tidak valid.');
    end if;
    seen_ids := array_append(seen_ids,line->>'id'); quantity := (line->>'quantity')::integer; price := private.parse_money(line->>'unitPrice');
    subtotal := subtotal + price * quantity;
    if subtotal > 999999999999 then perform private.raise_app_error('VALIDATION','Total menu melebihi batas.'); end if;
    quantities := 0; allocation_ids := '{}';
    for allocation in select value from jsonb_array_elements(line->'allocations') loop
      member_id := allocation->>'memberID';
      if jsonb_typeof(allocation->'memberID') is distinct from 'string' or member_id is null or not bases ? member_id or member_id=any(allocation_ids)
        or jsonb_typeof(allocation->'quantity') is distinct from 'number' or coalesce(allocation->>'quantity','') !~ '^(0|[1-9][0-9]{0,2})$' then
        perform private.raise_app_error('VALIDATION','Pembagian menu per peserta tidak valid.');
      end if;
      allocation_ids := array_append(allocation_ids,member_id); quantities := quantities + (allocation->>'quantity')::integer;
      bases := bases || jsonb_build_object(member_id,((bases->>member_id)::bigint + price*(allocation->>'quantity')::integer)::text);
    end loop;
    if quantities <> quantity then perform private.raise_app_error('VALIDATION','Semua jumlah menu harus dibagikan tepat sekali.'); end if;
  end loop;
  if jsonb_typeof(p_item_split->'tax') is distinct from 'string' or jsonb_typeof(p_item_split->'service') is distinct from 'string' or jsonb_typeof(p_item_split->'discount') is distinct from 'string' then
    perform private.raise_app_error('VALIDATION','Pajak, layanan, diskon harus string Rupiah.');
  end if;
  tax := private.parse_money(p_item_split->>'tax',true); service := private.parse_money(p_item_split->>'service',true); discount := private.parse_money(p_item_split->>'discount',true);
  total := subtotal+tax+service;
  if total > 999999999999 or discount >= total then perform private.raise_app_error('VALIDATION','Total atau diskon tidak valid.'); end if;
  total := total-discount;
  for member_id in select jsonb_array_elements_text(p_member_ids) loop
    amount := floor((bases->>member_id)::numeric * total / subtotal)::bigint;
    shares := shares || jsonb_build_object(member_id,amount::text); assigned := assigned + amount;
  end loop;
  remainder_count := (total-assigned)::integer;
  for candidate in select value as id from jsonb_array_elements_text(p_member_ids) with ordinality
    order by mod((bases->>value)::numeric*total,subtotal) desc, ordinality asc limit remainder_count loop
    shares := shares || jsonb_build_object(candidate.id,((shares->>candidate.id)::bigint+1)::text);
  end loop;
  return jsonb_build_object('total',total::text,'shares',shares);
end;
$$;

create function public.api_save_item_split_bill(
  p_client_mutation_id uuid, p_total text, p_title text, p_payer_kind text, p_payer_member_id uuid,
  p_payer_account_id uuid, p_category_id uuid, p_occurred_at timestamptz, p_members jsonb, p_item_split jsonb,
  p_note text default null, p_split_bill_id uuid default null, p_expected_version integer default null,
  p_review_item_id uuid default null, p_transaction_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id(); gate record; calculated jsonb; member jsonb; response jsonb; bill_id uuid;
  inner_id uuid := md5(p_client_mutation_id::text || ':items-ledger')::uuid;
begin
  select * into gate from private.start_mutation(uid,p_client_mutation_id,'save_item_split_bill',jsonb_build_object('total',p_total,'title',p_title,'payer',p_payer_kind,'payer_member',p_payer_member_id,'account',p_payer_account_id,'category',p_category_id,'date',p_occurred_at,'members',p_members,'items',p_item_split,'note',p_note,'bill',p_split_bill_id,'version',p_expected_version,'review',p_review_item_id,'transaction',p_transaction_id));
  if not gate.is_new then return gate.cached_response; end if;
  if num_nonnulls(p_split_bill_id,p_review_item_id,p_transaction_id)>1 then perform private.raise_app_error('VALIDATION','Pilih satu sumber split bill.'); end if;
  if (p_split_bill_id is not null or p_transaction_id is not null) and (p_expected_version is null or p_expected_version < 1) then perform private.raise_app_error('VALIDATION','Versi sumber wajib diisi.'); end if;
  calculated := public.api_calculate_item_split(p_item_split,(select jsonb_agg(value->>'id' order by ordinality) from jsonb_array_elements(p_members) with ordinality));
  if calculated->>'total' is distinct from p_total then perform private.raise_app_error('VALIDATION','Total menu tidak sesuai total tagihan.'); end if;
  for member in select value from jsonb_array_elements(p_members) loop
    if jsonb_typeof(member->'share_amount') is distinct from 'string' or member->>'share_amount' is distinct from calculated->'shares'->>(member->>'id') then perform private.raise_app_error('VALIDATION','Porsi peserta tidak sesuai hasil perhitungan server.'); end if;
  end loop;
  select jsonb_agg(jsonb_set(value,'{id}',to_jsonb((value->>'id')::uuid::text)) order by ordinality)
    into p_members from jsonb_array_elements(p_members) with ordinality;
  select jsonb_set(p_item_split,'{items}',jsonb_agg(jsonb_set(line.value,'{allocations}',coalesce((
      select jsonb_agg(jsonb_set(allocation.value,'{memberID}',to_jsonb((allocation.value->>'memberID')::uuid::text)) order by allocation.ordinality)
      from jsonb_array_elements(line.value->'allocations') with ordinality as allocation(value,ordinality)
    ),'[]'::jsonb)) order by line.ordinality))
    into p_item_split from jsonb_array_elements(p_item_split->'items') with ordinality as line(value,ordinality);
  perform public.api_calculate_item_split(p_item_split,(select jsonb_agg(value->>'id' order by ordinality) from jsonb_array_elements(p_members) with ordinality));
  if p_split_bill_id is not null then
    if exists(select 1 from public.split_settlements where user_id=uid and split_bill_id=p_split_bill_id and reversed_at is null)
      or exists(select 1 from public.split_resolutions where user_id=uid and split_bill_id=p_split_bill_id and reversed_at is null) then
      if (select item_split from public.split_bills where id=p_split_bill_id and user_id=uid) is distinct from p_item_split then perform private.raise_app_error('STRUCTURE_LOCKED','Menu dikunci setelah pelunasan.'); end if;
    end if;
    response := public.api_update_split_bill(inner_id,p_split_bill_id,p_expected_version,p_total,p_title,p_payer_kind,p_payer_member_id,p_payer_account_id,p_category_id,p_occurred_at,p_members,p_note);
  elsif p_review_item_id is not null then
    response := public.api_create_split_bill_from_review(inner_id,p_review_item_id,p_total,p_title,p_payer_kind,p_payer_member_id,p_payer_account_id,p_category_id,p_occurred_at,p_members,p_note);
  elsif p_transaction_id is not null then
    response := public.api_convert_transaction_to_split_bill(inner_id,p_transaction_id,p_expected_version,p_total,p_title,p_payer_kind,p_payer_member_id,p_payer_account_id,p_category_id,p_occurred_at,p_members,p_note);
  else
    response := public.api_create_split_bill(inner_id,p_total,p_title,p_payer_kind,p_payer_member_id,p_payer_account_id,p_category_id,p_occurred_at,p_members,p_note);
  end if;
  bill_id := (response->'data'->>'id')::uuid;
  update public.split_bills set item_split=p_item_split where id=bill_id and user_id=uid;
  response := jsonb_set(response,'{data,version}',to_jsonb((select version from public.split_bills where id=bill_id and user_id=uid)));
  return private.finish_mutation(uid,p_client_mutation_id,response);
end;
$$;

revoke all on function public.api_save_goal(uuid,uuid,text,text,text,date,integer), public.api_delete_goal(uuid,uuid,integer), public.api_calculate_item_split(jsonb,jsonb), public.api_save_item_split_bill(uuid,text,text,text,uuid,uuid,uuid,timestamptz,jsonb,jsonb,text,uuid,integer,uuid,uuid) from public, anon;
grant execute on function public.api_save_goal(uuid,uuid,text,text,text,date,integer), public.api_delete_goal(uuid,uuid,integer), public.api_calculate_item_split(jsonb,jsonb), public.api_save_item_split_bill(uuid,text,text,text,uuid,uuid,uuid,timestamptz,jsonb,jsonb,text,uuid,integer,uuid,uuid) to authenticated;

create function private.check_item_split_consistency()
returns trigger language plpgsql security definer set search_path = public, private, pg_temp as $$
declare bill_id uuid; bill public.split_bills%rowtype; calculated jsonb; member record;
begin
  if tg_table_name='split_members' then bill_id := coalesce(new.split_bill_id,old.split_bill_id);
  else bill_id := coalesce(new.id,old.id); end if;
  select * into bill from public.split_bills where id=bill_id;
  if not found or bill.item_split is null then return null; end if;
  calculated := public.api_calculate_item_split(bill.item_split,(select jsonb_agg(id::text order by sort_order) from public.split_members where split_bill_id=bill_id));
  if calculated->>'total' <> bill.total::text then perform private.raise_app_error('VALIDATION','Total menu tidak sesuai tagihan.'); end if;
  for member in select id,share_amount from public.split_members where split_bill_id=bill_id loop
    if calculated->'shares'->>member.id::text is distinct from member.share_amount::text then perform private.raise_app_error('VALIDATION','Porsi menu harus sesuai perhitungan server.'); end if;
  end loop;
  return null;
end;
$$;
create constraint trigger split_item_bill_consistency after insert or update on public.split_bills deferrable initially deferred for each row execute function private.check_item_split_consistency();
create constraint trigger split_item_member_consistency after insert or update or delete on public.split_members deferrable initially deferred for each row execute function private.check_item_split_consistency();

create function private.validate_budget_category()
returns trigger language plpgsql security definer set search_path = public, private, pg_temp as $$
begin
  if not exists(select 1 from public.categories where id=new.category_id and user_id=new.user_id and kind='expense' and archived_at is null) then
    perform private.raise_app_error('VALIDATION','Anggaran harus memakai kategori pengeluaran aktif milik akun.');
  end if;
  return new;
end;
$$;
create trigger budgets_expense_category before insert or update of category_id,limit_amount on public.budgets for each row execute function private.validate_budget_category();

commit;
