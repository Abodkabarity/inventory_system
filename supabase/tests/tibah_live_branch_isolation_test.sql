-- All branch, Max, order and audit fixtures roll back. The shared 4000-row
-- batch is exercised under the authenticated role's 8-second API timeout.
begin;
set local statement_timeout='8s';
do $test$
declare
  inventory_id uuid; store_id uuid; branch_id uuid;
  upp_branch constant text := 'Tibah UPP'; regular_branch constant text := 'tibah regular';
  a text; b text; upp uuid; regular uuid; next_upp uuid; rival uuid; bulk uuid;
  staged jsonb; result jsonb; before_other text;
begin
  select user_id into strict inventory_id from public.app_users where role='inventory' and is_active=true limit 1;
  select user_id into strict store_id from public.app_users where role='store' and is_active=true limit 1;
  select user_id into strict branch_id from public.app_users where role='branch' and is_active=true limit 1;
  perform set_config('request.jwt.claim.sub',inventory_id::text,true);
  assert exists(select 1 from public.branches where branch_name=upp_branch and is_active=true), 'Exact real branch missing';
  assert not exists(select 1 from public.branches where lower(btrim(branch_name))='tibah regular'), 'Regular fixture must not exist';
  assert not exists(select 1 from public.max_adj where branch_name=upp_branch), 'Use only before real trial Max is uploaded';
  insert into public.branches(branch_name,is_active,branch_group) values(regular_branch,true,'APG');
  select min(item_code),max(item_code) into a,b from (
    select distinct item_code from public.item_report
    where lower(coalesce(is_block::text,'')) not in ('true','t','1','yes','y')
    order by item_code limit 2) s;
  select md5(coalesce(string_agg(md5(to_jsonb(m)::text),'' order by id),'')) into before_other
    from public.max_adj m where branch_name not in (upp_branch,regular_branch);
  insert into public.max_adj(branch_name,item_code,qty,reason,max_adjustment_30d,current_demand_30d)
    values(upp_branch,b,7,'Previous',7,99),(regular_branch,b,8,'Previous',8,99);

  upp:=(public.tibah_max_order('begin','{"order_type":"UPP"}') ->>'id')::uuid;
  assert not exists(select 1 from public.max_adj where branch_name=upp_branch), 'Old Max was not cleared before parsing';
  begin
    perform public.tibah_max_order('configure',jsonb_build_object('id',upp,'total',0));
    raise exception 'Empty file was accepted';
  exception when sqlstate '22023' then null; end;
  assert not exists(select 1 from public.max_adj where branch_name=upp_branch), 'Empty-file failure restored old Max';
  perform public.tibah_max_order('configure',jsonb_build_object('id',upp,'total',2));
  staged:=jsonb_build_array(jsonb_build_object('item_code',a,'item_name','Uploaded UPP name','qty',20));
  perform public.tibah_max_order('stage',jsonb_build_object('id',upp,'rows',staged));
  begin
    perform public.tibah_max_order('commit',jsonb_build_object('id',upp));
    raise exception 'Incomplete file was accepted';
  exception when sqlstate '22023' then null; end;
  assert not exists(select 1 from public.max_adj where branch_name=upp_branch), 'Failed file retained old Max';
  begin
    perform public.tibah_max_order('stage',jsonb_build_object('id',upp,'rows',staged));
    raise exception 'Duplicate code was accepted';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.tibah_max_order('stage',jsonb_build_object('id',upp,'rows',jsonb_build_array(jsonb_build_object('item_code',b,'qty',1))));
    raise exception 'Missing Item Name was accepted';
  exception when sqlstate '22023' then null; end;
  perform public.tibah_max_order('stage',jsonb_build_object('id',upp,'rows',jsonb_build_array(jsonb_build_object('item_code',b,'item_name','Zero product','qty',0))));
  perform public.tibah_max_order('commit',jsonb_build_object('id',upp));
  assert (select count(*)=2 and bool_and(current_demand_30d=0 and adjustment_type='INCREASE' and reason='UPP') from public.max_adj where branch_name=upp_branch);
  assert (select item_name='Uploaded UPP name' from public.max_adj where branch_name=upp_branch and item_code=a);
  assert (select qty=8 and reason='Previous' from public.max_adj where branch_name=regular_branch and item_code=b), 'UPP erased Regular';

  regular:=(public.tibah_max_order('begin','{"order_type":"Regular","total":1}') ->>'id')::uuid;
  staged:=jsonb_build_array(jsonb_build_object('item_code',a,'item_name','Uploaded Regular name','qty',10));
  perform public.tibah_max_order('stage',jsonb_build_object('id',regular,'rows',staged));
  perform public.tibah_max_order('commit',jsonb_build_object('id',regular));
  assert (select count(*)=1 and bool_and(current_demand_30d=0 and adjustment_type='INCREASE' and reason='Regular' and qty=10) from public.max_adj where branch_name=regular_branch);
  assert (select count(*)=2 and bool_and(reason='UPP') from public.max_adj where branch_name=upp_branch), 'Regular erased UPP';
  assert jsonb_array_length(public.tibah_max_order('current')->'uploads')=2, 'Both branch cards must coexist';

  insert into public.daily_order(run_date,branch,item_code,max_adjustment_30d,reorder_qty_num) values
    ('2099-01-01',upp_branch,a,20,20),('2099-01-01',upp_branch,b,0,0),('2099-01-01',regular_branch,a,10,10);
  update public.daily_order set final_reorder_qty_store_stock_gt_0='7' where run_date='2099-01-01' and branch=upp_branch and item_code=a;
  assert public.tibah_max_order('current','{"order_type":"UPP"}')->'upload'->>'state'='preparing';
  update public.daily_order set final_reorder_qty_store_stock_gt_0='0' where run_date='2099-01-01' and branch=upp_branch and item_code=b;
  assert public.tibah_max_order('current','{"order_type":"UPP"}')->'upload'->>'state'='ready';
  assert public.tibah_max_order('current','{"order_type":"Regular"}')->'upload'->>'state'='preparing';
  update public.daily_order set final_reorder_qty_store_stock_gt_0='5' where run_date='2099-01-01' and branch=regular_branch;
  assert public.tibah_max_order('current','{"order_type":"Regular"}')->'upload'->>'state'='ready';
  result:=public.tibah_max_order('items',jsonb_build_object('id',upp,'limit',1,'after',a));
  assert result->'rows'->0->>'item_code'=b, 'Zero Qty was lost from completeness';
  update public.daily_order set final_reorder_qty_store_stock_gt_0='99' where run_date='2099-01-01' and branch=upp_branch and item_code=a;
  result:=public.tibah_max_order('items',jsonb_build_object('id',upp));
  assert result->'rows'->0->>'final_reorder_qty_store_stock_gt_0'='7', 'Ready snapshot was mutated';
  begin
    perform public.tibah_max_order('complete',jsonb_build_object('id',upp));
    raise exception 'Inventory completed Store work';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',store_id::text,true);
  perform public.tibah_max_order('complete',jsonb_build_object('id',upp));
  assert public.tibah_max_order('current','{"order_type":"UPP"}')->'upload'->>'state'='done';
  assert public.tibah_max_order('current','{"order_type":"Regular"}')->'upload'->>'state'='ready', 'UPP completion hid Regular';
  begin
    perform public.tibah_max_order('begin','{"order_type":"UPP","total":1}');
    raise exception 'Store uploaded Max';
  exception when insufficient_privilege then null; end;

  perform set_config('request.jwt.claim.sub',inventory_id::text,true);
  next_upp:=(public.tibah_max_order('begin','{"order_type":"UPP","total":1}')->>'id')::uuid;
  rival:=(public.tibah_max_order('begin','{"order_type":"UPP","total":1}')->>'id')::uuid;
  begin
    perform public.tibah_max_order('stage',jsonb_build_object('id',next_upp,'rows',staged));
    raise exception 'Superseded staging upload was accepted';
  exception when sqlstate 'PT409' then null; end;
  perform public.tibah_max_order('stage',jsonb_build_object('id',rival,'rows',staged));
  perform public.tibah_max_order('commit',jsonb_build_object('id',rival));
  begin
    perform public.tibah_max_order('commit',jsonb_build_object('id',next_upp));
    raise exception 'Stale competing file was accepted';
  exception when sqlstate 'PT409' then null; end;
  assert (select count(*)=1 from public.max_adj where branch_name=upp_branch), 'Same-type replacement kept obsolete rows';
  assert (select qty=10 from public.max_adj where branch_name=regular_branch and item_code=a);
  perform set_config('request.jwt.claim.sub',store_id::text,true);
  begin
    perform public.tibah_max_order('complete',jsonb_build_object('id',upp));
    raise exception 'Old completion finished the new file';
  exception when sqlstate 'PT409' then null; end;
  perform public.tibah_max_order('complete',jsonb_build_object('id',regular));
  assert public.tibah_max_order('current','{"order_type":"UPP"}')->'upload'->>'state'='preparing', 'Regular completion hid new UPP';

  update tibah_order_private.branch_controls set enabled=false;
  assert jsonb_array_length(public.tibah_max_order('current')->'uploads')=0;
  perform set_config('request.jwt.claim.sub',inventory_id::text,true);
  begin
    perform public.tibah_max_order('begin','{"order_type":"UPP","total":1}');
    raise exception 'Disabled temporary feature accepted an upload';
  exception when sqlstate '22023' then null; end;
  update tibah_order_private.branch_controls set enabled=true;
  perform set_config('request.jwt.claim.sub',branch_id::text,true);
  begin
    perform public.tibah_max_order('current');
    raise exception 'Branch account read special orders';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',inventory_id::text,true);
  update public.app_users set is_active=false where user_id=inventory_id;
  begin
    perform public.tibah_max_order('current');
    raise exception 'Inactive user read special orders';
  exception when insufficient_privilege then null; end;
  update public.app_users set is_active=true where user_id=inventory_id;
  assert not has_table_privilege('authenticated','tibah_order_private.branch_controls','select');
  assert not has_function_privilege('anon','public.tibah_max_order(text,jsonb)','execute');

  select jsonb_agg(jsonb_build_object('item_code',item_code,'item_name','Bulk product','qty',5)) into staged from (
    select distinct item_code from public.item_report where lower(coalesce(is_block::text,'')) not in ('true','t','1','yes','y')
    order by item_code limit 4000) s;
  assert jsonb_array_length(staged)=4000;
  bulk:=(public.tibah_max_order('begin','{"order_type":"Regular","total":4000}')->>'id')::uuid;
  result:=public.tibah_max_order('stage',jsonb_build_object('id',bulk,'rows',staged));
  assert result->>'received'='4000';
  perform public.tibah_max_order('commit',jsonb_build_object('id',bulk));
  assert (select count(*)=4000 and bool_and(current_demand_30d=0 and adjustment_type='INCREASE') from public.max_adj where branch_name=regular_branch);
  assert (select count(*)=1 from public.max_adj where branch_name=upp_branch);
  -- A failed replacement must remove an already visible pending Store request,
  -- even when no valid new rows ever reach staging.
  regular:=(public.tibah_max_order('begin','{"order_type":"Regular"}')->>'id')::uuid;
  assert (select state='superseded' from tibah_order_private.uploads where id=bulk), 'Old Store request survived clear-first';
  assert not exists(select 1 from public.max_adj where branch_name=regular_branch);
  begin
    perform public.tibah_max_order('stage',jsonb_build_object('id',regular,'rows',jsonb_build_array(
      jsonb_build_object('item_code',a,'item_name','Invalid replacement','qty',-1))));
    raise exception 'Invalid replacement Qty was accepted';
  exception when sqlstate '22023' then null; end;
  assert not exists(select 1 from public.max_adj where branch_name=regular_branch), 'Failed stage restored previous Max';
  assert public.tibah_max_order('current','{"order_type":"Regular"}')->'upload'->>'state'='staging', 'Failed file became a pending Store request';
  assert public.tibah_max_order('current','{"order_type":"UPP"}')->'upload'->>'state'='preparing', 'Failed Regular file hid UPP';
  assert (select count(*)=1 from public.max_adj where branch_name=upp_branch);
  assert (select md5(coalesce(string_agg(md5(to_jsonb(m)::text),'' order by id),''))=before_other from public.max_adj m
    where branch_name not in (upp_branch,regular_branch)), 'Ordinary Max rows changed';
end;
$test$;
rollback;
