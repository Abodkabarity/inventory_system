-- Database workflow only; no email is actually sent. Always roll back fixtures.
begin;
do $test$
declare
  inventory_user uuid;
  other_user uuid;
  status_value text;
  ids uuid[];
  input jsonb;
  drafts jsonb;
  draft_id uuid;
  blocked boolean;
  current_version bigint;
  old_count bigint;
  old_fingerprints text;
  after_fingerprints text;
begin
  select count(*),md5(coalesce(string_agg(row_to_json(i)::text,'|' order by id),''))
    into old_count,old_fingerprints from public.items_tracker_items i;
  select user_id into inventory_user from public.app_users where role='inventory' and is_active limit 1;
  select user_id into other_user from public.app_users where role='purchase' and is_active limit 1;
  select btrim(item_status) into status_value from public.item_report_apg where nullif(btrim(item_status),'') is not null limit 1;
  if inventory_user is null or other_user is null or status_value is null then raise exception 'Test actors/catalog unavailable'; end if;
  if has_function_privilege('anon','public.item_tracker_prepare_emails(uuid[],text)','execute') then raise exception 'Anonymous access enabled'; end if;
  perform set_config('request.jwt.claim.sub',inventory_user::text,true);
  execute 'set local role authenticated';
  input := jsonb_build_object('unit_cost',12.5,'required_qty',4,'status_updated_to',status_value,
    'inventory_note','Table reason <test> & details','follow_up_role','category','manual_product',
    jsonb_build_object('item_name','Rollback email product','company','Rollback email company','category','COSMETICS'));
  ids := public.item_tracker_create_batch_apg(jsonb_build_array(input,input,
    input || '{"follow_up_role":"purchase"}'::jsonb,input || '{"unit_cost":null}'::jsonb));
  if (select count(*) from public.item_tracker_grid_apg where id=any(ids) and email_queued_at is not null)<>4 then
    raise exception 'New products missing queue markers'; end if;
  blocked := false;
  begin perform public.item_tracker_prepare_emails(ids,null); exception when sqlstate '22023' then blocked:=true; end;
  if not blocked then raise exception 'Mixed department batch accepted'; end if;
  drafts := public.item_tracker_prepare_emails(array[ids[1],ids[2]],null);
  draft_id := (drafts->0->>'id')::uuid;
  if jsonb_array_length(drafts)<>1 or drafts->0->>'scope'<>'batch' or jsonb_array_length(drafts->0->'products')<>2 then raise exception 'Batch shape incorrect'; end if;
  if exists(select 1 from jsonb_array_elements(drafts->0->'products') p
    where (p->>'qty')::numeric<>4 or (p->>'cost')::numeric<>12.5 or (p->>'total')::numeric<>50 or p->>'status'<>status_value) then
    raise exception 'Snapshot quantities/costs/totals/status incorrect'; end if;
  if public.item_tracker_prepare_emails(array[ids[2],ids[1],ids[1]],null)<>drafts then raise exception 'Duplicate reservation created'; end if;
  blocked := false;
  begin perform public.item_tracker_prepare_emails(array[ids[1]],null,true); exception when sqlstate '22023' then blocked:=true; end;
  if not blocked then raise exception 'Unselected draft products silently included'; end if;
  blocked := false;
  begin perform public.item_tracker_prepare_emails(array[ids[1],ids[2],ids[4]],null); exception when sqlstate '22023' then blocked:=true; end;
  if not blocked then raise exception 'Draft scope changed silently'; end if;
  if not public.item_tracker_open_email(draft_id,false) then raise exception 'First handoff denied'; end if;
  if public.item_tracker_open_email(draft_id,false) then raise exception 'Double handoff allowed'; end if;
  perform public.item_tracker_release_email(draft_id);
  if not public.item_tracker_open_email(draft_id,false) then raise exception 'Failed launch not released'; end if;
  perform public.item_tracker_confirm_email(draft_id);
  perform public.item_tracker_confirm_email(draft_id);
  if (select count(*) from public.item_tracker_grid_apg where id=any(array[ids[1],ids[2]]) and email_status='sent')<>2 then raise exception 'Batch sent state missing'; end if;
  if public.item_tracker_open_email(draft_id,true) then raise exception 'Sent email reopened'; end if;
  drafts := public.item_tracker_prepare_emails(array[ids[4]],null);
  draft_id := (drafts->0->>'id')::uuid;
  if drafts->0->'products'->0->'cost'<>'null'::jsonb or drafts->0->'products'->0->'total'<>'null'::jsonb then raise exception 'Missing cost fabricated'; end if;
  perform public.item_tracker_cancel_email(draft_id);
  drafts := public.item_tracker_prepare_emails(array[ids[4]],null);
  draft_id := (drafts->0->>'id')::uuid;
  select row_version into current_version from public.items_tracker_items where id=ids[4];
  perform public.item_tracker_update_inventory_fields_apg(ids[4],current_date,20,'Table reason <test> & details',5,status_value,'category',current_version);
  blocked:=false;
  begin perform public.item_tracker_open_email(draft_id,false); exception when sqlstate '22023' then blocked:=true; end;
  if not blocked then raise exception 'Changed Qty/cost used stale snapshot'; end if;
  perform set_config('request.jwt.claim.sub',other_user::text,true);
  blocked:=false;
  begin perform public.item_tracker_prepare_emails(array[ids[3]],null); exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'Non-Inventory prepared batch'; end if;
  blocked:=false;
  begin update public.items_tracker_emails set status='sent' where id=draft_id; exception when insufficient_privilege then blocked:=true; end;
  if not blocked then raise exception 'Direct mutation enabled'; end if;
  perform set_config('request.jwt.claim.sub','',true);
  if exists(select 1 from public.items_tracker_emails) then raise exception 'Unauthenticated data visible'; end if;
  execute 'reset role';
  select md5(coalesce(string_agg(row_to_json(i)::text,'|' order by id),'')) into after_fingerprints
    from public.items_tracker_items i where not(id=any(ids));
  if old_fingerprints<>after_fingerprints then raise exception 'Existing item data changed'; end if;
end $test$;
rollback;
