-- Verifies APG saving against temporary copies only. No production tracker rows are written.
BEGIN;
CREATE TEMP TABLE apg_test_items (LIKE public.items_tracker_items INCLUDING DEFAULTS INCLUDING GENERATED INCLUDING CONSTRAINTS);
CREATE TEMP TABLE apg_test_events (LIKE public.items_tracker_events INCLUDING DEFAULTS INCLUDING GENERATED INCLUDING IDENTITY);
DO $test$
DECLARE
  v_definition text;
  v_inventory uuid;
  v_products jsonb;
  v_ids uuid[];
  v_record record;
  v_original record;
  v_count integer;
BEGIN
  SELECT user_id INTO v_inventory FROM public.app_users
  WHERE lower(role) = 'inventory' AND is_active IS NOT FALSE LIMIT 1;
  IF v_inventory IS NULL THEN RAISE EXCEPTION 'No inventory test role'; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_inventory::text, true);

  FOR v_original IN SELECT p.oid, p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN ('item_tracker_create_apg','item_tracker_create_batch_apg')
    ORDER BY p.proname LOOP
    v_definition := pg_get_functiondef(v_original.oid);
    v_definition := replace(v_definition, 'public.item_tracker_create_batch_apg(', 'pg_temp.apg_test_create_batch(');
    v_definition := replace(v_definition, 'public.item_tracker_create_apg(', 'pg_temp.apg_test_create(');
    v_definition := replace(v_definition, 'public.items_tracker_items', 'pg_temp.apg_test_items');
    v_definition := replace(v_definition, 'RETURNS items_tracker_items', 'RETURNS pg_temp.apg_test_items');
    v_definition := replace(v_definition, 'public.items_tracker_events', 'pg_temp.apg_test_events');
    EXECUTE v_definition;
  END LOOP;

  SELECT jsonb_agg(jsonb_build_object(
    'item_code', r.item_code, 'catalog_key', public.item_tracker_apg_key(r),
    'required_qty', 2, 'unit_cost', 0, 'status_updated_to', r.item_status, 'follow_up_role', 'inventory',
    'inventory_note', 'Isolated APG verification'))
  INTO v_products
  FROM public.item_report_apg r
  WHERE r.item_code = (SELECT item_code FROM public.item_report_apg GROUP BY item_code
    HAVING count(*) = 2 AND count(DISTINCT is_block) = 2 ORDER BY item_code LIMIT 1);
  IF jsonb_array_length(v_products) <> 2 THEN RAISE EXCEPTION 'Duplicate fixture missing'; END IF;
  SELECT count(*) INTO v_count FROM public.item_tracker_search_catalog_apg_cost(v_products->0->>'item_code',50);
  IF v_count <> 2 THEN RAISE EXCEPTION 'Search collapsed duplicate code'; END IF;

  v_ids := pg_temp.apg_test_create_batch(v_products);
  IF array_length(v_ids, 1) <> 2 THEN RAISE EXCEPTION 'Duplicate code batch not saved'; END IF;
  FOR v_record IN SELECT i.*, e.details FROM pg_temp.apg_test_items i
    JOIN pg_temp.apg_test_events e ON e.item_id=i.id LOOP
    IF NOT EXISTS (SELECT 1 FROM public.item_report_apg r
      WHERE public.item_tracker_apg_key(r) = v_record.details->>'catalog_key'
        AND r.item_name = v_record.item_name AND r.item_status = v_record.source_item_status
        AND r.reference_metric IS NOT DISTINCT FROM v_record.unit_cost_snapshot
        AND v_record.unit_cost_source = 'item_report_apg'
        AND v_record.required_value = round(r.reference_metric * 2, 2)
        AND (lower(r.is_block)='checked') = (v_record.details->>'catalog_is_block')::boolean)
    THEN RAISE EXCEPTION 'Saved wrong catalog variant'; END IF;
  END LOOP;
  BEGIN
    PERFORM pg_temp.apg_test_create_batch(jsonb_build_array(v_products->0, v_products->0));
    RAISE EXCEPTION 'Same variant accepted twice';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
  BEGIN
    PERFORM pg_temp.apg_test_create_batch(jsonb_build_array((v_products->0) || '{"catalog_key":"stale-key"}'::jsonb));
    RAISE EXCEPTION 'Stale selection accepted';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;
  END;
  SELECT count(*) INTO v_count FROM pg_temp.apg_test_items;
  IF v_count <> 2 THEN RAISE EXCEPTION 'Failed batch left partial records'; END IF;
  IF has_table_privilege('authenticated','public.item_report_apg','select')
    OR has_function_privilege('anon','public.item_tracker_search_catalog_apg_cost(text,integer)','execute') THEN
    RAISE EXCEPTION 'APG catalog permissions leaked';
  END IF;
END;
$test$;
ROLLBACK;

