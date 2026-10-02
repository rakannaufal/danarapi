alter view public.savings_goal_progress set (security_invoker = true);
revoke all on public.savings_goal_progress from public, anon;
grant select on public.savings_goal_progress to authenticated;

do $$
declare routine record;
begin
  for routine in
    select procedure.oid::regprocedure as signature
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid=procedure.pronamespace
    where namespace.nspname='public' and procedure.proname ~ '^api_'
  loop
    execute format('revoke all on function %s from public, anon', routine.signature);
  end loop;
end;
$$;
