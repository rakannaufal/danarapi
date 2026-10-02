\set ON_ERROR_STOP on
begin;
set local role anon;
do $$
begin
  begin perform 1 from public.ai_consents; raise exception 'anonymous consent read allowed'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.support_tickets; raise exception 'anonymous support read allowed'; exception when insufficient_privilege then null; end;
end;
$$;
reset role;
set request.jwt.claims = '{"sub":"15000000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

do $$
declare result jsonb; identifier uuid := gen_random_uuid(); baseline integer;
begin
  result := public.api_set_ai_consent(true,'2026-10-02');
  if result->>'granted' <> 'true' or result->>'policyVersion' <> '2026-10-02' then raise exception 'consent response mismatch'; end if;
  perform public.api_set_ai_consent(false,'2026-10-02');
  if (select granted from public.ai_consents) then raise exception 'consent revocation failed'; end if;
  begin perform public.api_set_ai_consent(true,'old-policy'); raise exception 'old policy accepted'; exception when invalid_parameter_value then null; end;
  begin update public.ai_consents set granted = true; raise exception 'direct consent mutation allowed'; exception when insufficient_privilege then null; end;
  select version into baseline from public.profiles where user_id = auth.uid();
  perform public.api_set_timezone('Asia/Jayapura');
  if not exists(select 1 from public.profiles where user_id = auth.uid() and timezone = 'Asia/Jayapura' and version = baseline + 1) then raise exception 'timezone update not versioned'; end if;
  begin perform public.api_set_timezone('invalid-zone'); raise exception 'invalid timezone accepted'; exception when invalid_parameter_value then null; end;
  perform public.api_create_support_ticket(identifier,'scan','Struk belum terbaca dengan benar','web','test');
  perform public.api_create_support_ticket(identifier,'scan','Struk belum terbaca dengan benar','web','test');
  if (select count(*) from public.support_tickets where id = identifier) <> 1 then raise exception 'ticket replay duplicated'; end if;
  begin perform public.api_create_support_ticket(identifier,'scan',null,'web','test'); raise exception 'changed ticket accepted'; exception when invalid_parameter_value then null; end;
  begin update public.support_tickets set status = 'resolved' where id = identifier; raise exception 'client changed support status'; exception when insufficient_privilege then null; end;
  for position in 2..10 loop perform public.api_create_support_ticket(gen_random_uuid(),'lainnya','Laporan sintetis tanpa data pribadi','ios','test'); end loop;
  begin perform public.api_create_support_ticket(gen_random_uuid(),'lainnya','Laporan melebihi batas harian','web','test'); raise exception 'support rate limit failed'; exception when invalid_parameter_value then null; end;
end;
$$;

do $$
declare goal_id uuid := gen_random_uuid(); result jsonb; next_page jsonb; oldest jsonb; source_category uuid := '35000000-0000-4000-8000-000000000001'; ledger_count integer; copied integer;
begin
  perform public.api_ensure_feature_categories();
  perform public.api_save_goal(gen_random_uuid(),goal_id,'Riwayat lengkap','1000000','0',null,0);
  for position in 1..35 loop
    perform public.api_create_transaction(gen_random_uuid(),'expense','100','25000000-0000-4000-8000-000000000001',source_category,'2026-10-01T00:00:00Z'::timestamptz + position * interval '1 minute','Kontribusi sintetis',null,'manual',goal_id);
  end loop;
  result := public.api_planning_history(goal_id);
  if jsonb_array_length(result) <> 31 or result->0->>'amount' <> '100' then raise exception 'history first page/decimal mismatch'; end if;
  oldest := result->29;
  next_page := public.api_planning_history(p_goal_id=>goal_id,p_cursor_at=>(oldest->>'occurredAt')::timestamptz,p_cursor_id=>(oldest->>'id')::uuid);
  if jsonb_array_length(next_page) <> 5 then raise exception 'history pagination lost/duplicated records'; end if;
  if jsonb_array_length(public.api_planning_history(gen_random_uuid())) <> 0 then raise exception 'unknown/foreign goal exposed records'; end if;
  begin perform public.api_planning_history(); raise exception 'unfiltered history allowed'; exception when invalid_parameter_value then null; end;
  insert into public.budgets(category_id,month,limit_amount) values(source_category,'2026-10-01',120000), (source_category,'2026-11-01',99000);
  select count(*) into ledger_count from public.ledger_entries;
  copied := public.api_copy_budgets('2026-10-01','2026-11-01');
  if copied <> 0 or (select limit_amount from public.budgets where category_id = source_category and month = '2026-11-01') <> 99000 then raise exception 'copy overwrote budget'; end if;
  copied := public.api_copy_budgets('2026-10-01','2026-12-01');
  if copied <> 1 or public.api_copy_budgets('2026-10-01','2026-12-01') <> 0 then raise exception 'budget replay duplicated'; end if;
  if (select count(*) from public.ledger_entries) <> ledger_count then raise exception 'budget copy changed cash ledger'; end if;
end;
$$;

set request.jwt.claims = '{"sub":"15000000-0000-4000-8000-000000000002","role":"authenticated"}';
do $$
begin
  if exists(select 1 from public.ai_consents) or exists(select 1 from public.support_tickets) then raise exception 'foreign private records visible'; end if;
  if public.api_copy_budgets('2026-10-01','2026-12-01') <> 0 then raise exception 'foreign budgets copied'; end if;
  if jsonb_array_length(public.api_planning_history(p_category_id=>'35000000-0000-4000-8000-000000000001',p_start=>'2026-10-01Z',p_end=>'2026-11-01Z')) <> 0 then raise exception 'foreign history visible'; end if;
end;
$$;
rollback;
\echo 'Product readiness: consent, owner isolation, support replay/rate limit, timezone, complete planning history and safe budget copy passed.'
