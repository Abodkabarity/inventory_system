-- Executes with authenticated RLS and always rolls back. No Outlook launch or
-- external email occurs; only the user's confirmation workflow is simulated.
begin;
do $test$
declare
  v_inventory uuid;
  v_purchase uuid;
  v_category uuid;
  v_status text;
  v_ids uuid[];
  v_input jsonb;
  v_drafts jsonb;
  v_drafts_again jsonb;
  v_category_job uuid;
  v_purchase_job uuid;
  v_inventory_job uuid;
  v_new_job uuid;
  v_blocked boolean;
  v_version bigint;
  v_events bigint;
begin
  select user_id into v_inventory from public.app_users where role='inventory' and is_active limit 1;
  select user_id into v_purchase from public.app_users where role='purchase' and is_active limit 1;
  select user_id into v_category from public.app_users where role='category' and is_active limit 1;
  select btrim(item_status) into v_status from public.item_report where nullif(btrim(item_status),'') is not null limit 1;
  if v_inventory is null or v_purchase is null or v_category is null then raise exception 'Active test roles unavailable'; end if;
  if has_function_privilege('anon','public.item_tracker_prepare_emails(uuid[],text)','execute')
    or has_function_privilege('anon','public.item_tracker_confirm_email(uuid)','execute') then
    raise exception 'Anonymous email execution enabled';
  end if;
  perform set_config('request.jwt.claim.sub',v_inventory::text,true);
  execute 'set local role authenticated';
  v_input := jsonb_build_object('unit_cost',null,'required_qty',2,'status_updated_to',v_status,
    'inventory_note','Reason & details','follow_up_role','category','manual_product',
    jsonb_build_object('item_name','Email rollback product','company','Email rollback company','category','COSMETICS'));
  v_ids := public.item_tracker_create_batch(jsonb_build_array(v_input,v_input,
    v_input || '{"follow_up_role":"inventory"}'::jsonb,
    v_input || '{"follow_up_role":"purchase"}'::jsonb));
  select row_version into v_version from public.items_tracker_items where id=v_ids[1];
  select count(*) into v_events from public.items_tracker_events where item_id=any(v_ids);
  v_drafts := public.item_tracker_prepare_emails(v_ids,'Email rollback company');
  if jsonb_array_length(v_drafts) <> 3 then raise exception 'Company email did not split departments: %',v_drafts; end if;
  select (d->>'id')::uuid into v_category_job from jsonb_array_elements(v_drafts) d where d->>'follow_up_role'='category';
  select (d->>'id')::uuid into v_purchase_job from jsonb_array_elements(v_drafts) d where d->>'follow_up_role'='purchase';
  select (d->>'id')::uuid into v_inventory_job from jsonb_array_elements(v_drafts) d where d->>'follow_up_role'='inventory';
  if (select jsonb_array_length(products) from public.items_tracker_emails where id=v_category_job) <> 2 then
    raise exception 'Wrong category email product count';
  end if;
  if exists(select 1 from public.item_tracker_grid where id=any(v_ids) and email_status <> 'draft') then
    raise exception 'Grid did not expose pending drafts';
  end if;
  -- Repeated requests and individual requests reuse exactly the same drafts.
  v_drafts_again := public.item_tracker_prepare_emails(v_ids,'Email rollback company');
  if v_drafts_again <> v_drafts then raise exception 'Repeat preparation created duplicate emails'; end if;
  v_drafts_again := public.item_tracker_prepare_emails(array[v_ids[1]],null);
  if jsonb_array_length(v_drafts_again) <> 1 or (v_drafts_again->0->>'id')::uuid <> v_category_job then
    raise exception 'Product request duplicated an existing company draft';
  end if;
  v_blocked := false;
  begin perform public.item_tracker_confirm_email(v_category_job); exception when others then v_blocked:=true; end;
  if not v_blocked then raise exception 'Unopened email marked as sent'; end if;
  if not public.item_tracker_open_email(v_category_job,false) then raise exception 'First Outlook handoff denied'; end if;
  if public.item_tracker_open_email(v_category_job,false) then raise exception 'Duplicate Outlook handoff allowed'; end if;
  if exists(select 1 from public.item_tracker_grid where id=any(array[v_ids[1],v_ids[2]]) and email_status='sent') then
    raise exception 'Opening Outlook incorrectly marked email as sent';
  end if;
  perform public.item_tracker_confirm_email(v_category_job);
  perform public.item_tracker_confirm_email(v_category_job);
  if (select count(*) from public.item_tracker_grid where id=any(array[v_ids[1],v_ids[2]])
      and email_status='sent' and email_scope='company' and email_sent_at is not null) <> 2 then
    raise exception 'Company confirmation did not mark both category products';
  end if;
  if public.item_tracker_open_email(v_category_job,true) then raise exception 'Sent email reopened'; end if;
  v_blocked:=false;
  begin perform public.item_tracker_cancel_email(v_category_job); exception when others then v_blocked:=true; end;
  if not v_blocked then raise exception 'Sent email cancelled'; end if;
  if (select row_version from public.items_tracker_items where id=v_ids[1]) <> v_version
    or (select count(*) from public.items_tracker_events where item_id=any(v_ids)) <> v_events then
    raise exception 'Email workflow changed action history or export version';
  end if;
  -- A later company addition emails only new products, not previous sent items.
  v_ids := array_append(v_ids,(public.item_tracker_create_batch(jsonb_build_array(v_input)))[1]);
  v_drafts_again := public.item_tracker_prepare_emails(v_ids,'Email rollback company');
  select (d->>'id')::uuid into v_new_job from jsonb_array_elements(v_drafts_again) d
    where d->>'follow_up_role'='category' and d->>'status'='draft';
  if v_new_job is null or (select jsonb_array_length(products) from public.items_tracker_emails where id=v_new_job) <> 1 then
    raise exception 'Previously sent company products included again';
  end if;
  -- Failed launches release only the handoff, not the reservation.
  perform public.item_tracker_open_email(v_inventory_job,false);
  perform public.item_tracker_release_email(v_inventory_job);
  if (select opened_at from public.items_tracker_emails where id=v_inventory_job) is not null then
    raise exception 'Failed Outlook handoff was not released';
  end if;
  perform public.item_tracker_cancel_email(v_purchase_job);
  if exists(select 1 from public.items_tracker_email_items where email_id=v_purchase_job) then
    raise exception 'Unsent draft cancellation did not release products';
  end if;
  -- A changed department/reason cannot silently use stale draft routing.
  perform public.item_tracker_update_inventory_fields(v_ids[3],current_date,null,'Changed reason',2,v_status,'purchase',v_version);
  v_blocked:=false;
  begin perform public.item_tracker_open_email(v_inventory_job,false); exception when others then v_blocked:=true; end;
  if not v_blocked then raise exception 'Stale draft was opened for the wrong department'; end if;
  perform public.item_tracker_cancel_email(v_inventory_job);
  v_drafts_again := public.item_tracker_prepare_emails(array[v_ids[3]],null);
  if v_drafts_again->0->>'follow_up_role' <> 'purchase' or v_drafts_again->0->>'scope' <> 'product' then
    raise exception 'New draft did not use current department/product scope';
  end if;
  -- The server guards all mutations even if a caller bypasses hidden UI buttons.
  foreach v_purchase in array array[v_purchase,v_category] loop
    perform set_config('request.jwt.claim.sub',v_purchase::text,true);
    v_blocked:=false;
    begin perform public.item_tracker_prepare_emails(array[v_ids[4]],null); exception when insufficient_privilege then v_blocked:=true; end;
    if not v_blocked then raise exception 'Non-Inventory prepared an email'; end if;
    v_blocked:=false;
    begin perform public.item_tracker_confirm_email(v_new_job); exception when insufficient_privilege then v_blocked:=true; end;
    if not v_blocked then raise exception 'Non-Inventory confirmed sending'; end if;
    v_blocked:=false;
    begin perform public.item_tracker_open_email(v_new_job,false); exception when insufficient_privilege then v_blocked:=true; end;
    if not v_blocked then raise exception 'Non-Inventory opened an email'; end if;
    v_blocked:=false;
    begin perform public.item_tracker_cancel_email(v_new_job); exception when insufficient_privilege then v_blocked:=true; end;
    if not v_blocked then raise exception 'Non-Inventory cancelled an email'; end if;
    v_blocked:=false;
    begin update public.items_tracker_emails set status='sent' where id=v_new_job; exception when insufficient_privilege then v_blocked:=true; end;
    if not v_blocked then raise exception 'Direct email mutation was allowed'; end if;
  end loop;
  perform set_config('request.jwt.claim.sub','',true);
  v_blocked:=false;
  begin perform public.item_tracker_prepare_emails(array[v_ids[4]],null); exception when insufficient_privilege then v_blocked:=true; end;
  if not v_blocked then raise exception 'Unauthenticated email preparation allowed'; end if;
  if exists(select 1 from public.items_tracker_emails) then raise exception 'Unauthenticated email read allowed'; end if;
  execute 'reset role';
end;
$test$;
rollback;
