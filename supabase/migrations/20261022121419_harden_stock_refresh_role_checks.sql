-- SQL NULL must fail inventory authorization. item_tracker_my_role() returns
-- NULL for viewers and other roles outside Items Tracker. In IF NOT (...), an
-- unhandled NULL previously skipped the denial branch of these refresh guards.
-- Preserve each routine's existing refresh implementation and service access.
do $$
declare routine regprocedure; definition text;
begin
  foreach routine in array array[
    'stock_management_private.refresh_snapshot()'::regprocedure,
    'stock_management_private.request_refresh()'::regprocedure,
    'stock_management_private.request_catalog_refresh()'::regprocedure,
    'stock_management_private.refresh_catalog()'::regprocedure
  ] loop
    definition := pg_get_functiondef(routine);
    if strpos(definition,'public.item_tracker_my_role()')=0 then
      raise exception 'Missing role guard in %',routine;
    end if;
    execute replace(definition,'public.item_tracker_my_role()',
      'coalesce(public.item_tracker_my_role(),'''')');
  end loop;
end;
$$;
