begin;
create table private.receipt_scan_cache (
  user_id uuid not null references auth.users(id) on delete cascade,
  image_hash text not null check (image_hash ~ '^[0-9a-f]{64}$'),
  call_count integer not null default 0 check (call_count between 0 and 2),
  result jsonb,
  created_at timestamptz not null default clock_timestamp(),
  primary key (user_id,image_hash)
);
create table private.receipt_scan_daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  scans integer not null,
  primary key (user_id,day)
);
create table private.receipt_scan_queue (
  id boolean primary key default true check (id),
  next_call_at timestamptz not null default clock_timestamp()
);

create function public.claim_receipt_scan(p_user_id uuid,p_hash text,p_daily_limit integer)
returns jsonb language plpgsql security definer set search_path = private,public,pg_temp as $$
declare cached private.receipt_scan_cache%rowtype; count_today integer;
begin
  if p_daily_limit not between 1 and 10000 or p_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_config'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
  delete from private.receipt_scan_cache where created_at < clock_timestamp() - interval '24 hours';
  delete from private.receipt_scan_daily where day < (clock_timestamp() at time zone 'UTC')::date - 2;
  select * into cached from private.receipt_scan_cache where user_id=p_user_id and image_hash=p_hash;
  if found then
    if cached.result is not null then return jsonb_build_object('state','cached','result',cached.result); end if;
    if cached.created_at < clock_timestamp() - interval '5 minutes' then
      update private.receipt_scan_cache set result='{"status":"service_error"}'::jsonb where user_id=p_user_id and image_hash=p_hash;
      return jsonb_build_object('state','cached','result',jsonb_build_object('status','service_error'));
    end if;
    return jsonb_build_object('state','busy');
  end if;
  select scans into count_today from private.receipt_scan_daily where user_id=p_user_id and day=(clock_timestamp() at time zone 'UTC')::date;
  if coalesce(count_today,0) >= p_daily_limit then return jsonb_build_object('state','quota_exceeded'); end if;
  insert into private.receipt_scan_daily values(p_user_id,(clock_timestamp() at time zone 'UTC')::date,1)
    on conflict(user_id,day) do update set scans=receipt_scan_daily.scans+1;
  insert into private.receipt_scan_cache(user_id,image_hash) values(p_user_id,p_hash);
  return jsonb_build_object('state','new');
end;
$$;

create function public.reserve_receipt_scan_call(p_user_id uuid,p_hash text,p_interval_ms integer)
returns integer language plpgsql security definer set search_path = private,public,pg_temp as $$
declare next_time timestamptz; wait_ms integer;
begin
  if p_interval_ms not between 0 and 60000 then raise exception 'invalid_config'; end if;
  insert into private.receipt_scan_queue(id) values(true) on conflict(id) do nothing;
  select greatest(clock_timestamp(),next_call_at) into next_time from private.receipt_scan_queue where id for update;
  wait_ms := greatest(0,ceil(extract(epoch from (next_time-clock_timestamp()))*1000)::integer);
  if wait_ms > 20000 then raise exception 'queue_full'; end if;
  update private.receipt_scan_cache set call_count=call_count+1 where user_id=p_user_id and image_hash=p_hash and call_count < 2 and result is null;
  if not found then raise exception 'call_limit'; end if;
  update private.receipt_scan_queue set next_call_at=next_time + p_interval_ms * interval '1 millisecond' where id;
  return wait_ms;
end;
$$;

create function public.finish_receipt_scan(p_user_id uuid,p_hash text,p_result jsonb)
returns void language plpgsql security definer set search_path = private,public,pg_temp as $$
begin
  if octet_length(p_result::text) > 262144 then raise exception 'size_limit'; end if;
  update private.receipt_scan_cache set result=p_result where user_id=p_user_id and image_hash=p_hash and result is null;
end;
$$;
revoke all on function public.claim_receipt_scan(uuid,text,integer),public.reserve_receipt_scan_call(uuid,text,integer),public.finish_receipt_scan(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.claim_receipt_scan(uuid,text,integer),public.reserve_receipt_scan_call(uuid,text,integer),public.finish_receipt_scan(uuid,text,jsonb) to service_role;
commit;
