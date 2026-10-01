\set ON_ERROR_STOP on
select set_config('test.item_fixture', :'item_fixture', false);
insert into public.categories(id,user_id,name,kind,archived_at) values
  ('36000000-0000-4000-8000-000000000001','15000000-0000-4000-8000-000000000001','Planning income','income',null),
  ('36000000-0000-4000-8000-000000000002','15000000-0000-4000-8000-000000000001','Planning archived','expense',now()),
  ('36000000-0000-4000-8000-000000000003','15000000-0000-4000-8000-000000000002','Planning foreign','expense',null);
set request.jwt.claims = '{"sub":"15000000-0000-4000-8000-000000000001","role":"authenticated"}';
set role authenticated;

do $$
declare fixture jsonb := current_setting('test.item_fixture')::jsonb; example jsonb; result jsonb; invalid jsonb; field_path text[];
begin
  for example in select value from jsonb_array_elements(fixture->'cases') loop
    result := public.api_calculate_item_split(example->'draft',example->'memberIDs');
    if result <> example->'expected' then raise exception 'Item fixture failed: %, got %',example->>'name',result; end if;
  end loop;
  invalid := fixture->'cases'->0->'draft';
  invalid := jsonb_set(invalid,'{items,0,allocations,0,quantity}','0');
  begin
    perform public.api_calculate_item_split(invalid,'["a","b","c"]');
    raise exception 'Unassigned quantities accepted';
  exception when sqlstate 'P0001' then if position('VALIDATION' in sqlerrm)=0 then raise; end if; end;
  foreach field_path slice 1 in array array[['items','0','id'],['items','0','name']] loop
    begin
      perform public.api_calculate_item_split(jsonb_set(fixture->'cases'->0->'draft',field_path,'42'),'["a","b","c"]');
      raise exception 'Numeric receipt identity accepted';
    exception when sqlstate 'P0001' then if position('VALIDATION' in sqlerrm)=0 then raise; end if; end;
  end loop;
  begin
    perform public.api_calculate_item_split(fixture->'cases'->0->'draft','[1,"b","c"]');
    raise exception 'Numeric participant identity accepted';
  exception when sqlstate 'P0001' then if position('VALIDATION' in sqlerrm)=0 then raise; end if; end;
end;
$$;

do $$
declare invalid_category uuid;
begin
  insert into public.budgets(user_id,category_id,month,limit_amount) values
    ('15000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001','2026-09-01',250000);
  foreach invalid_category in array array['36000000-0000-4000-8000-000000000001'::uuid,'36000000-0000-4000-8000-000000000002'::uuid,'36000000-0000-4000-8000-000000000003'::uuid] loop
    begin
      insert into public.budgets(user_id,category_id,month,limit_amount) values
        ('15000000-0000-4000-8000-000000000001',invalid_category,'2026-09-01',250000);
      raise exception 'Budget accepted income, archived or foreign category';
    exception when sqlstate 'P0001' then if position('VALIDATION' in sqlerrm)=0 then raise; end if; end;
  end loop;
end;
$$;

select public.api_save_goal('78000000-0000-4000-8000-000000000001','88000000-0000-4000-8000-000000000001','Laptop','15000000','0','2027-01-01',0);
select public.api_save_goal('78000000-0000-4000-8000-000000000001','88000000-0000-4000-8000-000000000001','Laptop','15000000','0','2027-01-01',0);
do $$ begin
  if (select count(*) from public.savings_goals) <> 1 then raise exception 'Goal retry duplicated'; end if;
  begin
    perform public.api_save_goal('78000000-0000-4000-8000-000000000002','88000000-0000-4000-8000-000000000001','Laptop','15000000','5000000',null,9);
    raise exception 'Goal stale update accepted';
  exception when sqlstate 'P0001' then if position('CONFLICT_VERSION' in sqlerrm)=0 then raise; end if; end;
end; $$;
set request.jwt.claims = '{"sub":"15000000-0000-4000-8000-000000000002","role":"authenticated"}';
do $$ begin if exists(select 1 from public.savings_goals) then raise exception 'Goal RLS leaked'; end if; end; $$;
reset role;
set request.jwt.claims = '{"sub":"15000000-0000-4000-8000-000000000001","role":"authenticated"}';
set role authenticated;

do $$
declare draft jsonb; members jsonb; response jsonb; retry jsonb; bill uuid; version integer;
begin
  draft := '{"items":[{"id":"meal","name":"Nasi","quantity":4,"unitPrice":"25000","allocations":[{"memberID":"68000000-0000-4000-8000-000000000001","quantity":1},{"memberID":"68000000-0000-4000-8000-000000000002","quantity":2},{"memberID":"68000000-0000-4000-8000-000000000003","quantity":1}]},{"id":"drink","name":"Minum","quantity":2,"unitPrice":"15000","allocations":[{"memberID":"68000000-0000-4000-8000-000000000001","quantity":1},{"memberID":"68000000-0000-4000-8000-000000000002","quantity":1}]}],"tax":"0","service":"0","discount":"0"}';
  members := '[{"id":"68000000-0000-4000-8000-000000000001","display_name":"Saya","is_self":true,"share_amount":"40000","sort_order":0},{"id":"68000000-0000-4000-8000-000000000002","display_name":"Ani","is_self":false,"share_amount":"65000","sort_order":1},{"id":"68000000-0000-4000-8000-000000000003","display_name":"Budi","is_self":false,"share_amount":"25000","sort_order":2}]';
  draft := replace(draft::text,'68000000-','69000000-')::jsonb;
  members := replace(members::text,'68000000-','69000000-')::jsonb;
  response := public.api_save_item_split_bill('79000000-0000-4000-8000-000000000001','130000','Makan per menu','self',null,'25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001',now(),members,draft);
  bill := (response->'data'->>'id')::uuid;
  retry := public.api_save_item_split_bill('79000000-0000-4000-8000-000000000001','130000','Makan per menu','self',null,'25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001',now(),members,draft);
  if retry <> response then raise exception 'Item bill retry changed response'; end if;
  if (select item_split from public.split_bills where id=bill) <> draft then raise exception 'Item detail not persisted'; end if;
  if (select sum(personal_expense_amount) from public.ledger_entries where source_id=bill and reversed_at is null) <> 40000 then raise exception 'Personal share ledger mismatch'; end if;
  begin
    perform public.api_save_item_split_bill('79000000-0000-4000-8000-000000000002','130000','Invalid shares','self',null,'25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001',now(),jsonb_set(members,'{0,share_amount}','"50000"'),draft);
    raise exception 'Tampered item shares accepted';
  exception when sqlstate 'P0001' then if position('VALIDATION' in sqlerrm)=0 then raise; end if; end;
  version := (response->'data'->>'version')::integer;
  response := public.api_save_item_split_bill('79000000-0000-4000-8000-000000000003','130000','Menu metadata','self',null,'25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001',now(),members,draft,'metadata',bill,version);
  version := (response->'data'->>'version')::integer;
  begin
    perform public.api_update_split_bill('79000000-0000-4000-8000-000000000007',bill,version,'130000','Tampered before settlement','self',null,'25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001',now(),jsonb_set(jsonb_set(members,'{0,share_amount}','"50000"'),'{1,share_amount}','"55000"'),null);
    set constraints all immediate;
    raise exception 'Legacy RPC bypassed item validation before settlement';
  exception when sqlstate 'P0001' then if position('VALIDATION' in sqlerrm)=0 then raise; end if; end;
  perform public.api_record_split_settlement('79000000-0000-4000-8000-000000000004',bill,'69000000-0000-4000-8000-000000000002','25000000-0000-4000-8000-000000000001','10000',now(),null);
  begin
    perform public.api_save_item_split_bill('79000000-0000-4000-8000-000000000005','130000','Invalid menu edit','self',null,'25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001',now(),members,jsonb_set(draft,'{items,0,name}','"Nasi diubah"'),null,bill,version);
    raise exception 'Item edit accepted after settlement';
  exception when sqlstate 'P0001' then if position('STRUCTURE_LOCKED' in sqlerrm)=0 then raise; end if; end;
  begin
    perform public.api_update_split_bill('79000000-0000-4000-8000-000000000006',bill,version,'130000','Tampered via old RPC','self',null,'25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001',now(),jsonb_set(jsonb_set(members,'{0,share_amount}','"50000"'),'{1,share_amount}','"55000"'),null);
    set constraints all immediate;
    raise exception 'Legacy RPC bypassed item validation';
  exception when sqlstate 'P0001' then if position('STRUCTURE_LOCKED' in sqlerrm)=0 and position('VALIDATION' in sqlerrm)=0 then raise; end if; end;
end;
$$;
do $$
declare draft jsonb; members jsonb; response jsonb; bill uuid;
begin
  select item_split into draft from public.split_bills where title='Menu metadata' and user_id='15000000-0000-4000-8000-000000000001';
  select jsonb_agg(jsonb_build_object('id',replace(id::text,'69000000-','ABCDEF00-'),'display_name',display_name,'is_self',is_self,'share_amount',share_amount::text,'sort_order',sort_order) order by sort_order)
    into members from public.split_members where split_bill_id=(select id from public.split_bills where title='Menu metadata' and user_id='15000000-0000-4000-8000-000000000001');
  draft := replace(draft::text,'69000000-','ABCDEF00-')::jsonb;
  response := public.api_save_item_split_bill('79000000-0000-4000-8000-000000000008','130000','Uppercase iOS UUID','self',null,'25000000-0000-4000-8000-000000000001','35000000-0000-4000-8000-000000000001',now(),members,draft);
  bill := (response->'data'->>'id')::uuid;
  set constraints all immediate;
  if (select item_split from public.split_bills where id=bill) <> replace(draft::text,'ABCDEF00-','abcdef00-')::jsonb then raise exception 'UUID allocations not canonicalized'; end if;
  if (select sum(personal_expense_amount) from public.ledger_entries where source_id=bill and reversed_at is null) <> 40000 then raise exception 'Uppercase UUID ledger mismatch'; end if;
end;
$$;
select 'Goals RLS/version/idempotency and shared item split fixtures/ledger passed' as result;
