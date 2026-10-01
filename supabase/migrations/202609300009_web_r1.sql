alter table public.review_items add column if not exists duplicate_bill_id uuid;
alter table public.review_items add constraint review_items_duplicate_bill_owner
  foreign key (user_id, duplicate_bill_id) references public.split_bills(user_id, id);
alter table public.review_items add constraint review_items_duplicate_kind
  check (duplicate_of is null or duplicate_bill_id is null);

alter function private.validate_split_bill_trigger() security definer;
alter function private.validate_split_bill_row_trigger() security definer;
revoke all on function private.validate_split_bill_trigger() from public;
revoke all on function private.validate_split_bill_row_trigger() from public;

create unique index if not exists review_items_source_fingerprint_unique
  on public.review_items (user_id, (extracted_fields->>'fingerprint'))
  where extracted_fields->>'fingerprint' is not null;

create or replace function public.api_restore_transfer(
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
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'restore_transfer', payload);
  if not gate.is_new then return gate.cached_response; end if;
  select * into item from public.transfers where user_id = uid and id = p_transfer_id and deleted_at is not null for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Transfer terhapus tidak ditemukan.'); end if;
  if item.version <> p_expected_version then perform private.raise_app_error('CONFLICT_VERSION', 'Versi transfer telah berubah.'); end if;
  perform private.assert_account(uid, item.from_account_id, item.occurred_at);
  perform private.assert_account(uid, item.to_account_id, item.occurred_at);
  update public.transfers set deleted_at = null where id = p_transfer_id returning * into item;
  update public.ledger_entries set reversed_at = null where user_id = uid and source_kind = 'transfer' and source_id = p_transfer_id;
  response := private.envelope(jsonb_build_object('id', item.id::text, 'deleted_at', null, 'version', item.version));
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;
revoke all on function public.api_restore_transfer(uuid,uuid,integer) from public;
grant execute on function public.api_restore_transfer(uuid,uuid,integer) to authenticated;

create or replace function public.api_merge_review_item_to_bill(
  p_client_mutation_id uuid, p_review_item_id uuid, p_split_bill_id uuid
)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare uid uuid := private.current_user_id();
declare gate record;
declare item public.review_items%rowtype;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'merge_review_item_to_bill', jsonb_build_object('review_item_id',p_review_item_id,'split_bill_id',p_split_bill_id));
  if not gate.is_new then return gate.cached_response; end if;
  select * into item from public.review_items where user_id = uid and id = p_review_item_id and status = 'pending' for update;
  if not found then perform private.raise_app_error('CONFLICT_VERSION','Item tinjauan sudah diselesaikan.'); end if;
  perform 1 from public.split_bills where user_id = uid and id = p_split_bill_id and deleted_at is null for update;
  if not found then perform private.raise_app_error('NOT_FOUND','Tagihan target tidak ditemukan.'); end if;
  update public.attachments set split_bill_id = p_split_bill_id, review_item_id = null where user_id = uid and review_item_id = p_review_item_id;
  update public.review_items set status = 'merged', duplicate_of = null, duplicate_bill_id = p_split_bill_id where user_id = uid and id = p_review_item_id;
  response := private.envelope(jsonb_build_object('id',p_review_item_id::text,'split_bill_id',p_split_bill_id::text));
  return private.finish_mutation(uid,p_client_mutation_id,response);
end;
$$;
revoke all on function public.api_merge_review_item_to_bill(uuid,uuid,uuid) from public;
grant execute on function public.api_merge_review_item_to_bill(uuid,uuid,uuid) to authenticated;
