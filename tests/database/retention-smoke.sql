begin;
insert into auth.users(id, email) values ('ea000000-0000-4000-8000-000000000001', 'retention-one@example.invalid'), ('ea000000-0000-4000-8000-000000000002', 'retention-two@example.invalid');
insert into public.review_items(id, user_id, source, status, created_at, rejected_at) values
  ('eb000000-0000-4000-8000-000000000001', 'ea000000-0000-4000-8000-000000000001', 'pasted_text', 'rejected', now() - interval '40 days', now() - interval '31 days'),
  ('eb000000-0000-4000-8000-000000000002', 'ea000000-0000-4000-8000-000000000001', 'pasted_text', 'rejected', now() - interval '40 days', now() - interval '29 days'),
  ('eb000000-0000-4000-8000-000000000003', 'ea000000-0000-4000-8000-000000000001', 'pasted_text', 'pending', now() - interval '91 days', null),
  ('eb000000-0000-4000-8000-000000000004', 'ea000000-0000-4000-8000-000000000002', 'pasted_text', 'pending', now() - interval '100 days', null),
  ('eb000000-0000-4000-8000-000000000005', 'ea000000-0000-4000-8000-000000000001', 'pasted_text', 'saved', now() - interval '100 days', null),
  ('eb000000-0000-4000-8000-000000000006', 'ea000000-0000-4000-8000-000000000001', 'pasted_text', 'pending', now() - interval '89 days', null);
insert into public.retention_notices(user_id, received_at) values ('ea000000-0000-4000-8000-000000000001', now() - interval '8 days');
set local role service_role;
do $$ declare claimed_count integer;
begin
  select count(*) into claimed_count from public.claim_expired_reviews();
  if claimed_count <> 2 then raise exception 'Retention boundary/notice failed: %', claimed_count; end if;
end $$;
reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = 'ea000000-0000-4000-8000-000000000001';
do $$ begin
  begin perform public.claim_expired_reviews(); raise exception 'Owner invoked service-only cleanup';
  exception when insufficient_privilege then null; end;
  update public.review_items set status = 'pending' where id = 'eb000000-0000-4000-8000-000000000001';
  if found then raise exception 'Expired claim was restored'; end if;
  if (select count(*) from public.retention_notices) <> 1 then raise exception 'Notice RLS failed'; end if;
  perform public.acknowledge_retention_policy();
end $$;
reset role;
set local role service_role;
select public.finish_expired_review('eb000000-0000-4000-8000-000000000001');
select public.finish_expired_review('eb000000-0000-4000-8000-000000000001');
reset role;
do $$ begin
  if exists(select 1 from public.review_items where id = 'eb000000-0000-4000-8000-000000000001') then raise exception 'Expired review survived'; end if;
  if not exists(select 1 from public.review_items where id = 'eb000000-0000-4000-8000-000000000004' and status = 'pending') then raise exception 'Pending without notice removed'; end if;
end $$;
rollback;
