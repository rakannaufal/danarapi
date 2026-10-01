begin;

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

  response := public.api_create_transaction(
    p_client_mutation_id, p_type, p_amount, p_account_id, p_category_id,
    p_occurred_at, p_merchant, p_note, 'review'
  );
  created_transaction_id := (response->'data'->>'id')::uuid;

  if item.status = 'pending' then
    update public.attachments set transaction_id = created_transaction_id, review_item_id = null
    where user_id = uid and review_item_id = p_review_item_id;
    update public.review_items set status = 'saved', duplicate_of = null
    where user_id = uid and id = p_review_item_id;
  end if;
  return response;
end;
$$;

create or replace function public.api_merge_review_item(
  p_client_mutation_id uuid,
  p_review_item_id uuid,
  p_transaction_id uuid
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare payload jsonb := jsonb_build_object('review_item_id', p_review_item_id, 'transaction_id', p_transaction_id);
declare gate record;
declare item public.review_items%rowtype;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'merge_review_item', payload);
  if not gate.is_new then return gate.cached_response; end if;
  select * into item from public.review_items where user_id = uid and id = p_review_item_id and status = 'pending' for update;
  if not found then perform private.raise_app_error('CONFLICT_VERSION', 'Item tinjauan sudah diselesaikan.'); end if;
  if not exists (select 1 from public.transactions where user_id = uid and id = p_transaction_id and deleted_at is null) then
    perform private.raise_app_error('NOT_FOUND', 'Transaksi target tidak ditemukan.');
  end if;
  update public.attachments set transaction_id = p_transaction_id, review_item_id = null
  where user_id = uid and review_item_id = p_review_item_id;
  update public.review_items set status = 'merged', duplicate_of = p_transaction_id
  where user_id = uid and id = p_review_item_id;
  response := private.envelope(jsonb_build_object('id', p_review_item_id::text, 'transaction_id', p_transaction_id::text));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

create or replace function public.api_create_split_bill_from_review(
  p_client_mutation_id uuid,
  p_review_item_id uuid,
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
declare item public.review_items%rowtype;
declare created_split_bill_id uuid;
declare response jsonb;
begin
  select * into item from public.review_items
  where user_id = uid and id = p_review_item_id
  for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Item tinjauan tidak ditemukan.'); end if;
  if item.status not in ('pending', 'saved') then perform private.raise_app_error('CONFLICT_VERSION', 'Item tinjauan sudah diselesaikan dengan tindakan lain.'); end if;

  response := public.api_create_split_bill(
    p_client_mutation_id, p_total, p_title, p_payer_kind, p_payer_member_id,
    p_payer_account_id, p_category_id, p_occurred_at, p_members, p_note
  );
  created_split_bill_id := (response->'data'->>'id')::uuid;
  if item.status = 'pending' then
    update public.attachments set split_bill_id = created_split_bill_id, review_item_id = null
    where user_id = uid and review_item_id = p_review_item_id;
    update public.review_items set status = 'saved', duplicate_of = null
    where user_id = uid and id = p_review_item_id;
  end if;
  return response;
end;
$$;

revoke all on function public.api_confirm_review_item(uuid,uuid,text,text,uuid,uuid,timestamptz,text,text) from public;
grant execute on function public.api_confirm_review_item(uuid,uuid,text,text,uuid,uuid,timestamptz,text,text) to authenticated;
revoke all on function public.api_merge_review_item(uuid,uuid,uuid) from public;
grant execute on function public.api_merge_review_item(uuid,uuid,uuid) to authenticated;
revoke all on function public.api_create_split_bill_from_review(uuid,uuid,text,text,text,uuid,uuid,uuid,timestamptz,jsonb,text) from public;
grant execute on function public.api_create_split_bill_from_review(uuid,uuid,text,text,text,uuid,uuid,uuid,timestamptz,jsonb,text) to authenticated;

commit;
