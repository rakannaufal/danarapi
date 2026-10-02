begin;

create table public.ai_consents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  policy_version text not null check (length(policy_version) between 1 and 40),
  granted boolean not null,
  updated_at timestamptz not null default now()
);
alter table public.ai_consents enable row level security;
create policy ai_consent_owner_read on public.ai_consents for select to authenticated using (user_id = auth.uid());
grant select on public.ai_consents to authenticated;
grant all on public.ai_consents to service_role;
revoke insert, update, delete on public.ai_consents from anon, authenticated;

create function public.api_set_ai_consent(p_granted boolean, p_policy_version text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := private.current_user_id();
begin
  if p_granted is null or p_policy_version is distinct from '2026-10-02' then
    raise exception using errcode = '22023', message = 'Versi persetujuan tidak valid.';
  end if;
  insert into public.ai_consents(user_id, policy_version, granted) values(owner_id, p_policy_version, p_granted)
    on conflict(user_id) do update set policy_version = excluded.policy_version, granted = excluded.granted, updated_at = now();
  return jsonb_build_object('granted', p_granted, 'policyVersion', p_policy_version, 'updatedAt', now());
end;
$$;
revoke all on function public.api_set_ai_consent(boolean,text) from public, anon;
grant execute on function public.api_set_ai_consent(boolean,text) to authenticated;

create table public.support_tickets (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  topic text not null check (topic in ('login','scan','saldo','sinkronisasi','privasi','lainnya')),
  description text not null check (length(btrim(description)) between 10 and 4000),
  platform text not null check (platform in ('web','ios')),
  app_version text not null check (length(app_version) between 1 and 80),
  request_id uuid,
  status text not null default 'open' check (status in ('open','in_progress','resolved')),
  reply text check (length(reply) <= 4000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index support_owner_created on public.support_tickets(user_id,created_at desc);
alter table public.support_tickets enable row level security;
create policy support_owner_read on public.support_tickets for select to authenticated using(user_id = auth.uid());
grant select on public.support_tickets to authenticated;
grant all on public.support_tickets to service_role;
revoke insert, update, delete on public.support_tickets from anon, authenticated;

create function public.api_create_support_ticket(p_id uuid,p_topic text,p_description text,p_platform text,p_app_version text,p_request_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := private.current_user_id(); existing public.support_tickets;
begin
  perform pg_advisory_xact_lock(hashtextextended(owner_id::text || ':support',0));
  select * into existing from public.support_tickets where id = p_id;
  if found then
    if existing.user_id is distinct from owner_id or existing.topic is distinct from p_topic or existing.description is distinct from btrim(p_description) or existing.platform is distinct from p_platform or existing.app_version is distinct from p_app_version or existing.request_id is distinct from p_request_id then
      raise exception using errcode = '22023', message = 'Permintaan laporan berbeda.';
    end if;
    return existing.id;
  end if;
  if (select count(*) from public.support_tickets where user_id = owner_id and created_at >= now() - interval '1 day') >= 10 then
    raise exception using errcode = '22023', message = 'Batas laporan harian tercapai. Coba kembali nanti.';
  end if;
  insert into public.support_tickets(id,user_id,topic,description,platform,app_version,request_id)
    values(p_id,owner_id,p_topic,btrim(p_description),p_platform,p_app_version,p_request_id);
  return p_id;
end;
$$;
revoke all on function public.api_create_support_ticket(uuid,text,text,text,text,uuid) from public, anon;
grant execute on function public.api_create_support_ticket(uuid,text,text,text,text,uuid) to authenticated;

create function public.api_set_timezone(p_timezone text)
returns void language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := private.current_user_id();
begin
  if p_timezone is null or p_timezone not in ('Asia/Jakarta','Asia/Makassar','Asia/Jayapura','UTC') then
    raise exception using errcode = '22023', message = 'Zona waktu tidak valid.';
  end if;
  update public.profiles set timezone = p_timezone, updated_at = now(), version = version + 1 where user_id = owner_id;
  if not found then raise exception using errcode = '22023', message = 'Profil belum tersedia.'; end if;
end;
$$;
revoke all on function public.api_set_timezone(text) from public, anon;
grant execute on function public.api_set_timezone(text) to authenticated;

commit;
