begin;

create or replace function public.api_update_split_bill(
  p_client_mutation_id uuid,
  p_split_bill_id uuid,
  p_expected_version integer,
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
declare payload jsonb := jsonb_build_object(
  'id', p_split_bill_id, 'expected_version', p_expected_version, 'total', p_total,
  'title', p_title, 'payer_kind', p_payer_kind, 'payer_member_id', p_payer_member_id,
  'payer_account_id', p_payer_account_id, 'category_id', p_category_id,
  'occurred_at', p_occurred_at, 'members', p_members, 'note', p_note
);
declare gate record;
declare item public.split_bills%rowtype;
declare parsed_total bigint;
declare self_share bigint;
declare member_record jsonb;
declare active_events integer;
declare structural_change boolean;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'update_split_bill', payload);
  if not gate.is_new then return gate.cached_response; end if;

  select * into item from public.split_bills
  where user_id = uid and id = p_split_bill_id and deleted_at is null
  for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Split bill tidak ditemukan.'); end if;
  if item.version <> p_expected_version then perform private.raise_app_error('CONFLICT_VERSION', 'Versi split bill telah berubah.'); end if;

  parsed_total := private.parse_money(p_total);
  if p_payer_kind not in ('self', 'other') or jsonb_typeof(p_members) <> 'array' or jsonb_array_length(p_members) not between 2 and 20 then
    perform private.raise_app_error('VALIDATION', 'Struktur split bill tidak valid.');
  end if;
  if length(btrim(coalesce(p_title, ''))) not between 1 and 160 then perform private.raise_app_error('VALIDATION', 'Judul split bill wajib diisi.'); end if;

  select count(*) into active_events from (
    select id from public.split_settlements where split_bill_id = item.id and reversed_at is null
    union all
    select id from public.split_resolutions where split_bill_id = item.id and reversed_at is null
  ) active;

  structural_change := item.total <> parsed_total
    or item.payer_kind <> p_payer_kind
    or item.payer_member_id is distinct from p_payer_member_id
    or item.payer_account_id is distinct from p_payer_account_id
    or item.category_id <> p_category_id
    or item.occurred_at <> p_occurred_at
    or (select count(*) from public.split_members where split_bill_id = item.id) <> jsonb_array_length(p_members)
    or exists (
      select 1 from public.split_members current_member
      where current_member.split_bill_id = item.id and not exists (
        select 1 from jsonb_array_elements(p_members) incoming
        where (incoming->>'id')::uuid = current_member.id
          and incoming->>'display_name' = current_member.display_name
          and (incoming->>'is_self')::boolean = current_member.is_self
          and private.parse_money(incoming->>'share_amount', true) = current_member.share_amount
          and (incoming->>'sort_order')::integer = current_member.sort_order
      )
    );

  if active_events > 0 and structural_change then
    perform private.raise_app_error('STRUCTURE_LOCKED', 'Batalkan pelunasan atau penghapusan aktif sebelum mengubah struktur bill.');
  end if;

  if not structural_change then
    update public.split_bills set title = btrim(p_title), note = nullif(btrim(p_note), '')
    where id = item.id returning * into item;
    response := private.envelope(jsonb_build_object('id', item.id::text, 'version', item.version));
    return private.finish_mutation(uid, p_client_mutation_id, response);
  end if;

  perform private.assert_category(uid, p_category_id, 'expense');
  if p_payer_kind = 'self' then
    if p_payer_account_id is null or p_payer_member_id is not null then perform private.raise_app_error('VALIDATION', 'Akun pembayar wajib saat Saya membayar.'); end if;
    perform private.assert_account(uid, p_payer_account_id, p_occurred_at);
  elsif p_payer_account_id is not null or p_payer_member_id is null then
    perform private.raise_app_error('VALIDATION', 'Peserta pembayar wajib saat teman membayar.');
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_members) incoming
    join public.split_members existing on existing.id = (incoming->>'id')::uuid
    where existing.user_id <> uid or existing.split_bill_id <> item.id
  ) then perform private.raise_app_error('FORBIDDEN', 'ID peserta sudah digunakan oleh bill lain.'); end if;

  if exists (
    select 1 from public.split_members old_member
    where old_member.split_bill_id = item.id
      and not exists (select 1 from jsonb_array_elements(p_members) incoming where (incoming->>'id')::uuid = old_member.id)
      and (exists (select 1 from public.split_settlements where member_id = old_member.id)
        or exists (select 1 from public.split_resolutions where member_id = old_member.id))
  ) then perform private.raise_app_error('STRUCTURE_LOCKED', 'Peserta dengan riwayat tidak dapat dihapus. Buat bill pengganti.'); end if;

  update public.split_bills set
    total = parsed_total, title = btrim(p_title), payer_kind = p_payer_kind,
    payer_member_id = p_payer_member_id, payer_account_id = p_payer_account_id,
    category_id = p_category_id, occurred_at = p_occurred_at, note = nullif(btrim(p_note), '')
  where id = item.id returning * into item;

  for member_record in select value from jsonb_array_elements(p_members)
  loop
    insert into public.split_members(id, user_id, split_bill_id, display_name, is_self, share_amount, sort_order)
    values (
      (member_record->>'id')::uuid, uid, item.id, member_record->>'display_name',
      (member_record->>'is_self')::boolean, private.parse_money(member_record->>'share_amount', true),
      (member_record->>'sort_order')::integer
    )
    on conflict (id) do update set
      display_name = excluded.display_name,
      is_self = excluded.is_self,
      share_amount = excluded.share_amount,
      sort_order = excluded.sort_order;
  end loop;

  delete from public.split_members old_member
  where old_member.split_bill_id = item.id
    and not exists (select 1 from jsonb_array_elements(p_members) incoming where (incoming->>'id')::uuid = old_member.id);

  perform private.validate_split_bill(item.id);
  select share_amount into self_share from public.split_members where split_bill_id = item.id and is_self;
  delete from public.ledger_entries where user_id = uid and source_kind = 'split_bill' and source_id = item.id;
  if p_payer_kind = 'self' then
    insert into public.ledger_entries(user_id, account_id, category_id, source_kind, source_id, leg, occurred_at, cash_amount, personal_expense_amount, receivable_delta)
    values (uid, p_payer_account_id, p_category_id, 'split_bill', item.id, 'initial', p_occurred_at, -parsed_total, self_share, parsed_total - self_share);
  elsif self_share > 0 then
    insert into public.ledger_entries(user_id, category_id, source_kind, source_id, leg, occurred_at, personal_expense_amount, payable_delta)
    values (uid, p_category_id, 'split_bill', item.id, 'initial', p_occurred_at, self_share, self_share);
  end if;

  response := private.envelope(jsonb_build_object('id', item.id::text, 'total', item.total::text, 'self_share', self_share::text, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

revoke all on function public.api_update_split_bill(uuid,uuid,integer,text,text,text,uuid,uuid,uuid,timestamptz,jsonb,text) from public;
grant execute on function public.api_update_split_bill(uuid,uuid,integer,text,text,text,uuid,uuid,uuid,timestamptz,jsonb,text) to authenticated;

commit;
