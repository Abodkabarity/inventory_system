create or replace function public.item_tracker_create_batch(p_items jsonb)
returns uuid[]
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_input jsonb;
  v_manual jsonb;
  v_record public.items_tracker_items%rowtype;
  v_ids uuid[] := '{}';
  v_codes text[] := '{}';
  v_code text;
  v_status text;
  v_role text;
  v_qty numeric;
  v_cost numeric;
  v_date date;
  v_batch uuid := gen_random_uuid();
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'INVENTORY_PERMISSION_REQUIRED' using errcode = '42501';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'PRODUCT_LIST_REQUIRED' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) not between 1 and 1000 then
    raise exception 'SELECT_BETWEEN_1_AND_1000_PRODUCTS' using errcode = '22023';
  end if;
  for v_input in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_input) is distinct from 'object' then
      raise exception 'INVALID_PRODUCT_ENTRY' using errcode = '22023';
    end if;
    v_manual := v_input->'manual_product';
    v_code := nullif(btrim(v_input->>'item_code'), '');
    if v_code is null and jsonb_typeof(v_manual) = 'object' then
      v_code := 'MANUAL-' || gen_random_uuid()::text;
    end if;
    if v_code is null then
      raise exception 'ITEM_CODE_REQUIRED' using errcode = '22023';
    end if;
    if lower(v_code) = any(v_codes) then
      raise exception 'DUPLICATE_PRODUCT_IN_SELECTION' using errcode = '22023';
    end if;
    v_codes := array_append(v_codes, lower(v_code));
    v_qty := (v_input->>'required_qty')::numeric;
    v_cost := (v_input->>'unit_cost')::numeric;
    v_date := coalesce((v_input->>'escalated_date')::date, (now() at time zone 'Asia/Dubai')::date);
    if v_qty is null or v_qty <= 0 or v_qty::text in ('NaN', 'Infinity', '-Infinity') then
      raise exception 'REQUIRED_QUANTITY_MUST_BE_POSITIVE' using errcode = '22023';
    end if;
    if v_cost < 0 or v_cost::text in ('NaN', 'Infinity', '-Infinity') then
      raise exception 'INVALID_UNIT_COST' using errcode = '22023';
    end if;
    v_role := lower(btrim(v_input->>'follow_up_role'));
    if v_role is null or v_role not in ('inventory', 'purchase', 'category') then
      raise exception 'INVALID_FOLLOW_UP_ROLE' using errcode = '22023';
    end if;
    if v_manual is null or v_manual = 'null'::jsonb then
      select * into v_record from public.item_tracker_create(
        v_date, v_code, v_cost, v_input->>'inventory_note',
        v_qty, v_input->>'status_updated_to', v_role
      );
      update public.items_tracker_events
      set details = details || jsonb_build_object('entry_mode', 'company', 'batch_id', v_batch, 'catalog_source', 'item_report')
      where item_id = v_record.id and event_type = 'created';
    else
      if jsonb_typeof(v_manual) is distinct from 'object'
        or nullif(btrim(v_manual->>'item_name'), '') is null
        or nullif(btrim(v_manual->>'company'), '') is null
        or nullif(btrim(v_manual->>'category'), '') is null then
        raise exception 'MANUAL_PRODUCT_NAME_COMPANY_CATEGORY_REQUIRED' using errcode = '22023';
      end if;
      if exists(select 1 from public.item_report r where lower(btrim(r.item_code)) = lower(v_code)) then
        raise exception 'PRODUCT_ALREADY_IN_ITEM_REPORT_SELECT_CATALOG_PRODUCT' using errcode = '22023';
      end if;
      select btrim(r.item_status) into v_status from public.item_report r
      where lower(btrim(r.item_status)) = lower(btrim(v_input->>'status_updated_to'))
      order by r.item_status limit 1;
      if v_status is null then
        raise exception 'INVALID_ITEM_STATUS' using errcode = '22023';
      end if;
      insert into public.items_tracker_items(
        escalated_date, item_code, item_name, category, supplier, company,
        source_item_status, unit_cost_snapshot, unit_cost_source, inventory_note,
        required_qty, status_updated_to, follow_up_role, case_status,
        created_by, created_by_role, updated_by, updated_by_role
      ) values (
        v_date, v_code, btrim(v_manual->>'item_name'), btrim(v_manual->>'category'),
        nullif(btrim(v_manual->>'supplier'), ''), btrim(v_manual->>'company'),
        null, v_cost, case when v_cost is not null then 'manual_inventory' end,
        nullif(btrim(v_input->>'inventory_note'), ''),
        v_qty, v_status, v_role, 'pending',
        auth.uid(), 'inventory', auth.uid(), 'inventory'
      ) returning * into v_record;
      insert into public.items_tracker_events(item_id, event_type, action_date, body, to_follow_up_role, to_case_status, actor_id, actor_role, details)
      values(v_record.id, 'created', v_date, 'Manual product added by Inventory', v_role, 'pending', auth.uid(), 'inventory',
        jsonb_build_object('entry_mode', 'company', 'batch_id', v_batch,
          'catalog_source', 'manual', 'company', v_record.company,
          'item_code', v_code, 'required_qty', v_qty, 'unit_cost', v_cost,
          'required_value', v_record.required_value, 'status_updated_to', v_status));
    end if;
    v_ids := array_append(v_ids, v_record.id);
  end loop;
  return v_ids;
end;
$$;
