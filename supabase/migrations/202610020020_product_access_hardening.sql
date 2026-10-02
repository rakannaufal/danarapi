begin;

revoke all on table public.ai_consents, public.support_tickets from public, anon;
revoke insert, update, delete, truncate, references, trigger on table public.ai_consents, public.support_tickets from authenticated;
grant select on table public.ai_consents, public.support_tickets to authenticated;
grant all on table public.ai_consents, public.support_tickets to service_role;

commit;
