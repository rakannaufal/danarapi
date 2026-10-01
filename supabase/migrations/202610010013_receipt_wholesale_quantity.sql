begin;

create or replace function public.api_calculate_item_split_legacy(p_item_split jsonb, p_member_ids jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare
  line jsonb; allocation jsonb; member_id text; seen_ids text[] := '{}'; allocation_ids text[];
  quantities integer; quantity integer; price bigint; subtotal bigint := 0; total bigint; tax bigint; service bigint; discount bigint;
  shares jsonb := '{}'; bases jsonb := '{}'; assigned bigint := 0; amount bigint; remainder_count integer; candidate record;
begin
  if jsonb_typeof(p_member_ids) is distinct from 'array' or jsonb_array_length(p_member_ids) not between 2 and 20
    or jsonb_typeof(p_item_split->'items') is distinct from 'array' or jsonb_array_length(p_item_split->'items') not between 1 and 100 then
    perform private.raise_app_error('VALIDATION','Diperlukan 2–20 peserta dan 1–100 menu.');
  end if;
  if exists(select 1 from jsonb_array_elements(p_member_ids) where jsonb_typeof(value) is distinct from 'string') then
    perform private.raise_app_error('VALIDATION','ID peserta harus string.');
  end if;
  for member_id in select jsonb_array_elements_text(p_member_ids) loop
    if member_id is null or length(member_id)=0 or bases ? member_id then perform private.raise_app_error('VALIDATION','ID peserta harus unik.'); end if;
    bases := bases || jsonb_build_object(member_id,'0');
  end loop;
  for line in select value from jsonb_array_elements(p_item_split->'items') loop
    if jsonb_typeof(line->'unitPrice') is distinct from 'string' or jsonb_typeof(line->'id') is distinct from 'string'
      or jsonb_typeof(line->'name') is distinct from 'string' or length(btrim(coalesce(line->>'name',''))) not between 1 and 160
      or coalesce(line->>'id','')='' or (line->>'id')=any(seen_ids)
      or jsonb_typeof(line->'quantity') is distinct from 'number' or coalesce(line->>'quantity','') !~ '^[1-9][0-9]{0,5}$'
      or jsonb_typeof(line->'allocations') is distinct from 'array' or jsonb_array_length(line->'allocations') > 20 then
      perform private.raise_app_error('VALIDATION','Menu, jumlah, harga atau pembagian tidak valid.');
    end if;
    seen_ids := array_append(seen_ids,line->>'id'); quantity := (line->>'quantity')::integer; price := private.parse_money(line->>'unitPrice');
    subtotal := subtotal + price * quantity;
    if subtotal > 999999999999 then perform private.raise_app_error('VALIDATION','Total menu melebihi batas.'); end if;
    quantities := 0; allocation_ids := '{}';
    for allocation in select value from jsonb_array_elements(line->'allocations') loop
      member_id := allocation->>'memberID';
      if jsonb_typeof(allocation->'memberID') is distinct from 'string' or member_id is null or not bases ? member_id or member_id=any(allocation_ids)
        or jsonb_typeof(allocation->'quantity') is distinct from 'number' or coalesce(allocation->>'quantity','') !~ '^(0|[1-9][0-9]{0,5})$' then
        perform private.raise_app_error('VALIDATION','Pembagian menu per peserta tidak valid.');
      end if;
      allocation_ids := array_append(allocation_ids,member_id); quantities := quantities + (allocation->>'quantity')::integer;
      if quantities > quantity then perform private.raise_app_error('VALIDATION','Jumlah pembagian melebihi jumlah menu.'); end if;
      bases := bases || jsonb_build_object(member_id,((bases->>member_id)::bigint + price*(allocation->>'quantity')::integer)::text);
    end loop;
    if quantities <> quantity then perform private.raise_app_error('VALIDATION','Semua jumlah menu harus dibagikan tepat sekali.'); end if;
  end loop;
  if jsonb_typeof(p_item_split->'tax') is distinct from 'string' or jsonb_typeof(p_item_split->'service') is distinct from 'string' or jsonb_typeof(p_item_split->'discount') is distinct from 'string' then
    perform private.raise_app_error('VALIDATION','Pajak, layanan, diskon harus string Rupiah.');
  end if;
  tax := private.parse_money(p_item_split->>'tax',true); service := private.parse_money(p_item_split->>'service',true); discount := private.parse_money(p_item_split->>'discount',true);
  total := subtotal+tax+service;
  if total > 999999999999 or discount >= total then perform private.raise_app_error('VALIDATION','Total atau diskon tidak valid.'); end if;
  total := total-discount;
  for member_id in select jsonb_array_elements_text(p_member_ids) loop
    amount := floor((bases->>member_id)::numeric * total / subtotal)::bigint;
    shares := shares || jsonb_build_object(member_id,amount::text); assigned := assigned + amount;
  end loop;
  remainder_count := (total-assigned)::integer;
  for candidate in select value as id from jsonb_array_elements_text(p_member_ids) with ordinality
    order by mod((bases->>value)::numeric*total,subtotal) desc, ordinality asc limit remainder_count loop
    shares := shares || jsonb_build_object(candidate.id,((shares->>candidate.id)::bigint+1)::text);
  end loop;
  return jsonb_build_object('total',total::text,'shares',shares);
end;
$$;

create or replace function public.api_calculate_item_split(p_item_split jsonb, p_member_ids jsonb)
returns jsonb language plpgsql security definer set search_path = public, private, pg_temp as $$
declare
  settings jsonb := p_item_split->'settings';
  bases numeric[] := '{}'; values numeric[]; floors bigint[]; columns jsonb := '[]';
  member_ids text[]; seen_ids text[] := '{}'; owners text[];
  line jsonb; allocation jsonb; member_id text; candidate record;
  price bigint; quantity integer; amount numeric; service_rate numeric; tax_rate numeric;
  denominator numeric := 232792560; divisor numeric; target bigint; remaining integer;
  base_sum numeric; discount bigint; rounding bigint;
  position integer; column_index integer; shares jsonb := '{}'; total bigint := 0;
begin
  if settings is null or settings = 'null'::jsonb then return public.api_calculate_item_split_legacy(p_item_split,p_member_ids); end if;
  if jsonb_typeof(settings) <> 'object' or jsonb_typeof(settings->'serviceRate') is distinct from 'number'
    or jsonb_typeof(settings->'taxRate') is distinct from 'number' or jsonb_typeof(settings->'taxOnService') is distinct from 'boolean'
    or jsonb_typeof(p_member_ids) is distinct from 'array' or jsonb_array_length(p_member_ids) not between 2 and 20
    or jsonb_typeof(p_item_split->'items') is distinct from 'array' or jsonb_array_length(p_item_split->'items') not between 1 and 100 then
    perform private.raise_app_error('VALIDATION','Peserta, menu atau pengaturan tidak valid.');
  end if;
  service_rate := (settings->>'serviceRate')::numeric * 100;
  tax_rate := (settings->>'taxRate')::numeric * 100;
  if service_rate not between 0 and 10000 or tax_rate not between 0 and 10000 or service_rate <> trunc(service_rate) or tax_rate <> trunc(tax_rate) then
    perform private.raise_app_error('VALIDATION','Service dan pajak 0–100%, maksimal dua desimal.');
  end if;
  if exists(select 1 from jsonb_array_elements(p_member_ids) where jsonb_typeof(value) <> 'string' or value#>>'{}' = '') then
    perform private.raise_app_error('VALIDATION','ID peserta harus string.');
  end if;
  select array_agg(value order by ordinality) into member_ids from jsonb_array_elements_text(p_member_ids) with ordinality;
  if cardinality(member_ids) <> (select count(distinct value) from unnest(member_ids) value) then perform private.raise_app_error('VALIDATION','ID peserta harus unik.'); end if;
  bases := array_fill(0::numeric,array[cardinality(member_ids)]);
  for line in select value from jsonb_array_elements(p_item_split->'items') loop
    if jsonb_typeof(line->'id') is distinct from 'string' or coalesce(line->>'id','') = '' or (line->>'id') = any(seen_ids)
      or jsonb_typeof(line->'name') is distinct from 'string' or length(btrim(coalesce(line->>'name',''))) not between 1 and 160
      or jsonb_typeof(line->'quantity') is distinct from 'number' or coalesce(line->>'quantity','') !~ '^(0|[1-9][0-9]{0,5})$'
      or jsonb_typeof(line->'unitPrice') is distinct from 'string' or jsonb_typeof(line->'allocations') is distinct from 'array'
      or jsonb_array_length(line->'allocations') > 20 then perform private.raise_app_error('VALIDATION','Menu tidak valid.'); end if;
    seen_ids := array_append(seen_ids,line->>'id');
    price := private.parse_money(coalesce(nullif(line->>'unitPrice',''),'0'),true); quantity := (line->>'quantity')::integer;
    owners := '{}';
    for allocation in select value from jsonb_array_elements(line->'allocations') loop
      member_id := allocation->>'memberID';
      if jsonb_typeof(allocation->'memberID') is distinct from 'string' or member_id is null or not member_id = any(member_ids) or member_id = any(owners)
        or allocation->'quantity' is distinct from '1'::jsonb then perform private.raise_app_error('VALIDATION','Pemesan tidak valid.'); end if;
      owners := array_append(owners,member_id);
    end loop;
    if cardinality(owners) = 0 then
      if price * quantity > 0 then perform private.raise_app_error('VALIDATION','Menu belum memiliki pemesan.'); end if;
      continue;
    end if;
    foreach member_id in array owners loop
      position := array_position(member_ids,member_id);
      bases[position] := bases[position] + price::numeric * quantity * (denominator / cardinality(owners));
    end loop;
  end loop;
  select sum(value) into base_sum from unnest(bases) value;
  discount := private.parse_money(coalesce(nullif(p_item_split->>'discount',''),'0'),true);
  if coalesce(p_item_split->>'rounding','0') !~ '^-?(0|[1-9][0-9]{0,11})$' then perform private.raise_app_error('VALIDATION','Pembulatan tidak valid.'); end if;
  rounding := coalesce(p_item_split->>'rounding','0')::bigint;
  if base_sum <= 0 or base_sum / denominator > 999999999999 or discount * denominator > base_sum then perform private.raise_app_error('VALIDATION','Subtotal atau diskon tidak valid.'); end if;
  if p_item_split->'settings'->'taxIncluded' is not null and jsonb_typeof(p_item_split->'settings'->'taxIncluded') is distinct from 'boolean' then perform private.raise_app_error('VALIDATION','Pengaturan pajak tidak valid.'); end if;
  if coalesce((settings->>'taxIncluded')::boolean,false) then service_rate := 0; tax_rate := 0; end if;
  for column_index in 1..5 loop
    values := '{}'; floors := '{}';
    divisor := case column_index when 1 then denominator when 2 then base_sum when 3 then denominator * base_sum * 10000 when 4 then denominator * base_sum * 100000000 else base_sum end;
    foreach amount in array bases loop
      amount := case column_index when 1 then amount when 2 then amount * discount
        when 3 then amount * (base_sum - discount * denominator) * service_rate
        when 4 then amount * (base_sum - discount * denominator) * (case when (settings->>'taxOnService')::boolean then 10000 + service_rate else 10000 end) * tax_rate
        else amount * abs(rounding) end;
      values := array_append(values,amount); floors := array_append(floors,floor(amount / divisor)::bigint);
    end loop;
    select round(sum(value) / divisor)::bigint into target from unnest(values) value;
    select (target - sum(value))::integer into remaining from unnest(floors) value;
    for candidate in select ordinality::integer as position from unnest(values) with ordinality
      order by mod(unnest,divisor) desc, ordinality limit remaining loop
      floors[candidate.position] := floors[candidate.position] + 1;
    end loop;
    if column_index = 5 and rounding < 0 then select array_agg(-value order by ordinality) into floors from unnest(floors) with ordinality as parts(value,ordinality); end if;
    columns := columns || jsonb_build_array(to_jsonb(floors));
  end loop;
  for position in 1..cardinality(member_ids) loop
    amount := (columns->0->>(position-1))::bigint - (columns->1->>(position-1))::bigint + (columns->2->>(position-1))::bigint + (columns->3->>(position-1))::bigint + (columns->4->>(position-1))::bigint;
    if amount < 0 then perform private.raise_app_error('VALIDATION','Pembulatan membuat porsi negatif.'); end if;
    shares := shares || jsonb_build_object(member_ids[position],amount::bigint::text); total := total + amount::bigint;
  end loop;
  if total <= 0 or total > 999999999999 then perform private.raise_app_error('VALIDATION','Total tagihan tidak valid.'); end if;
  return jsonb_build_object('total',total::text,'shares',shares);
end;
$$;

commit;
