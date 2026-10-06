begin;
do $test$
declare
  v_inventory uuid;
  v_purchase uuid;
  v_catalog record;
  v_ids uuid[];
  v_before bigint;
  v_count bigint;
  v_entry jsonb;
  v_manual jsonb;
  v_company_count bigint;
begin
  select user_id into v_inventory from public.app_users where role = 'inventory' and is_active limit 1;
  select user_id into v_purchase from public.app_users where role = 'purchase' and is_active limit 1;
  if v_inventory is null or v_purchase is null then raise exception 'Active test roles unavailable'; end if;
  select item_code, company, item_status into v_catalog from public.item_report
    where nullif(btrim(company), '') is not null and nullif(btrim(item_code), '') is not null
      and nullif(btrim(item_name), '') is not null and nullif(btrim(item_status), '') is not null limit 1;
  if has_function_privilege('anon', 'public.item_tracker_create_batch(jsonb)', 'execute') then
    raise exception 'Anonymous execution was not revoked';
  end if;
  perform set_config('request.jwt.claim.sub', v_inventory::text, true);
  execute 'set local role authenticated';
  select count(*) into v_company_count from public.item_tracker_search_companies(v_catalog.company);
  if v_company_count = 0 then raise exception 'Company search failed'; end if;
  if not exists(select 1 from public.item_tracker_company_catalog(v_catalog.company) c where c.item_code = v_catalog.item_code) then
    raise exception 'Company catalog omitted product';
  end if;
  v_entry := jsonb_build_object('item_code', v_catalog.item_code,
    'unit_cost', null, 'required_qty', 2, 'status_updated_to', v_catalog.item_status,
    'follow_up_role', 'inventory', 'inventory_note', 'Rollback verification');
  v_manual := jsonb_build_object('item_code', '', 'unit_cost', 12.50,
    'required_qty', 3, 'status_updated_to', v_catalog.item_status,
    'follow_up_role', 'category', 'manual_product', jsonb_build_object(
      'company', v_catalog.company, 'item_name', 'Rollback verification product', 'category', 'COSMETICS'));
  v_ids := public.item_tracker_create_batch(jsonb_build_array(v_entry, v_manual));
  if array_length(v_ids, 1) <> 2 then raise exception 'Batch did not create both products'; end if;
  if not exists(select 1 from public.items_tracker_items where id = v_ids[1]
    and unit_cost_snapshot is null and required_value is null and required_qty = 2) then
    raise exception 'Optional catalog cost incorrect';
  end if;
  if not exists(select 1 from public.items_tracker_items where id = v_ids[2]
    and item_code like 'MANUAL-%' and required_value = 37.50 and follow_up_role = 'category') then
    raise exception 'Manual product value incorrect';
  end if;
  select count(*) into v_count from public.items_tracker_events where item_id = any(v_ids)
    and event_type = 'created' and details->>'batch_id' is not null;
  if v_count <> 2 then raise exception 'Creation audit missing'; end if;
  select count(*) into v_before from public.items_tracker_items;
  begin
    perform public.item_tracker_create_batch(jsonb_build_array(v_entry, v_manual || '{"required_qty":0}'::jsonb));
    raise exception 'Invalid batch accepted';
  exception when sqlstate '22023' then null;
  end;
  select count(*) into v_count from public.items_tracker_items;
  if v_count <> v_before then raise exception 'Failed batch saved partial records'; end if;
  begin
    perform public.item_tracker_create_batch(jsonb_build_array(v_entry, v_entry));
    raise exception 'Duplicate batch accepted';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.item_tracker_create_batch(jsonb_build_array(v_manual || jsonb_build_object('item_code', v_catalog.item_code)));
    raise exception 'Manual entry overwrote catalog snapshot';
  exception when sqlstate '22023' then null;
  end;
  perform set_config('request.jwt.claim.sub', v_purchase::text, true);
  begin
    perform public.item_tracker_create_batch(jsonb_build_array(v_entry));
    raise exception 'Purchase was allowed to create products';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.item_tracker_create_batch(jsonb_build_array(v_entry));
    raise exception 'Unauthenticated creation accepted';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';
end;
$test$;
rollback;
