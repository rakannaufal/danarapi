begin;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists citext with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create domain public.idr_amount as bigint
  check (value >= 0 and value <= 999999999999);

create domain public.idr_positive as bigint
  check (value > 0 and value <= 999999999999);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  timezone text not null default 'Asia/Jakarta' check (length(timezone) between 1 and 64),
  locale text not null default 'id-ID' check (locale = 'id-ID'),
  theme text not null default 'system' check (theme in ('system', 'light', 'dark')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0)
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 80),
  kind text not null check (kind in ('cash', 'bank', 'ewallet', 'other')),
  opening_balance bigint not null default 0 check (abs(opening_balance) <= 999999999999),
  opened_at timestamptz not null,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  unique (user_id, id)
);

create unique index accounts_active_name_uidx
  on public.accounts (user_id, lower(btrim(name))) where archived_at is null;

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 80),
  kind text not null check (kind in ('income', 'expense')),
  system_key text,
  sort_order integer not null default 0 check (sort_order >= 0),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  unique (user_id, id)
);

create unique index categories_active_name_kind_uidx
  on public.categories (user_id, kind, lower(btrim(name))) where archived_at is null;
create unique index categories_system_key_uidx
  on public.categories (user_id, system_key) where system_key is not null;

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('income', 'expense')),
  status text not null default 'posted' check (status in ('draft', 'posted')),
  amount public.idr_positive not null,
  account_id uuid not null,
  category_id uuid not null,
  occurred_at timestamptz not null,
  merchant text check (merchant is null or length(merchant) <= 160),
  note text check (note is null or length(note) <= 1000),
  source text not null default 'manual' check (source in ('manual', 'review', 'qris', 'demo')),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  unique (user_id, id),
  foreign key (user_id, account_id) references public.accounts(user_id, id),
  foreign key (user_id, category_id) references public.categories(user_id, id)
);

create table public.transfers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  from_account_id uuid not null,
  to_account_id uuid not null,
  amount public.idr_positive not null,
  occurred_at timestamptz not null,
  note text check (note is null or length(note) <= 1000),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  unique (user_id, id),
  check (from_account_id <> to_account_id),
  foreign key (user_id, from_account_id) references public.accounts(user_id, id),
  foreign key (user_id, to_account_id) references public.accounts(user_id, id)
);

create table public.adjustments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null,
  signed_amount bigint not null check (signed_amount <> 0 and abs(signed_amount) <= 999999999999),
  reason text not null check (length(btrim(reason)) between 1 and 500),
  occurred_at timestamptz not null,
  reversed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  unique (user_id, id),
  foreign key (user_id, account_id) references public.accounts(user_id, id)
);

create table public.split_bills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  total public.idr_positive not null,
  title text not null check (length(btrim(title)) between 1 and 160),
  payer_kind text not null check (payer_kind in ('self', 'other')),
  payer_member_id uuid,
  payer_account_id uuid,
  category_id uuid not null,
  occurred_at timestamptz not null,
  note text check (note is null or length(note) <= 1000),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  unique (user_id, id),
  check ((payer_kind = 'self' and payer_account_id is not null and payer_member_id is null)
      or (payer_kind = 'other' and payer_account_id is null and payer_member_id is not null)),
  foreign key (user_id, payer_account_id) references public.accounts(user_id, id),
  foreign key (user_id, category_id) references public.categories(user_id, id)
);

create table public.split_members (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  split_bill_id uuid not null,
  display_name text not null check (length(btrim(display_name)) between 1 and 80),
  normalized_name text generated always as (lower(regexp_replace(btrim(display_name), '\s+', ' ', 'g'))) stored,
  is_self boolean not null default false,
  share_amount public.idr_amount not null,
  sort_order integer not null check (sort_order between 0 and 19),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  unique (user_id, id),
  unique (split_bill_id, normalized_name),
  unique (split_bill_id, sort_order),
  foreign key (user_id, split_bill_id) references public.split_bills(user_id, id) on delete cascade
);

alter table public.split_bills
  add constraint split_bills_payer_member_fk
  foreign key (user_id, payer_member_id) references public.split_members(user_id, id)
  deferrable initially deferred;

create unique index split_members_one_self_uidx
  on public.split_members(split_bill_id) where is_self;

create table public.split_settlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  split_bill_id uuid not null,
  member_id uuid not null,
  direction text not null check (direction in ('in', 'out')),
  account_id uuid not null,
  amount public.idr_positive not null,
  occurred_at timestamptz not null,
  note text check (note is null or length(note) <= 1000),
  reversed_at timestamptz,
  reversal_reason text check (reversal_reason is null or length(btrim(reversal_reason)) between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  unique (user_id, id),
  foreign key (user_id, split_bill_id) references public.split_bills(user_id, id),
  foreign key (user_id, member_id) references public.split_members(user_id, id),
  foreign key (user_id, account_id) references public.accounts(user_id, id),
  check ((reversed_at is null and reversal_reason is null) or (reversed_at is not null and reversal_reason is not null))
);

create table public.split_resolutions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  split_bill_id uuid not null,
  member_id uuid not null,
  kind text not null check (kind in ('receivable_writeoff', 'payable_forgiveness')),
  amount public.idr_positive not null,
  occurred_at timestamptz not null,
  reason text not null check (length(btrim(reason)) between 1 and 500),
  reversed_at timestamptz,
  reversal_reason text check (reversal_reason is null or length(btrim(reversal_reason)) between 1 and 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  unique (user_id, id),
  foreign key (user_id, split_bill_id) references public.split_bills(user_id, id),
  foreign key (user_id, member_id) references public.split_members(user_id, id),
  check ((reversed_at is null and reversal_reason is null) or (reversed_at is not null and reversal_reason is not null))
);

create table public.review_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null check (source in ('image', 'pdf_text', 'pasted_text', 'qris')),
  status text not null default 'pending' check (status in ('pending', 'saved', 'rejected', 'merged')),
  extracted_fields jsonb not null default '{}'::jsonb check (jsonb_typeof(extracted_fields) = 'object'),
  raw_reference text,
  duplicate_of uuid,
  rejected_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  unique (user_id, id),
  foreign key (user_id, duplicate_of) references public.transactions(user_id, id)
);

create table public.attachments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  transaction_id uuid,
  review_item_id uuid,
  split_bill_id uuid,
  storage_key text not null check (storage_key like user_id::text || '/%'),
  mime text not null check (mime in ('image/jpeg', 'image/png', 'image/heic', 'application/pdf')),
  size_bytes integer not null check (size_bytes between 1 and 5242880),
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  unique (user_id, id),
  check (num_nonnulls(transaction_id, review_item_id, split_bill_id) = 1),
  foreign key (user_id, transaction_id) references public.transactions(user_id, id),
  foreign key (user_id, review_item_id) references public.review_items(user_id, id),
  foreign key (user_id, split_bill_id) references public.split_bills(user_id, id)
);

create table public.merchant_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  match_type text not null check (match_type in ('exact', 'contains', 'prefix')),
  normalized_pattern text not null check (length(btrim(normalized_pattern)) between 1 and 160),
  category_id uuid not null,
  priority integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  unique (user_id, id),
  foreign key (user_id, category_id) references public.categories(user_id, id)
);

create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid not null,
  month date not null check (month = date_trunc('month', month)::date),
  limit_amount public.idr_positive not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1 check (version > 0),
  unique (user_id, id),
  unique (user_id, category_id, month),
  foreign key (user_id, category_id) references public.categories(user_id, id)
);

create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid,
  category_id uuid,
  source_kind text not null check (source_kind in ('transaction', 'transfer', 'adjustment', 'split_bill', 'split_settlement', 'split_resolution')),
  source_id uuid not null,
  leg text not null,
  occurred_at timestamptz not null,
  cash_amount bigint not null default 0 check (abs(cash_amount) <= 999999999999),
  personal_income_amount bigint not null default 0 check (personal_income_amount between 0 and 999999999999),
  personal_expense_amount bigint not null default 0 check (personal_expense_amount between 0 and 999999999999),
  receivable_delta bigint not null default 0 check (abs(receivable_delta) <= 999999999999),
  payable_delta bigint not null default 0 check (abs(payable_delta) <= 999999999999),
  is_non_cash boolean not null default false,
  reversed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, source_kind, source_id, leg),
  foreign key (user_id, account_id) references public.accounts(user_id, id),
  foreign key (user_id, category_id) references public.categories(user_id, id),
  check (cash_amount <> 0 or personal_income_amount <> 0 or personal_expense_amount <> 0 or receivable_delta <> 0 or payable_delta <> 0)
);

create table public.mutation_receipts (
  user_id uuid not null references auth.users(id) on delete cascade,
  client_mutation_id uuid not null,
  operation text not null,
  payload_hash text not null check (payload_hash ~ '^[a-f0-9]{64}$'),
  response jsonb,
  applied_at timestamptz not null default now(),
  primary key (user_id, client_mutation_id)
);

create index transactions_user_occurred_idx on public.transactions(user_id, occurred_at desc, id desc) where deleted_at is null;
create index transfers_user_occurred_idx on public.transfers(user_id, occurred_at desc, id desc) where deleted_at is null;
create index split_bills_user_occurred_idx on public.split_bills(user_id, occurred_at desc, id desc) where deleted_at is null;
create index ledger_entries_user_occurred_idx on public.ledger_entries(user_id, occurred_at desc, id desc) where reversed_at is null;
create index settlements_bill_member_idx on public.split_settlements(split_bill_id, member_id) where reversed_at is null;
create index resolutions_bill_member_idx on public.split_resolutions(split_bill_id, member_id) where reversed_at is null;

create or replace function private.touch_version()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.updated_at := now();
  new.version := old.version + 1;
  return new;
end;
$$;

create or replace function private.reject_user_change()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if new.user_id <> old.user_id then
    raise exception using errcode = 'P0001', message = '{"code":"FORBIDDEN","message":"Pemilik data tidak dapat diubah."}';
  end if;
  return new;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array['profiles','accounts','categories','transactions','transfers','adjustments','split_bills','split_members','split_settlements','split_resolutions','review_items','merchant_rules','budgets']
  loop
    execute format('create trigger %I_touch before update on public.%I for each row execute function private.touch_version()', table_name, table_name);
    execute format('create trigger %I_owner before update on public.%I for each row execute function private.reject_user_change()', table_name, table_name);
  end loop;
end;
$$;

create or replace function private.validate_split_bill(p_bill_id uuid)
returns void language plpgsql set search_path = public, pg_temp as $$
declare
  bill_total bigint;
  member_count integer;
  self_count integer;
  share_total bigint;
  payer_kind_value text;
  payer_member uuid;
  payer_is_self boolean;
begin
  select total, payer_kind, payer_member_id into bill_total, payer_kind_value, payer_member
  from public.split_bills where id = p_bill_id and deleted_at is null;
  if not found then return; end if;

  select count(*), count(*) filter (where is_self), coalesce(sum(share_amount), 0)
  into member_count, self_count, share_total
  from public.split_members where split_bill_id = p_bill_id;

  if member_count < 2 or member_count > 20 or self_count <> 1 or share_total <> bill_total or share_total <= 0 then
    raise exception using errcode = '23514', message = 'split_bill_members_invalid';
  end if;

  if payer_kind_value = 'other' then
    select is_self into payer_is_self from public.split_members where id = payer_member and split_bill_id = p_bill_id;
    if payer_is_self is distinct from false then
      raise exception using errcode = '23514', message = 'split_bill_payer_invalid';
    end if;
  end if;
end;
$$;

create or replace function private.validate_split_bill_trigger()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  perform private.validate_split_bill(coalesce(new.split_bill_id, old.split_bill_id));
  return null;
end;
$$;

create constraint trigger split_members_validate
after insert or update or delete on public.split_members
deferrable initially deferred for each row execute function private.validate_split_bill_trigger();

create or replace function private.validate_split_bill_row_trigger()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  perform private.validate_split_bill(new.id);
  return null;
end;
$$;

create constraint trigger split_bills_validate
after insert or update of total, payer_kind, payer_member_id on public.split_bills
deferrable initially deferred for each row execute function private.validate_split_bill_row_trigger();

create or replace view public.split_obligations
with (security_invoker = true) as
select
  b.user_id,
  b.id as split_bill_id,
  m.id as member_id,
  'receivable'::text as obligation_kind,
  m.share_amount as original_amount,
  coalesce((select sum(s.amount) from public.split_settlements s where s.split_bill_id = b.id and s.member_id = m.id and s.reversed_at is null), 0) as settled_amount,
  coalesce((select sum(r.amount) from public.split_resolutions r where r.split_bill_id = b.id and r.member_id = m.id and r.reversed_at is null), 0) as resolved_amount
from public.split_bills b
join public.split_members m on m.split_bill_id = b.id and not m.is_self
where b.payer_kind = 'self' and b.deleted_at is null
union all
select
  b.user_id,
  b.id,
  payer.id,
  'payable'::text,
  self_member.share_amount,
  coalesce((select sum(s.amount) from public.split_settlements s where s.split_bill_id = b.id and s.member_id = payer.id and s.reversed_at is null), 0),
  coalesce((select sum(r.amount) from public.split_resolutions r where r.split_bill_id = b.id and r.member_id = payer.id and r.reversed_at is null), 0)
from public.split_bills b
join public.split_members payer on payer.id = b.payer_member_id
join public.split_members self_member on self_member.split_bill_id = b.id and self_member.is_self
where b.payer_kind = 'other' and b.deleted_at is null;

create or replace view public.split_bill_summaries
with (security_invoker = true) as
select
  b.user_id,
  b.id,
  b.total,
  b.title,
  b.payer_kind,
  b.occurred_at,
  b.version,
  coalesce(sum(o.original_amount), 0)::bigint as obligation_amount,
  coalesce(sum(o.settled_amount), 0)::bigint as settled_amount,
  coalesce(sum(o.resolved_amount), 0)::bigint as resolved_amount,
  coalesce(sum(o.original_amount - o.settled_amount - o.resolved_amount), 0)::bigint as remaining_amount,
  case
    when coalesce(sum(o.original_amount - o.settled_amount - o.resolved_amount), 0) = 0 then 'settled'
    when coalesce(sum(o.settled_amount + o.resolved_amount), 0) > 0 then 'partially_settled'
    else 'unsettled'
  end as status
from public.split_bills b
left join public.split_obligations o on o.split_bill_id = b.id
where b.deleted_at is null
group by b.user_id, b.id;

create or replace view public.account_balances
with (security_invoker = true) as
select
  a.user_id,
  a.id as account_id,
  a.name,
  a.opening_balance + coalesce(sum(le.cash_amount) filter (where le.reversed_at is null), 0)::bigint as balance
from public.accounts a
left join public.ledger_entries le on le.user_id = a.user_id and le.account_id = a.id
group by a.user_id, a.id;

create or replace view public.financial_overview
with (security_invoker = true) as
select
  p.user_id,
  coalesce((select sum(ab.balance) from public.account_balances ab where ab.user_id = p.user_id), 0)::bigint as account_balance,
  coalesce((select sum(greatest(o.original_amount - o.settled_amount - o.resolved_amount, 0)) from public.split_obligations o where o.user_id = p.user_id and o.obligation_kind = 'receivable'), 0)::bigint as receivables,
  coalesce((select sum(greatest(o.original_amount - o.settled_amount - o.resolved_amount, 0)) from public.split_obligations o where o.user_id = p.user_id and o.obligation_kind = 'payable'), 0)::bigint as payables,
  coalesce((select sum(ab.balance) from public.account_balances ab where ab.user_id = p.user_id), 0)::bigint
    + coalesce((select sum(greatest(o.original_amount - o.settled_amount - o.resolved_amount, 0)) from public.split_obligations o where o.user_id = p.user_id and o.obligation_kind = 'receivable'), 0)::bigint
    - coalesce((select sum(greatest(o.original_amount - o.settled_amount - o.resolved_amount, 0)) from public.split_obligations o where o.user_id = p.user_id and o.obligation_kind = 'payable'), 0)::bigint as net_position
from public.profiles p;

commit;
