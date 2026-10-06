-- Automatic Items Tracker costs from APG; only Inventory can read catalog costs.
-- Existing tracker rows, old catalog RPCs and Daily Order are unchanged.

CREATE OR REPLACE FUNCTION public.item_tracker_company_catalog_apg_cost(p_company text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 1000)
 RETURNS TABLE(item_code text, item_name text, category text, supplier text, company text, item_status text, retail double precision, is_block boolean, catalog_key text, unit_cost numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'INVENTORY_PERMISSION_REQUIRED' using errcode = '42501';
  end if;
  return query
  select r.item_code, r.item_name, r.category, r.supplier, r.company, r.item_status, r.retail,
    lower(btrim(coalesce(r.is_block::text, ''))) in ('checked','true','1','yes','block','blocked'),
    public.item_tracker_apg_key(r), r.reference_metric::numeric
  from public.item_report_apg r
  where lower(btrim(r.company)) = lower(btrim(p_company))
    and nullif(btrim(r.item_code), '') is not null
    and nullif(btrim(r.item_name), '') is not null
  order by r.item_name, r.item_code, public.item_tracker_apg_key(r)
  offset greatest(coalesce(p_offset, 0), 0)
  limit least(greatest(coalesce(p_limit, 1000), 1), 1000);
end;
$function$;

REVOKE ALL ON FUNCTION public.item_tracker_company_catalog_apg_cost(text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.item_tracker_company_catalog_apg_cost(text, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.item_tracker_create_apg(p_escalated_date date, p_item_code text, p_unit_cost numeric, p_inventory_note text, p_required_qty numeric, p_status_updated_to text, p_follow_up_role text, p_catalog_key text)
 RETURNS items_tracker_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_role text := public.item_tracker_my_role();
  v_catalog record;
  v_cost numeric;
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
    ir.reference_metric::numeric as unit_cost,
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

  v_cost := coalesce(v_catalog.unit_cost, p_unit_cost);
  if v_cost < 0 or v_cost::text in ('NaN', 'Infinity', '-Infinity') then
    raise exception 'INVALID_UNIT_COST' using errcode = '22023';
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
    v_cost,
    case
      when v_catalog.unit_cost is not null then 'item_report_apg'
      when v_cost is not null then 'manual_inventory'
      else null
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

CREATE OR REPLACE FUNCTION public.item_tracker_search_catalog_apg_cost(p_query text, p_limit integer DEFAULT 15)
 RETURNS TABLE(item_code text, item_name text, category text, supplier text, company text, item_status text, retail numeric, is_block boolean, catalog_key text, unit_cost numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_role text := public.item_tracker_my_role();
  v_query text := btrim(coalesce(p_query, ''));
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 50);
begin
  if v_role is distinct from 'inventory' then
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
    public.item_tracker_apg_key(ir),
    ir.reference_metric::numeric
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

REVOKE ALL ON FUNCTION public.item_tracker_search_catalog_apg_cost(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.item_tracker_search_catalog_apg_cost(text, integer) TO authenticated;

NOTIFY pgrst, 'reload schema';

