begin;
do $test$
declare actor record; allowed boolean; expected_catalog bigint; expected_mrn bigint; outside_branch text;
begin
 select count(*) into expected_catalog from public.stock_catalog_snapshot;
 select count(*) into expected_mrn from public.stock_management_snapshot;
 select s.branch_name into outside_branch from public.sales_history s
 where s.branch_name in (select branch_name from public.branches where zone is distinct from 'Main') limit 1;
 for actor in select user_id,zone from public.app_users where role='zone_manager' and is_active is true loop
  perform set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor.user_id)::text,true);
  execute 'set local role authenticated';
  allowed:=public.can_read_main_zone_stock();
  if allowed is distinct from (actor.zone='Main') then raise exception 'Wrong stock exception for %',actor.zone; end if;
  if allowed then
   if (select count(*) from public.stock_catalog_snapshot)<>expected_catalog or
      (select count(*) from public.stock_management_snapshot)<>expected_mrn then
     raise exception 'Main did not receive full registers';
   end if;
   if jsonb_array_length(public.get_stock_catalog_register_batch(0,1)->'rows')<>1 or
      jsonb_array_length(public.get_stock_management_register_batch(0,1)->'rows')<>1 or
      jsonb_array_length(public.get_stock_mrn_cd_register_batch(0,1)->'rows')<>1 then
     raise exception 'Main register RPC denied';
   end if;
   if public.prepare_stock_expiry_workspace(null) is null or
      public.get_stock_expiry_page(p_limit=>1) is null then raise exception 'Main expiry denied'; end if;
   if outside_branch is null or not exists(select 1 from public.sales_history where branch_name=outside_branch) then
     raise exception 'Main cannot read sales outside its zone';
   end if;
   begin perform public.refresh_stock_catalog(); raise exception 'Main rebuilt catalog';
   exception when insufficient_privilege then null; end;
   begin perform public.refresh_stock_management_snapshot(); raise exception 'Main rebuilt MRN';
   exception when insufficient_privilege then null; end;
   begin perform public.refresh_stock_expiry_watch(); raise exception 'Main started discovery';
   exception when insufficient_privilege then null; end;
   begin perform public.save_stock_expiry_review('test',date '2027-01-01','test','test','note',null,date '2026-11-01');
     raise exception 'Main changed review';
   exception when insufficient_privilege then null; end;
  else
   if exists(select 1 from public.stock_catalog_snapshot) or stock_management_private.is_view_user() then
     raise exception 'Other zone acquired global stock';
   end if;
  end if;
  begin perform online_overview_private.assert_access(); raise exception 'Zone received Online Overview';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
 end loop;
end $test$;
select 'Main global read verified; other zones, writes and Online Overview denied' as result;
rollback;
