begin;

create or replace function public.api_convert_transaction_to_split_bill(
  p_client_mutation_id uuid,
  p_transaction_id uuid,
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
  'transaction_id', p_transaction_id, 'expected_version', p_expected_version,
  'total', p_total, 'title', p_title, 'payer_kind', p_payer_kind,
  'payer_member_id', p_payer_member_id, 'payer_account_id', p_payer_account_id,
  'category_id', p_category_id, 'occurred_at', p_occurred_at, 'members', p_members, 'note', p_note
);
declare gate record;
declare source_transaction public.transactions%rowtype;
declare created_split_bill_id uuid;
declare response jsonb;
begin
  select * into gate from private.start_mutation(uid, p_client_mutation_id, 'convert_transaction_to_split_bill', payload);
  if not gate.is_new then return gate.cached_response; end if;

  select * into source_transaction from public.transactions
  where user_id = uid and id = p_transaction_id and deleted_at is null
  for update;
  if not found then perform private.raise_app_error('NOT_FOUND', 'Transaksi tidak ditemukan.'); end if;
  if source_transaction.version <> p_expected_version then perform private.raise_app_error('CONFLICT_VERSION', 'Versi transaksi telah berubah.'); end if;
  if source_transaction.type <> 'expense' then perform private.raise_app_error('VALIDATION', 'Hanya pengeluaran dapat dijadikan split bill.'); end if;

  response := public.api_create_split_bill(
    gen_random_uuid(), p_total, p_title, p_payer_kind, p_payer_member_id,
    p_payer_account_id, p_category_id, p_occurred_at, p_members, p_note
  );
  created_split_bill_id := (response->'data'->>'id')::uuid;

  update public.transactions set deleted_at = now() where id = source_transaction.id;
  update public.ledger_entries set reversed_at = now()
  where user_id = uid and source_kind = 'transaction' and source_id = source_transaction.id and reversed_at is null;
  update public.attachments set split_bill_id = created_split_bill_id, transaction_id = null
  where user_id = uid and transaction_id = source_transaction.id;

  response := jsonb_set(response, '{data,converted_transaction_id}', to_jsonb(source_transaction.id::text), true);
  return private.finish_mutation(uid, p_client_mutation_id, response);
end;
$$;

revoke all on function public.api_convert_transaction_to_split_bill(uuid,uuid,integer,text,text,text,uuid,uuid,uuid,timestamptz,jsonb,text) from public;
grant execute on function public.api_convert_transaction_to_split_bill(uuid,uuid,integer,text,text,text,uuid,uuid,uuid,timestamptz,jsonb,text) to authenticated;

commit;
