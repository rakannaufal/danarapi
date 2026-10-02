begin;

create function public.api_planning_history(p_goal_id uuid default null, p_category_id uuid default null, p_start timestamptz default null, p_end timestamptz default null, p_cursor_at timestamptz default null, p_cursor_id uuid default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare owner_id uuid := auth.uid(); result jsonb;
begin
  if (p_goal_id is null) = (p_category_id is null) or (p_category_id is not null and (p_start is null or p_end is null or p_end <= p_start)) or (p_cursor_at is null) <> (p_cursor_id is null) then
    raise exception using errcode = '22023', message = 'Filter riwayat tidak valid.';
  end if;
  select coalesce(jsonb_agg(to_jsonb(page) order by page."occurredAt" desc, page.id desc), '[]'::jsonb) into result from (
    select entry.id, entry.source_id as "sourceID", entry.source_kind as kind, entry.personal_expense_amount::text as amount, entry.occurred_at as "occurredAt", tx.merchant, tx.note
    from public.ledger_entries entry
    left join public.transactions tx on entry.source_kind = 'transaction' and entry.source_id = tx.id and tx.user_id = owner_id and tx.deleted_at is null
    where entry.user_id = owner_id and entry.reversed_at is null and entry.personal_expense_amount > 0
      and (p_goal_id is null or tx.goal_id = p_goal_id)
      and (p_category_id is null or entry.category_id = p_category_id)
      and (p_start is null or entry.occurred_at >= p_start) and (p_end is null or entry.occurred_at < p_end)
      and (p_cursor_at is null or (entry.occurred_at,entry.id) < (p_cursor_at,p_cursor_id))
    order by entry.occurred_at desc,entry.id desc limit 31
  ) page;
  return result;
end;
$$;
revoke all on function public.api_planning_history(uuid,uuid,timestamptz,timestamptz,timestamptz,uuid) from public, anon;
grant execute on function public.api_planning_history(uuid,uuid,timestamptz,timestamptz,timestamptz,uuid) to authenticated;

create function public.api_copy_budgets(p_from date,p_to date)
returns integer language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := private.current_user_id(); copied integer;
begin
  if p_from is null or p_to is null or p_from = p_to or extract(day from p_from) <> 1 or extract(day from p_to) <> 1 then
    raise exception using errcode = '22023', message = 'Pilih dua bulan berbeda.';
  end if;
  insert into public.budgets(user_id,category_id,month,limit_amount)
    select owner_id,source.category_id,p_to,source.limit_amount from public.budgets source
    join public.categories category on category.id = source.category_id and category.user_id = owner_id and category.archived_at is null
    where source.user_id = owner_id and source.month = p_from
    on conflict(user_id,category_id,month) do nothing;
  get diagnostics copied = row_count;
  return copied;
end;
$$;
revoke all on function public.api_copy_budgets(date,date) from public, anon;
grant execute on function public.api_copy_budgets(date,date) to authenticated;

commit;
