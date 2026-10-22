-- Uses an existing active view user, and rolls back every session setting.
begin;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select user_id from public.app_users
    where lower(btrim(role))='view' and is_active is not false limit 1),
  'role','authenticated')::text,true);
set local role authenticated;
do $$
declare state_before jsonb; state_after jsonb; payload jsonb; denied boolean;
begin
  if auth.uid() is null then raise exception 'An active view test user is required'; end if;
  if not stock_management_private.is_view_user() then raise exception 'View role unresolved'; end if;
  if public.item_tracker_my_role() is not null then raise exception 'Viewer acquired a back-office role'; end if;
  if not exists(select 1 from public.stock_catalog_snapshot) then raise exception 'Overview inaccessible'; end if;
  if not exists(select 1 from public.stock_management_snapshot) then raise exception 'MRN inaccessible'; end if;
  state_before := public.get_stock_workspace_cache_state();
  if state_before->>'mrn' is null or state_before->>'expiry' is null then
    raise exception 'Cache validation inaccessible';
  end if;
  state_after := public.prepare_stock_expiry_workspace(null);
  if state_before is distinct from state_after then raise exception 'Viewer changed cache revisions'; end if;
  payload := public.get_stock_catalog_page(p_limit=>1);
  if jsonb_array_length(payload->'rows')<>1 then raise exception 'Overview RPC inaccessible'; end if;
  payload := public.get_stock_management_page(p_limit=>1);
  if jsonb_array_length(payload->'rows')<>1 then raise exception 'MRN RPC inaccessible'; end if;
  payload := public.get_stock_expiry_page(p_limit=>1);
  if payload->'total' is null then raise exception 'Expiry RPC inaccessible'; end if;
  payload := public.get_fill_rate_report_v1('1900-01-01','1900-01-01',null,1);
  if payload->'summaries' is null then raise exception 'Fill Rate RPC inaccessible'; end if;
  perform 1 from public.availability_branch_summary_cache_v2 limit 1;
  perform 1 from public.availability_branch_master_cache limit 1;
  perform 1 from public.availability_kpi_purchase_status limit 1;
  perform 1 from public.branches where branch_group='71' limit 1;

  denied := false;
  begin perform public.refresh_stock_catalog();
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Viewer rebuilt catalog'; end if;
  denied := false;
  begin perform public.refresh_stock_management_snapshot();
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Viewer rebuilt MRN snapshot'; end if;
  denied := false;
  begin perform public.refresh_stock_expiry_watch();
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Viewer started expiry discovery'; end if;
  denied := false;
  begin perform public.save_stock_expiry_review('__view_test__','2026-01-01','','test','note',null);
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Viewer saved a review'; end if;
end;
$$;
reset role;
-- Deactivation must revoke viewer reads even within an existing JWT session.
update public.app_users set is_active=false where user_id=auth.uid();
set local role authenticated;
do $$
begin
  if stock_management_private.is_view_user()
    or exists(select 1 from public.stock_catalog_snapshot)
    or exists(select 1 from public.stock_management_snapshot)
    or public.get_stock_workspace_cache_state() is not null then
    raise exception 'Inactive viewer retained stock access';
  end if;
end;
$$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select user_id from public.app_users where role='inventory' and is_active is not false limit 1),
  'role','authenticated')::text,true);
set local role authenticated;
do $$
begin
  if public.item_tracker_my_role() is distinct from 'inventory'
    or public.get_stock_workspace_cache_state() is null
    or not exists(select 1 from public.stock_management_snapshot) then
    raise exception 'Existing inventory access regressed';
  end if;
end;
$$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select user_id from public.app_users where role='category' and is_active is not false limit 1),
  'role','authenticated')::text,true);
set local role authenticated;
do $$
begin
  if auth.uid() is null then raise exception 'An active category test user is required'; end if;
  if stock_management_private.is_view_user()
    or exists(select 1 from public.stock_catalog_snapshot)
    or public.get_stock_workspace_cache_state() is not null then
    raise exception 'Unrelated role acquired stock access';
  end if;
end;
$$;
select 'viewer reads, write denials, deactivation and existing roles passed' as result;
rollback;
