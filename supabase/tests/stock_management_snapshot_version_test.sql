-- Run as database owner; simulated metadata updates roll back.
begin;
do $test$
declare
  overview jsonb;
  batch jsonb;
  original_source_time text;
  changed_version timestamptz;
  inventory_user uuid;
begin
  select user_id into inventory_user from public.app_users
    where role='inventory' and is_active limit 1;
  if inventory_user is null then raise exception 'Inventory test actor unavailable'; end if;
  select payload->'meta'->>'refreshed_at' into original_source_time
    from public.stock_management_snapshot order by item_code limit 1;
  -- Reproduce the Created date backfill: updated_at changes while source metadata does not.
  update public.stock_management_snapshot set updated_at=
    (select max(updated_at)+interval '1 second' from public.stock_management_snapshot)
    where item_code=(select item_code from public.stock_management_snapshot order by item_code limit 1);
  select max(updated_at) into changed_version from public.stock_management_snapshot;
  perform set_config('request.jwt.claim.sub',inventory_user::text,true);
  execute 'set local role authenticated';
  overview:=public.get_stock_management_page(p_limit=>1);
  batch:=public.get_stock_management_register_batch(0,1);
  if (overview->'meta'->>'snapshot_at')::timestamptz is distinct from changed_version
    or (overview->'meta'->>'refreshed_at')::timestamptz is distinct from changed_version
    or (batch->>'snapshot_at')::timestamptz is distinct from changed_version then
    raise exception 'Overview and batches do not share the canonical snapshot version';
  end if;
  if (overview->'summary'->>'items')::bigint<>(batch->>'total')::bigint then
    raise exception 'Overview and batch counts differ';
  end if;
  execute 'reset role';
  if original_source_time is distinct from (select payload->'meta'->>'refreshed_at'
    from public.stock_management_snapshot order by item_code limit 1) then
    raise exception 'Source metadata was modified';
  end if;
  if (select prosecdef from pg_proc where oid=
      'public.get_stock_management_page(text,text,text,text,date,date,text,integer,integer)'::regprocedure) then
    raise exception 'Reader must remain security invoker';
  end if;
end;
$test$;
rollback;
