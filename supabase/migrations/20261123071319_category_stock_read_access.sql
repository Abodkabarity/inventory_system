-- This stock-only helper gates existing SELECT policies, cache reads and the
-- no-discovery path in prepare_stock_expiry_workspace. Its callers were audited:
-- no write policy, refresh mutation or Online Overview guard uses it.
-- Keep the established name so all View read dependencies also cover Category.
create or replace function stock_management_private.is_view_user()
returns boolean language sql stable security invoker set search_path='' as $$
  select exists (
    select 1 from public.app_users u
    where u.user_id=(select auth.uid())
      and u.is_active is not false
      and lower(btrim(u.role::text)) in ('view','category')
  );
$$;
revoke all on function stock_management_private.is_view_user() from public,anon;
grant execute on function stock_management_private.is_view_user() to authenticated,service_role;
comment on function stock_management_private.is_view_user() is
  'Stock read-only access for active View and Category users. Never use for inventory writes or Online Overview.';
