-- Protect the same sources used by Sales Report against direct API bypasses.
-- Do not mutate source rows, branch assignments, refresh jobs or report content.
-- Server ingestion/cron retain their postgres/service_role privileges.

-- Authenticated clients must not edit the authority used to derive their scope.
-- Account/zone assignment administration remains server-side.
revoke all on public.app_users,public.app_user_zones from public,anon,authenticated;
grant select on public.app_users,public.app_user_zones to authenticated;
revoke truncate,trigger,references on public.zone_management_delegations from public,anon,authenticated;

-- Inventory's Branch Settings still writes directly; other users cannot move a
-- branch to their zone or alter authoritative group/active membership.
alter table public.branches enable row level security;
revoke all on public.branches from public,anon;
revoke truncate,trigger,references on public.branches from authenticated;
create policy sales_report_branch_metadata_read on public.branches
  for select to authenticated using(true);
create policy sales_report_branch_inventory_insert on public.branches
  for insert to authenticated with check((select public.item_tracker_my_role())='inventory');
create policy sales_report_branch_inventory_update on public.branches
  for update to authenticated using((select public.item_tracker_my_role())='inventory')
  with check((select public.item_tracker_my_role())='inventory');
create policy sales_report_branch_inventory_delete on public.branches
  for delete to authenticated using((select public.item_tracker_my_role())='inventory');

-- NULL = existing full read for active non-zone business roles. Empty = deny.
-- A zone manager ALWAYS receives the current server-derived branch array,
-- including a genuinely empty scope, with no fallback to global sales.
create function sales_report_private.source_read_branches()
returns text[] language plpgsql stable security definer set search_path='' as $$
declare v_role text; v_scope jsonb; v_branches text[];
begin
  if auth.uid() is null then return array[]::text[]; end if;
  select lower(btrim(role)) into v_role from public.app_users
    where user_id=auth.uid() and is_active is not false limit 1;
  if v_role='zone_manager' then
    v_scope:=sales_report_private.current_scope();
    select coalesce(array_agg(b),array[]::text[]) into v_branches
      from jsonb_array_elements_text(coalesce(v_scope->'branches','[]'::jsonb)) b;
    return v_branches;
  end if;
  if v_role in ('inventory','purchase','category','store','view','branch') then return null; end if;
  return array[]::text[];
end $$;
revoke all on function sales_report_private.source_read_branches() from public,anon,authenticated,service_role;
grant execute on function sales_report_private.source_read_branches() to authenticated;

alter table public.sales_history enable row level security;
alter table public.sales_last_45_days enable row level security;
revoke all on public.sales_history,public.sales_last_45_days from public,anon,authenticated;
grant select on public.sales_history,public.sales_last_45_days to authenticated;
create policy sales_report_scoped_history_read on public.sales_history
  for select to authenticated using(
    (select sales_report_private.source_read_branches()) is null
    or btrim(branch_name)=any((select sales_report_private.source_read_branches())::text[]));
create policy sales_report_scoped_daily_read on public.sales_last_45_days
  for select to authenticated using(
    (select sales_report_private.source_read_branches()) is null
    or btrim(branch_name)=any((select sales_report_private.source_read_branches())::text[]));

-- Views must use the caller's source RLS rather than the view owner's bypass.
alter view public.availability_sales_monthly set(security_invoker=true);
alter view public.availability_branch_master set(security_invoker=true);
revoke all on public.availability_sales_monthly,public.availability_branch_master from public,anon;

-- A SECURITY DEFINER maintenance RPC must not bypass the new source policies.
revoke all on function public.truncate_sales_last_45_days() from public,anon,authenticated;
grant execute on function public.truncate_sales_last_45_days() to service_role;
notify pgrst,'reload schema';
