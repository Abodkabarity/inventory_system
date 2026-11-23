-- Main is a permanent assignment exception, never a delegated zone or a
-- client-supplied label. Authoritative app_user_zones supersedes legacy zone.
create function stock_management_private.is_main_zone_stock_reader()
returns boolean language sql stable security invoker set search_path='' as $$
  select exists (
    select 1 from public.app_users u
    where u.user_id=(select auth.uid()) and u.is_active is true
      and lower(btrim(u.role::text))='zone_manager'
      and (
        exists(select 1 from public.app_user_zones z
          where z.user_id=u.user_id and lower(btrim(z.zone))='main')
        or (not exists(select 1 from public.app_user_zones z where z.user_id=u.user_id)
          and lower(btrim(u.zone))='main')
      )
  );
$$;
revoke all on function stock_management_private.is_main_zone_stock_reader() from public,anon;
grant execute on function stock_management_private.is_main_zone_stock_reader() to authenticated,service_role;

create function public.can_read_main_zone_stock()
returns boolean language sql stable security invoker set search_path='' as $$
  select stock_management_private.is_main_zone_stock_reader();
$$;
revoke all on function public.can_read_main_zone_stock() from public,anon;
grant execute on function public.can_read_main_zone_stock() to authenticated,service_role;

-- All callers are stock SELECT policies, read RPCs and the no-discovery expiry
-- path. No inventory write or Online Overview permission uses this helper.
create or replace function stock_management_private.is_view_user()
returns boolean language sql stable security invoker set search_path='' as $$
  select exists (
    select 1 from public.app_users u
    where u.user_id=(select auth.uid()) and u.is_active is not false
      and lower(btrim(u.role::text)) in ('view','category')
  ) or stock_management_private.is_main_zone_stock_reader();
$$;
comment on function stock_management_private.is_view_user() is
  'Stock read-only access for View, Category and permanently assigned active Main zone managers. No writes or Online Overview.';

-- Product details use these sources under caller RLS. Main must receive the
-- same full-network evidence as View, not partial zonal sales beside global stock.
create policy main_zone_stock_history_read on public.sales_history
  for select to authenticated using((select stock_management_private.is_main_zone_stock_reader()));
create policy main_zone_stock_daily_read on public.sales_last_45_days
  for select to authenticated using((select stock_management_private.is_main_zone_stock_reader()));
notify pgrst,'reload schema';
