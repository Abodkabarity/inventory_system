-- Run as the database owner. All session changes and test effects roll back.
begin;
select set_config('request.jwt.claims',jsonb_build_object(
  'role','authenticated',
  'sub',(select user_id from public.app_users
    where role='category' and is_active is true limit 1)
)::text,true);
set local role authenticated;
do $test$
begin
  if not stock_management_private.is_view_user() then
    raise exception 'Category stock reader was denied';
  end if;
  if jsonb_array_length(public.get_stock_catalog_register_batch(0,1)->'rows')<>1
    or jsonb_array_length(public.get_stock_management_register_batch(0,1)->'rows')<>1
    or jsonb_array_length(public.get_stock_mrn_cd_register_batch(0,1)->'rows')<>1 then
    raise exception 'Category cannot read the prepared stock registers';
  end if;
  if public.prepare_stock_expiry_workspace(null) is null
    or public.get_stock_expiry_page(p_limit=>1) is null then
    raise exception 'Category cannot read Near Expiry';
  end if;
  begin
    perform public.refresh_stock_catalog();
    raise exception 'Category rebuilt Overview';
  exception when insufficient_privilege then null; end;
  begin
    perform public.refresh_stock_management_snapshot();
    raise exception 'Category rebuilt MRN';
  exception when insufficient_privilege then null; end;
  begin
    perform public.refresh_stock_expiry_watch();
    raise exception 'Category started expiry discovery';
  exception when insufficient_privilege then null; end;
  begin
    perform public.save_stock_expiry_review('test',date '2027-01-01',
      'test','test','note',null,date '2026-11-01');
    raise exception 'Category changed an expiry review';
  exception when insufficient_privilege then null; end;
  begin
    perform online_overview_private.assert_access();
    raise exception 'Category acquired Online Overview access';
  exception when insufficient_privilege then null; end;
end;
$test$;
select 'Category stock reads allowed; writes and Online Overview denied' as result;
rollback;
