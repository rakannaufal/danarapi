begin;

alter table public.review_items drop constraint review_items_status_check;
alter table public.review_items add constraint review_items_status_check
  check (status in ('pending', 'saved', 'rejected', 'merged', 'expired'));

create table public.retention_notices (
  user_id uuid primary key references auth.users(id) on delete cascade,
  policy_version text not null default 'r1-30-90-v1',
  received_at timestamptz not null default now()
);
alter table public.retention_notices enable row level security;
create policy retention_notice_owner_select on public.retention_notices
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.retention_notices to authenticated;

create function public.acknowledge_retention_policy()
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.retention_notices(user_id) values (private.current_user_id())
    on conflict (user_id) do nothing;
end;
$$;
revoke all on function public.acknowledge_retention_policy() from public, anon;
grant execute on function public.acknowledge_retention_policy() to authenticated;

drop policy review_items_owner_update on public.review_items;
create policy review_items_owner_update on public.review_items for update to authenticated
  using (user_id = (select auth.uid()) and status <> 'expired')
  with check (user_id = (select auth.uid()) and status <> 'expired');
drop policy review_items_owner_delete on public.review_items;
create policy review_items_owner_delete on public.review_items for delete to authenticated
  using (user_id = (select auth.uid()) and status <> 'expired');

create function public.claim_expired_reviews(p_limit integer default 50)
returns table(id uuid, storage_keys jsonb)
language plpgsql security definer set search_path = public, pg_temp as $$
declare selected_ids uuid[];
begin
  if p_limit not between 1 and 100 then raise exception 'Invalid retention batch limit'; end if;
  select array_agg(candidate.id) into selected_ids from (
    select review.id from public.review_items review
    where review.status = 'expired'
      or (review.status = 'rejected' and review.rejected_at <= now() - interval '30 days')
      or (review.status = 'pending' and review.created_at <= now() - interval '90 days'
        and exists (select 1 from public.retention_notices notice where notice.user_id = review.user_id
          and notice.received_at <= now() - interval '7 days'))
    order by review.created_at, review.id limit p_limit for update of review skip locked
  ) candidate;
  update public.review_items review set status = 'expired' where review.id = any(selected_ids);
  return query select review.id, coalesce(jsonb_agg(attachment.storage_key)
    filter (where attachment.id is not null), '[]'::jsonb)
    from public.review_items review left join public.attachments attachment on attachment.review_item_id = review.id
    where review.id = any(selected_ids) group by review.id;
end;
$$;

create function public.finish_expired_review(p_review_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform 1 from public.review_items where id = p_review_id and status = 'expired' for update;
  if not found then return; end if;
  delete from public.attachments where review_item_id = p_review_id;
  delete from public.review_items where id = p_review_id and status = 'expired';
end;
$$;
revoke all on function public.claim_expired_reviews(integer), public.finish_expired_review(uuid) from public, anon, authenticated;
grant execute on function public.claim_expired_reviews(integer), public.finish_expired_review(uuid) to service_role;

commit;
