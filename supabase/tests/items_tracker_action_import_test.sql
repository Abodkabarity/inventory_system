begin;
do $test$
declare
  v_inventory uuid;
  v_purchase uuid;
  v_status text;
  v_ids uuid[];
  v_catalog jsonb;
  v_rows jsonb;
  v_result jsonb;
  v_tokens uuid[] := array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
  v_item public.items_tracker_items%rowtype;
  v_version bigint;
  v_events bigint;
begin
  select user_id into v_inventory from public.app_users where role='inventory' and is_active limit 1;
  select user_id into v_purchase from public.app_users where role='purchase' and is_active limit 1;
  select btrim(item_status) into v_status from public.item_report where nullif(btrim(item_status),'') is not null limit 1;
  if v_inventory is null or v_purchase is null then raise exception 'Test roles unavailable'; end if;
  if has_function_privilege('anon', 'public.item_tracker_import_actions(jsonb,text,boolean)', 'execute') then
    raise exception 'Anonymous execution enabled';
  end if;
  perform set_config('request.jwt.claim.sub', v_inventory::text, true);
  execute 'set local role authenticated';
  v_catalog := jsonb_build_object('unit_cost',12.50,'required_qty',4,'status_updated_to',v_status,
    'inventory_note','Original reason','follow_up_role','purchase','manual_product',
    jsonb_build_object('item_name','Rollback import test','company','Rollback verification','category','COSMETICS'));
  v_ids := public.item_tracker_create_batch(jsonb_build_array(v_catalog, v_catalog, v_catalog,
    v_catalog || '{"follow_up_role":"category"}'::jsonb));
  select row_version into v_version from public.items_tracker_items where id=v_ids[1];
  perform set_config('request.jwt.claim.sub', v_purchase::text, true);
  perform public.item_tracker_add_action(v_ids[1],current_date,'Edited inside system','pending',v_version);
  perform public.item_tracker_add_action(v_ids[3],current_date,'System conflict action','pending',v_version);
  v_rows := '[]';
  for i in 1..4 loop
    select * into v_item from public.items_tracker_items where id=v_ids[i];
    v_rows := v_rows || jsonb_build_array(jsonb_build_object('excel_row',i+5,'item_id',v_item.id,
      'item_code',v_item.item_code,'expected_version',v_version,'import_token',v_tokens[i],
      'body',case when i=1 then '' else 'Action written in file' end,
      'action_date',null,'required_qty',0,'inventory_note','','case_status','done'));
  end loop;
  -- Even malformed metadata on a blank action must not touch the record.
  v_rows := v_rows || '[{"excel_row":20,"item_id":"invalid","body":"   "}]'::jsonb;
  select count(*) into v_events from public.items_tracker_events where item_id=any(v_ids);
  v_result := public.item_tracker_import_actions(v_rows,'rollback.xlsx',false);
  if not v_result @> '[{"excel_row":6,"status":"blank"},{"excel_row":7,"status":"ready"},{"excel_row":8,"status":"conflict"},{"excel_row":9,"status":"not_assigned"},{"excel_row":20,"status":"blank"}]'::jsonb then
    raise exception 'Unexpected preview: %',v_result;
  end if;
  if (select count(*) from public.items_tracker_events where item_id=any(v_ids)) <> v_events then
    raise exception 'Preview modified events';
  end if;
  v_result := public.item_tracker_import_actions(v_rows,'rollback.xlsx',true);
  if not v_result @> '[{"excel_row":6,"status":"blank"},{"excel_row":7,"status":"imported"},{"excel_row":8,"status":"conflict"},{"excel_row":9,"status":"not_assigned"}]'::jsonb then
    raise exception 'Unexpected apply: %',v_result;
  end if;
  if (select count(*) from public.items_tracker_events where item_id=any(v_ids)) <> v_events+1 then
    raise exception 'Import added blank, conflicting or unauthorized actions';
  end if;
  if not exists(select 1 from public.items_tracker_items where id=v_ids[2]
    and required_qty=4 and unit_cost_snapshot=12.50 and inventory_note='Original reason' and case_status='pending') then
    raise exception 'Import overwrote reference fields';
  end if;
  if not exists(select 1 from public.items_tracker_events where item_id=v_ids[1] and body='Edited inside system') then
    raise exception 'Blank action cleared system change';
  end if;
  if not exists(select 1 from public.items_tracker_events where item_id=v_ids[2] and actor_id=v_purchase
    and actor_role='purchase' and details->>'import_source'='excel') then
    raise exception 'Imported action audit is incorrect';
  end if;
  v_result := public.item_tracker_import_actions(v_rows,'rollback.xlsx',true);
  if not v_result @> '[{"excel_row":7,"status":"already_imported"}]'::jsonb
    or (select count(*) from public.items_tracker_events where item_id=any(v_ids)) <> v_events+1 then
    raise exception 'Reimport duplicated an action';
  end if;
  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform public.item_tracker_import_actions(v_rows,'rollback.xlsx',true);
    raise exception 'Unauthenticated import accepted';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';
end;
$test$;
rollback;
