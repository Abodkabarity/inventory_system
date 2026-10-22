-- app_users.role is text and already accepts 'view'. Keep the Items Tracker
-- role helper unchanged: a viewer must never acquire inventory write access.
create or replace function stock_management_private.is_view_user()
returns boolean language sql stable security invoker set search_path='' as $$
  select exists (
    select 1 from public.app_users u
    where u.user_id=(select auth.uid())
      and u.is_active is not false
      and lower(btrim(u.role::text))='view'
  );
$$;
revoke all on function stock_management_private.is_view_user() from public,anon;
grant execute on function stock_management_private.is_view_user() to authenticated,service_role;

-- Only SELECT is added. Existing inventory policies and write guards remain.
create policy stock_management_view_read on public.stock_management_snapshot
  for select to authenticated using ((select stock_management_private.is_view_user()));
create policy stock_management_refresh_view_read on public.stock_management_refresh_state
  for select to authenticated using ((select stock_management_private.is_view_user()));
create policy stock_catalog_view_read on public.stock_catalog_snapshot
  for select to authenticated using ((select stock_management_private.is_view_user()));
create policy stock_catalog_refresh_view_read on public.stock_catalog_refresh_state
  for select to authenticated using ((select stock_management_private.is_view_user()));
create policy stock_expiry_reviews_view_read on public.stock_expiry_reviews
  for select to authenticated using ((select stock_management_private.is_view_user()));
create policy stock_expiry_watch_view_read on public.stock_expiry_watch_state
  for select to authenticated using ((select stock_management_private.is_view_user()));
create policy stock_expiry_receipts_view_read on public.stock_expiry_alert_receipts
  for select to authenticated using ((select stock_management_private.is_view_user()));
create policy stock_workspace_cache_view_read on public.stock_workspace_cache_revisions
  for select to authenticated using ((select stock_management_private.is_view_user()));

-- Preserve the current cache version and all completeness/privilege checks.
do $$
declare definition text;
begin
  definition := pg_get_functiondef('public.get_stock_workspace_cache_state()'::regprocedure);
  if strpos(definition, 'public.item_tracker_my_role()=''inventory'' or current_user=''service_role''')=0 then
    raise exception 'Stock workspace authorization changed; review the view-role migration';
  end if;
  execute replace(definition,
    'public.item_tracker_my_role()=''inventory'' or current_user=''service_role''',
    'public.item_tracker_my_role()=''inventory'' or stock_management_private.is_view_user() or current_user=''service_role''');
end;
$$;

create or replace function public.prepare_stock_expiry_workspace(p_known_discovery_version text default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare before_state jsonb; after_state jsonb;
begin
  before_state := public.get_stock_workspace_cache_state();
  if before_state is null then
    raise exception 'Stock workspace access required' using errcode='42501';
  end if;
  -- Viewers read the persistent register without starting receipt discovery.
  if stock_management_private.is_view_user() then
    return before_state;
  end if;
  if before_state->>'discovery' is distinct from p_known_discovery_version then
    perform public.refresh_stock_expiry_watch();
  end if;
  after_state := public.get_stock_workspace_cache_state();
  if before_state->>'discovery' is distinct from after_state->>'discovery' then
    raise exception 'Receipts changed while loading. Please retry.' using errcode='40001';
  end if;
  return after_state;
end;
$$;
revoke all on function public.prepare_stock_expiry_workspace(text) from public,anon;
grant execute on function public.prepare_stock_expiry_workspace(text) to authenticated,service_role;
