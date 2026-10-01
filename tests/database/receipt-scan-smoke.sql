begin;
select set_config('app.receipt_fixture', :'receipt_fixture', true);
do $$
declare result jsonb; draft jsonb; example jsonb; user_id uuid := '10000000-0000-4000-8000-000000000001';
begin
  draft := '{"items":[{"id":"beras","name":"Beras","quantity":4000,"unitPrice":"12500","allocations":[{"memberID":"a","quantity":1}]}],"discount":"0","settings":{"serviceRate":0,"taxRate":0,"taxOnService":false}}';
  if public.api_calculate_item_split(draft,'["a","b"]')->>'total' <> '50000000' then raise exception 'Wholesale shared quantity truncated'; end if;
  draft := jsonb_set(draft - 'settings','{items,0,allocations,0,quantity}','4000') || '{"tax":"0","service":"0"}';
  if public.api_calculate_item_split(draft,'["a","b"]')->>'total' <> '50000000' then raise exception 'Wholesale legacy quantity truncated'; end if;
  for example in select value from jsonb_array_elements(current_setting('app.receipt_fixture')::jsonb->'cases') loop
    result := public.api_calculate_item_split(example->'draft',example->'memberIDs');
    if result is distinct from example->'expected' then raise exception 'Receipt parity mismatch %: %',example->>'name',result; end if;
  end loop;
  draft := '{"items":[{"id":"shared","name":"Menu","quantity":1,"unitPrice":"10000","allocations":[{"memberID":"a","quantity":1},{"memberID":"b","quantity":1},{"memberID":"c","quantity":1}]}],"discount":"1000","rounding":"-1","settings":{"serviceRate":5,"taxRate":10,"taxOnService":false}}';
  result := public.api_calculate_item_split(draft,'["a","b","c"]');
  if result->>'total' <> '10349' then raise exception 'Discount calculation mismatch: %',result; end if;
  draft := jsonb_set(draft,'{settings,taxIncluded}','true');
  result := public.api_calculate_item_split(draft,'["a","b","c"]');
  if result->>'total' <> '8999' then raise exception 'Inclusive tax mismatch: %',result; end if;
  draft := jsonb_set(draft,'{rounding}','"1"');
  if public.api_calculate_item_split(draft,'["a","b","c"]')->>'total' <> '9001' then raise exception 'Positive rounding mismatch'; end if;
  if has_function_privilege('authenticated','public.claim_receipt_scan(uuid,text,integer)','EXECUTE') then raise exception 'Client must not claim scan cache'; end if;
  if public.claim_receipt_scan(user_id,repeat('a',64),1)->>'state' <> 'new' then raise exception 'Claim failed'; end if;
  if public.claim_receipt_scan(user_id,repeat('a',64),1)->>'state' <> 'busy' then raise exception 'Concurrent scan must be busy'; end if;
  perform public.reserve_receipt_scan_call(user_id,repeat('a',64),0);
  perform public.reserve_receipt_scan_call(user_id,repeat('a',64),0);
  begin perform public.reserve_receipt_scan_call(user_id,repeat('a',64),0); raise exception 'Third call incorrectly allowed'; exception when raise_exception then if sqlerrm <> 'call_limit' then raise; end if; end;
  perform public.finish_receipt_scan(user_id,repeat('a',64),'{"status":"ok"}');
  if public.claim_receipt_scan(user_id,repeat('a',64),1)->>'state' <> 'cached' then raise exception 'Cache miss'; end if;
  if public.claim_receipt_scan(user_id,repeat('b',64),1)->>'state' <> 'quota_exceeded' then raise exception 'Daily limit bypass'; end if;
end;
$$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$
declare
  owner_id uuid := '10000000-0000-4000-8000-000000000001';
  member_ids jsonb := '["36000000-0000-4000-8000-000000000001","36000000-0000-4000-8000-000000000002","36000000-0000-4000-8000-000000000003"]';
  draft jsonb; calculated jsonb; members jsonb; saved jsonb; bill_id uuid;
begin
  draft := jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id','shared','name','Menu','quantity',1,'unitPrice','10000','allocations',
    (select jsonb_agg(jsonb_build_object('memberID',value,'quantity',1)) from jsonb_array_elements_text(member_ids)))),
    'tax','0','service','0','discount','1000','rounding','-1','settings',jsonb_build_object('serviceRate',5,'taxRate',10,'taxOnService',false));
  calculated := public.api_calculate_item_split(draft,member_ids);
  select jsonb_agg(jsonb_build_object('id',value,'display_name','Peserta '||ordinality,'is_self',ordinality=1,'share_amount',calculated->'shares'->>value,'sort_order',ordinality-1) order by ordinality)
    into members from jsonb_array_elements_text(member_ids) with ordinality;
  saved := public.api_save_item_split_bill('76000000-0000-4000-8000-000000000099',calculated->>'total','Scan ledger test','self',null,
    (select id from public.accounts where user_id=owner_id and archived_at is null limit 1),
    (select id from public.categories where user_id=owner_id and kind='expense' and archived_at is null limit 1),now(),members,draft);
  bill_id := (saved->'data'->>'id')::uuid;
  set constraints all immediate;
  if (select total from public.split_bills where id=bill_id) <> 10349 then raise exception 'Saved shared receipt total mismatch'; end if;
  if (select item_split->>'rounding' from public.split_bills where id=bill_id) <> '-1' then raise exception 'Receipt metadata lost'; end if;
  if (select sum(share_amount) from public.split_members where split_bill_id=bill_id) <> 10349 then raise exception 'Stored shares mismatch'; end if;
end;
$$;
rollback;
