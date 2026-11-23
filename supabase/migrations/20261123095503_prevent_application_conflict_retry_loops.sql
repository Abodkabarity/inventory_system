-- Business conflicts must reach the caller instead of triggering PostgREST 14 retries.
-- Only the SQLSTATE literal changes. Conditions, messages, writes and access stay intact.
do $migration$
declare signature text; target oid; original text; repaired text;
begin
  foreach signature in array array[
    'prepare_stock_expiry_workspace(text)',
    'stock_management_private.refresh_supply_insights(boolean)',
    'item_tracker_update_status_updated_to(uuid,text,bigint)',
    'item_tracker_update_tracker_status(uuid,text,bigint)',
    'item_tracker_update_inventory_fields_apg(uuid,date,numeric,text,numeric,text,text,bigint)',
    'stock_management_private.save_expiry_review(text,date,text,text,text,timestamp with time zone,date)',
    'item_tracker_update_inventory_fields(uuid,date,numeric,text,numeric,text,text,bigint)',
    'item_tracker_change_follow_up(uuid,text,text,date,bigint)',
    'item_tracker_add_action(uuid,date,text,text,bigint)',
    'item_tracker_update_status_updated_to_apg(uuid,text,bigint)',
    'inventory_audit.kpi_adjustments(uuid[],text,text,integer,text,date)',
    'branch_near_expiry_private.workspace(text,text,jsonb)',
    'upp_index_page(integer,integer,text)'
  ] loop
    target := to_regprocedure(signature);
    -- Some feature-specific functions are installed separately.
    if target is null then continue; end if;
    original := pg_get_functiondef(target);
    repaired := regexp_replace(original,
      $pattern$(errcode[[:space:]]*=[[:space:]]*)'40001'$pattern$,
      $replacement$\1'PT409'$replacement$, 'gi');
    if repaired is distinct from original then
      execute repaired;
    elsif strpos(original, 'PT409') = 0 then
      raise exception 'Expected conflict clause not found in %', signature;
    end if;
  end loop;
  target := to_regprocedure('public.item_tracker_import_actions(jsonb,text,boolean)');
  if target is not null then
    original := pg_get_functiondef(target);
    repaired := replace(original, 'when sqlstate ''40001'' then',
      'when sqlstate ''40001'' or sqlstate ''PT409'' then');
    if repaired is distinct from original then
      execute repaired;
    elsif strpos(original, 'when sqlstate ''40001'' or sqlstate ''PT409'' then') = 0 then
      raise exception 'Expected Items Tracker import conflict handler not found';
    end if;
  end if;
end;
$migration$;
