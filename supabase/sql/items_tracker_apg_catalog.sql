-- APG catalog RPCs for Items Tracker. Existing catalogs, RPCs and Daily Order stay intact.
-- Only explicitly selected catalog fields are returned; reference_metric is private.
CREATE OR REPLACE FUNCTION public.item_tracker_apg_key(p_product public.item_report_apg)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, public
AS $function$
  SELECT md5(jsonb_build_array(p_product.item_code, p_product.item_name,
    p_product.category, p_product.supplier, p_product.company,
    p_product.item_status, p_product.retail, p_product.is_block)::text);
$function$;
REVOKE ALL ON FUNCTION public.item_tracker_apg_key(public.item_report_apg) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.item_tracker_company_catalog_apg(p_company text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 1000)
RETURNS TABLE(item_code text, item_name text, category text, supplier text, company text,
  item_status text, retail double precision, is_block boolean, catalog_key text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $function$
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'INVENTORY_PERMISSION_REQUIRED' using errcode = '42501';
  end if;
  return query
  select r.item_code, r.item_name, r.category, r.supplier, r.company, r.item_status, r.retail,
    lower(btrim(coalesce(r.is_block::text, ''))) in ('checked','true','1','yes','block','blocked'),
    public.item_tracker_apg_key(r)
  from public.item_report_apg r
  where lower(btrim(r.company)) = lower(btrim(p_company))
    and nullif(btrim(r.item_code), '') is not null
    and nullif(btrim(r.item_name), '') is not null
  order by r.item_name, r.item_code, public.item_tracker_apg_key(r)
  offset greatest(coalesce(p_offset, 0), 0)
  limit least(greatest(coalesce(p_limit, 1000), 1), 1000);
end;
$function$;;

REVOKE ALL ON FUNCTION public.item_tracker_company_catalog_apg(text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.item_tracker_company_catalog_apg(text, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.item_tracker_create_apg(p_escalated_date date, p_item_code text, p_unit_cost numeric, p_inventory_note text, p_required_qty numeric, p_status_updated_to text, p_follow_up_role text, p_catalog_key text)
 RETURNS items_tracker_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_role text := public.item_tracker_my_role();
  v_catalog record;
  v_status_updated_to text;
  v_follow_up_role text;
  v_item public.items_tracker_items%rowtype;
begin
  if v_role is distinct from 'inventory' then
    raise exception 'INVENTORY_PERMISSION_REQUIRED'
      using errcode = '42501';
  end if;

  if nullif(btrim(coalesce(p_item_code, '')), '') is null then
    raise exception 'ITEM_CODE_REQUIRED' using errcode = '22023';
  end if;

  if p_required_qty is null or p_required_qty <= 0 then
    raise exception 'REQUIRED_QUANTITY_MUST_BE_POSITIVE'
      using errcode = '22023';
  end if;

  if p_unit_cost is not null and p_unit_cost < 0 then
    raise exception 'UNIT_COST_CANNOT_BE_NEGATIVE'
      using errcode = '22023';
  end if;

  if nullif(btrim(p_catalog_key), '') is null then
    raise exception 'APG_CATALOG_SELECTION_REQUIRED' using errcode = '22023';
  end if;

  select
    nullif(btrim(ir.item_code::text), '') as item_code,
    nullif(btrim(ir.item_name::text), '') as item_name,
    nullif(btrim(ir.category::text), '') as category,
    nullif(btrim(ir.supplier::text), '') as supplier,
    nullif(btrim(ir.company::text), '') as company,
    nullif(btrim(ir.item_status::text), '') as item_status,
    ir.retail::numeric as retail,
    lower(btrim(coalesce(ir.is_block::text, ''))) in ('checked','true','1','yes','block','blocked') as is_block
  into v_catalog
  from public.item_report_apg ir
  where lower(btrim(ir.item_code::text)) =
    lower(btrim(p_item_code))
    and public.item_tracker_apg_key(ir) = btrim(p_catalog_key)
  limit 1;

  if not found or v_catalog.item_name is null then
    raise exception 'APG_CATALOG_SELECTION_CHANGED'
      using errcode = 'P0002';
  end if;

  if nullif(btrim(coalesce(p_status_updated_to, '')), '') is null then
    raise exception 'STATUS_UPDATED_TO_REQUIRED'
      using errcode = '22023';
  end if;

  select btrim(ir.item_status::text)
  into v_status_updated_to
  from public.item_report_apg ir
  where lower(btrim(ir.item_status::text)) =
    lower(btrim(p_status_updated_to))
  order by ir.item_status::text
  limit 1;

  if not found or v_status_updated_to is null then
    raise exception 'INVALID_ITEM_STATUS'
      using errcode = '22023';
  end if;

  v_follow_up_role := lower(btrim(coalesce(p_follow_up_role, '')));
  if v_follow_up_role = '' then
    v_follow_up_role := case
      when upper(btrim(coalesce(v_catalog.category, ''))) = 'MEDICINE'
        then 'purchase'
      else 'category'
    end;
  end if;

  if v_follow_up_role not in ('inventory', 'purchase', 'category') then
    raise exception 'INVALID_FOLLOW_UP_ROLE'
      using errcode = '22023';
  end if;

  insert into public.items_tracker_items (
    escalated_date,
    item_code,
    item_name,
    category,
    supplier,
    company,
    source_item_status,
    retail_snapshot,
    unit_cost_snapshot,
    unit_cost_source,
    inventory_note,
    required_qty,
    status_updated_to,
    follow_up_role,
    case_status,
    created_by,
    created_by_role,
    updated_by,
    updated_by_role
  ) values (
    coalesce(
      p_escalated_date,
      (now() at time zone 'Asia/Dubai')::date
    ),
    v_catalog.item_code,
    v_catalog.item_name,
    v_catalog.category,
    v_catalog.supplier,
    v_catalog.company,
    v_catalog.item_status,
    v_catalog.retail,
    p_unit_cost,
    case
      when p_unit_cost is null then null
      else 'manual_inventory'
    end,
    nullif(btrim(coalesce(p_inventory_note, '')), ''),
    p_required_qty,
    v_status_updated_to,
    v_follow_up_role,
    'pending',
    auth.uid(),
    v_role,
    auth.uid(),
    v_role
  )
  returning * into v_item;

  insert into public.items_tracker_events (
    item_id,
    event_type,
    action_date,
    body,
    to_follow_up_role,
    to_case_status,
    details,
    actor_id,
    actor_role
  ) values (
    v_item.id,
    'created',
    v_item.escalated_date,
    'Item escalated by Inventory',
    v_item.follow_up_role,
    v_item.case_status,
    jsonb_build_object(
      'escalated_date', v_item.escalated_date,
      'item_code', v_item.item_code,
      'catalog_source', 'item_report_apg',
      'catalog_key', p_catalog_key,
      'catalog_is_block', v_catalog.is_block,
      'required_qty', v_item.required_qty,
      'unit_cost_snapshot', v_item.unit_cost_snapshot,
      'required_value', v_item.required_value,
      'status_updated_to', v_item.status_updated_to
    ),
    auth.uid(),
    v_role
  );

  return v_item;
end;
$function$;

REVOKE ALL ON FUNCTION public.item_tracker_create_apg(date, text, numeric, text, numeric, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.item_tracker_create_apg(date, text, numeric, text, numeric, text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.item_tracker_create_batch_apg(p_items jsonb)
 RETURNS uuid[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_input jsonb;
  v_manual jsonb;
  v_record public.items_tracker_items%rowtype;
  v_ids uuid[] := '{}';
  v_codes text[] := '{}';
  v_code text;
  v_selection text;
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
    v_selection := case when v_manual is null or v_manual = 'null'::jsonb
      then 'catalog:' || coalesce(v_input->>'catalog_key', '')
      else 'manual:' || lower(v_code) end;
    if v_selection = any(v_codes) then
      raise exception 'DUPLICATE_PRODUCT_IN_SELECTION' using errcode = '22023';
    end if;
    v_codes := array_append(v_codes, v_selection);
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
      select * into v_record from public.item_tracker_create_apg(
        v_date, v_code, v_cost, v_input->>'inventory_note',
        v_qty, v_input->>'status_updated_to', v_role, v_input->>'catalog_key'
      );
      update public.items_tracker_events
      set details = details || jsonb_build_object('entry_mode', 'company', 'batch_id', v_batch, 'catalog_source', 'item_report_apg')
      where item_id = v_record.id and event_type = 'created';
    else
      if jsonb_typeof(v_manual) is distinct from 'object'
        or nullif(btrim(v_manual->>'item_name'), '') is null
        or nullif(btrim(v_manual->>'company'), '') is null
        or nullif(btrim(v_manual->>'category'), '') is null then
        raise exception 'MANUAL_PRODUCT_NAME_COMPANY_CATEGORY_REQUIRED' using errcode = '22023';
      end if;
      if exists(select 1 from public.item_report_apg r where lower(btrim(r.item_code)) = lower(v_code)) then
        raise exception 'PRODUCT_ALREADY_IN_ITEM_REPORT_SELECT_CATALOG_PRODUCT' using errcode = '22023';
      end if;
      select btrim(r.item_status) into v_status from public.item_report_apg r
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
$function$;

REVOKE ALL ON FUNCTION public.item_tracker_create_batch_apg(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.item_tracker_create_batch_apg(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.item_tracker_search_catalog_apg(p_query text, p_limit integer DEFAULT 15)
 RETURNS TABLE(item_code text, item_name text, category text, supplier text, company text, item_status text, retail numeric, is_block boolean, catalog_key text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_role text := public.item_tracker_my_role();
  v_query text := btrim(coalesce(p_query, ''));
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 50);
begin
  if v_role is null then
    raise exception 'ITEMS_TRACKER_PERMISSION_REQUIRED'
      using errcode = '42501';
  end if;

  if v_query = '' then
    return;
  end if;

  return query
  select
    ir.item_code::text,
    ir.item_name::text,
    ir.category::text,
    ir.supplier::text,
    ir.company::text,
    ir.item_status::text,
    ir.retail::numeric,
    lower(btrim(coalesce(ir.is_block::text, ''))) in ('checked','true','1','yes','block','blocked'),
    public.item_tracker_apg_key(ir)
  from public.item_report_apg ir
  where ir.item_code::text ilike ('%' || v_query || '%')
     or ir.item_name::text ilike ('%' || v_query || '%')
  order by
    case
      when lower(btrim(ir.item_code::text)) = lower(v_query) then 0
      when lower(btrim(ir.item_name::text)) = lower(v_query) then 1
      when lower(ir.item_code::text) like lower(v_query) || '%' then 2
      else 3
    end,
    ir.item_name::text,
    ir.item_code::text,
    public.item_tracker_apg_key(ir)
  limit v_limit;
end;
$function$;

REVOKE ALL ON FUNCTION public.item_tracker_search_catalog_apg(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.item_tracker_search_catalog_apg(text, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.item_tracker_search_companies_apg(p_query text DEFAULT ''::text, p_limit integer DEFAULT 30)
 RETURNS TABLE(company text, product_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'INVENTORY_PERMISSION_REQUIRED' using errcode = '42501';
  end if;
  return query
  select min(btrim(r.company)), count(*)
  from public.item_report_apg r
  where nullif(btrim(r.company), '') is not null
    and nullif(btrim(r.item_code), '') is not null
    and nullif(btrim(r.item_name), '') is not null
    and position(lower(btrim(coalesce(p_query, ''))) in lower(btrim(r.company))) > 0
  group by lower(btrim(r.company))
  order by min(btrim(r.company))
  limit least(greatest(coalesce(p_limit, 30), 1), 100);
end;
$function$;

REVOKE ALL ON FUNCTION public.item_tracker_search_companies_apg(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.item_tracker_search_companies_apg(text, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.item_tracker_status_options_apg()
 RETURNS TABLE(item_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_role text := public.item_tracker_my_role();
begin
  if v_role is null then
    raise exception 'ITEMS_TRACKER_PERMISSION_REQUIRED'
      using errcode = '42501';
  end if;

  return query
  select distinct btrim(ir.item_status::text)
  from public.item_report_apg ir
  where nullif(btrim(ir.item_status::text), '') is not null
  order by 1;
end;
$function$;

REVOKE ALL ON FUNCTION public.item_tracker_status_options_apg() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.item_tracker_status_options_apg() TO authenticated;

CREATE OR REPLACE FUNCTION public.item_tracker_update_inventory_fields_apg(p_item_id uuid, p_escalated_date date, p_unit_cost numeric, p_inventory_note text, p_required_qty numeric, p_status_updated_to text, p_follow_up_role text, p_expected_version bigint)
 RETURNS items_tracker_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_role text := public.item_tracker_my_role();
  v_old public.items_tracker_items%rowtype;
  v_new public.items_tracker_items%rowtype;
  v_status_updated_to text;
  v_follow_up_role text;
begin
  if v_role is distinct from 'inventory' then
    raise exception 'INVENTORY_PERMISSION_REQUIRED'
      using errcode = '42501';
  end if;

  select * into v_old
  from public.items_tracker_items
  where id = p_item_id
  for update;

  if not found then
    raise exception 'ITEMS_TRACKER_ITEM_NOT_FOUND'
      using errcode = 'P0002';
  end if;

  if p_expected_version is not null
    and v_old.row_version is distinct from p_expected_version then
    raise exception 'STALE_ITEM_VERSION'
      using errcode = '40001';
  end if;

  if p_escalated_date is null then
    raise exception 'ESCALATED_DATE_REQUIRED' using errcode = '22023';
  end if;

  if p_required_qty is null or p_required_qty <= 0 then
    raise exception 'REQUIRED_QUANTITY_MUST_BE_POSITIVE'
      using errcode = '22023';
  end if;

  if p_unit_cost is not null and p_unit_cost < 0 then
    raise exception 'UNIT_COST_CANNOT_BE_NEGATIVE'
      using errcode = '22023';
  end if;

  if nullif(btrim(coalesce(p_status_updated_to, '')), '') is null then
    raise exception 'STATUS_UPDATED_TO_REQUIRED'
      using errcode = '22023';
  end if;

  select btrim(ir.item_status::text)
  into v_status_updated_to
  from public.item_report_apg ir
  where lower(btrim(ir.item_status::text)) =
    lower(btrim(p_status_updated_to))
  order by ir.item_status::text
  limit 1;

  if not found or v_status_updated_to is null then
    raise exception 'INVALID_ITEM_STATUS'
      using errcode = '22023';
  end if;

  v_follow_up_role := lower(
    btrim(coalesce(p_follow_up_role, v_old.follow_up_role, ''))
  );
  if v_follow_up_role not in ('inventory', 'purchase', 'category') then
    raise exception 'INVALID_FOLLOW_UP_ROLE'
      using errcode = '22023';
  end if;

  update public.items_tracker_items
  set
    escalated_date = p_escalated_date,
    required_qty = p_required_qty,
    inventory_note = nullif(btrim(coalesce(p_inventory_note, '')), ''),
    status_updated_to = v_status_updated_to,
    unit_cost_snapshot = p_unit_cost,
    unit_cost_source = case
      when p_unit_cost is null then null
      else 'manual_inventory'
    end,
    follow_up_role = v_follow_up_role,
    updated_by = auth.uid(),
    updated_by_role = v_role
  where id = p_item_id
  returning * into v_new;

  insert into public.items_tracker_events (
    item_id,
    event_type,
    body,
    details,
    actor_id,
    actor_role
  ) values (
    p_item_id,
    'inventory_update',
    'Inventory fields updated',
    jsonb_build_object(
      'old', jsonb_build_object(
        'escalated_date', v_old.escalated_date,
        'required_qty', v_old.required_qty,
        'inventory_note', v_old.inventory_note,
        'status_updated_to', v_old.status_updated_to,
        'follow_up_role', v_old.follow_up_role,
        'unit_cost_snapshot', v_old.unit_cost_snapshot,
        'required_value', v_old.required_value
      ),
      'new', jsonb_build_object(
        'escalated_date', v_new.escalated_date,
        'required_qty', v_new.required_qty,
        'inventory_note', v_new.inventory_note,
        'status_updated_to', v_new.status_updated_to,
        'follow_up_role', v_new.follow_up_role,
        'unit_cost_snapshot', v_new.unit_cost_snapshot,
        'required_value', v_new.required_value
      )
    ),
    auth.uid(),
    v_role
  );

  if v_old.follow_up_role is distinct from v_new.follow_up_role then
    insert into public.items_tracker_events (
      item_id,
      event_type,
      action_date,
      body,
      from_follow_up_role,
      to_follow_up_role,
      from_case_status,
      to_case_status,
      actor_id,
      actor_role
    ) values (
      p_item_id,
      'follow_up',
      (now() at time zone 'Asia/Dubai')::date,
      'Follow-up changed by Inventory',
      v_old.follow_up_role,
      v_new.follow_up_role,
      v_old.case_status,
      v_new.case_status,
      auth.uid(),
      v_role
    );
  end if;

  return v_new;
end;
$function$;

REVOKE ALL ON FUNCTION public.item_tracker_update_inventory_fields_apg(uuid, date, numeric, text, numeric, text, text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.item_tracker_update_inventory_fields_apg(uuid, date, numeric, text, numeric, text, text, bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.item_tracker_update_status_updated_to_apg(p_item_id uuid, p_status_updated_to text, p_expected_version bigint)
 RETURNS items_tracker_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_role text := public.item_tracker_my_role();
  v_old public.items_tracker_items%rowtype;
  v_new public.items_tracker_items%rowtype;
  v_status_updated_to text;
begin
  if v_role is distinct from 'inventory' then
    raise exception 'INVENTORY_PERMISSION_REQUIRED'
      using errcode = '42501';
  end if;

  select * into v_old
  from public.items_tracker_items
  where id = p_item_id
  for update;

  if not found then
    raise exception 'ITEMS_TRACKER_ITEM_NOT_FOUND'
      using errcode = 'P0002';
  end if;

  if p_expected_version is not null
    and v_old.row_version is distinct from p_expected_version then
    raise exception 'STALE_ITEM_VERSION'
      using errcode = '40001';
  end if;

  if nullif(btrim(coalesce(p_status_updated_to, '')), '') is null then
    raise exception 'STATUS_UPDATED_TO_REQUIRED'
      using errcode = '22023';
  end if;

  select btrim(ir.item_status::text)
  into v_status_updated_to
  from public.item_report_apg ir
  where lower(btrim(ir.item_status::text)) =
    lower(btrim(p_status_updated_to))
  order by ir.item_status::text
  limit 1;

  if not found or v_status_updated_to is null then
    raise exception 'INVALID_ITEM_STATUS'
      using errcode = '22023';
  end if;

  -- Do not create a new version or audit event when the canonical value did
  -- not actually change.
  if lower(btrim(v_old.status_updated_to)) =
     lower(btrim(v_status_updated_to)) then
    return v_old;
  end if;

  update public.items_tracker_items
  set
    status_updated_to = v_status_updated_to,
    updated_by = auth.uid(),
    updated_by_role = v_role
  where id = p_item_id
  returning * into v_new;

  insert into public.items_tracker_events (
    item_id,
    event_type,
    body,
    details,
    actor_id,
    actor_role
  ) values (
    p_item_id,
    'inventory_update',
    'Status Updated To changed by Inventory',
    jsonb_build_object(
      'field', 'status_updated_to',
      'old', v_old.status_updated_to,
      'new', v_new.status_updated_to
    ),
    auth.uid(),
    v_role
  );

  return v_new;
end;
$function$;

REVOKE ALL ON FUNCTION public.item_tracker_update_status_updated_to_apg(uuid, text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.item_tracker_update_status_updated_to_apg(uuid, text, bigint) TO authenticated;

NOTIFY pgrst, 'reload schema';

