-- Compare actual authenticated RPC payloads in one consistent snapshot.
-- These reads use the same 5,000-row batches as the app and its exports.
-- No credentials or user identities are returned. Everything rolls back.
begin isolation level repeatable read;
do $test$
declare
  inventory_user uuid;
  view_user uuid;
  check_name text;
  check_sql text;
  role_name text;
  payload jsonb;
  baseline text;
  results jsonb := '[]'::jsonb;
begin
  select user_id into inventory_user from public.app_users
    where role='inventory' and is_active is not false limit 1;
  select user_id into view_user from public.app_users
    where role='view' and is_active is not false limit 1;
  if inventory_user is null or view_user is null then
    raise exception 'Active inventory and view test users are required';
  end if;

  for check_name,check_sql in select * from (values
    ('source_visibility',$q$
      select jsonb_build_object(
        'receipts',exists(select 1 from public.mrn_apg_2026),
        'sales_2025',exists(select 1 from public.sales_history_2025),
        'catalog_revisions',(select jsonb_object_agg(source,revision) from public.stock_catalog_cache_revisions))
    $q$),
    ('workspace_versions',$q$select public.get_stock_workspace_cache_state()$q$),
    ('catalog_versions',$q$select jsonb_build_array(
      stock_management_private.catalog_cache_version(false),
      stock_management_private.catalog_cache_version(true))$q$),
    ('overview_page',$q$select public.get_stock_catalog_page(p_limit=>1)$q$),
    ('overview_complete_register',$q$
      with batches as materialized (
        select n,public.get_stock_catalog_register_batch(n,5000) payload
        from generate_series(0,greatest((select count(*)::int-1 from public.stock_catalog_snapshot),0),5000) n
      ) select jsonb_build_object('rows',sum(jsonb_array_length(payload->'rows')),
        'digest',md5(string_agg(payload::text,'|' order by n))) from batches
    $q$),
    ('mrn_page',$q$select public.get_stock_management_page(p_limit=>1)$q$),
    ('mrn_complete_register',$q$
      with batches as materialized (
        select n,public.get_stock_management_register_batch(n,5000) payload
        from generate_series(0,greatest((select count(*)::int-1 from public.stock_management_snapshot),0),5000) n
      ) select jsonb_build_object('rows',sum(jsonb_array_length(payload->'rows')),
        'digest',md5(string_agg(payload::text,'|' order by n))) from batches
    $q$),
    ('overview_product_details',$q$
      select jsonb_agg(public.get_stock_catalog_item(s.item_code) order by s.item_code)
      from (select item_code from public.stock_catalog_snapshot order by item_code limit 3) s
    $q$),
    ('overview_cached_details',$q$
      select public.get_stock_catalog_item_if_changed(
        (select item_code from public.stock_catalog_snapshot order by item_code limit 1),
        stock_management_private.catalog_cache_version(true))
    $q$),
    ('mrn_product_details',$q$
      select jsonb_agg(public.get_stock_management_product_details(s.item_code) order by s.item_code)
      from (select item_code from public.stock_management_snapshot order by last_mrn_date desc,item_code limit 3) s
    $q$),
    ('expiry_complete_register',$q$
      with batches as materialized (
        select n,public.get_stock_expiry_page(p_review_state=>'all',p_offset=>n,p_limit=>5000) payload
        from generate_series(0,greatest((select count(*)::int-1 from public.stock_expiry_candidates),0),5000) n
      ) select jsonb_build_object('rows',sum(jsonb_array_length(payload->'rows')),
        'digest',md5(string_agg(payload::text,'|' order by n))) from batches
    $q$),
    ('expiry_product_details',$q$
      select jsonb_agg(public.get_stock_expiry_item(s.item_code,s.expiry_date) order by s.item_code,s.expiry_date)
      from (select item_code,expiry_date from public.stock_expiry_candidates order by item_code,expiry_date limit 3) s
    $q$),
    ('availability_branch_summaries',$q$
      select coalesce(jsonb_agg(to_jsonb(c) order by branch_name),'[]'::jsonb)
      from public.availability_branch_summary_cache_v2 c
      where run_date=(select max(run_date) from public.availability_branch_summary_cache_v2)
    $q$),
    ('availability_master_and_stock',$q$
      with sample_branches as materialized (
        select distinct on(branch_group) branch_name from public.branches
        where is_active and branch_group in ('71','APG') order by branch_group,branch_name
      ) select jsonb_build_object(
        'master',(select coalesce(jsonb_agg(to_jsonb(c) order by c.branch_name,c.item_code),'[]'::jsonb)
          from public.availability_branch_master_cache c join sample_branches b using(branch_name)),
        'stock',(select coalesce(jsonb_agg(to_jsonb(d) order by d.branch,d.item_code),'[]'::jsonb)
          from public.daily_order d join sample_branches b on b.branch_name=d.branch
          where d.run_date=(select max(run_date) from public.daily_order)))
    $q$),
    ('fill_rate_kpi',$q$
      select public.get_fill_rate_report_v1(
        (select max(run_date) from public.refail_order),
        (select max(run_date) from public.refail_order),null,5000)
    $q$)
  ) checks(name,sql_text) loop
    foreach role_name in array array['inventory','view'] loop
      perform set_config('request.jwt.claims',jsonb_build_object(
        'sub',case when role_name='inventory' then inventory_user else view_user end,
        'role','authenticated')::text,true);
      execute 'set local role authenticated';
      execute check_sql into payload;
      execute 'reset role';
      if payload is null then raise exception '% returned no payload for %',check_name,role_name; end if;
      if check_name='source_visibility' and
        (payload->>'receipts'<>'true' or payload->>'sales_2025'<>'true' or payload->'catalog_revisions'='null'::jsonb) then
        raise exception 'Incomplete underlying source access for %',role_name;
      end if;
      if check_name='workspace_versions' and payload->>'details' is null then
        raise exception 'Product cache validation missing for %',role_name;
      end if;
      if check_name='catalog_versions' and (payload->>0 is null or payload->>1 is null) then
        raise exception 'Overview cache validation missing for %',role_name;
      end if;
      if role_name='inventory' then
        baseline := md5(payload::text);
      elsif md5(payload::text) is distinct from baseline then
        raise exception 'Inventory/view payload mismatch in %',check_name;
      end if;
    end loop;
    results := results || jsonb_build_array(jsonb_build_object(
      'check',check_name,'equal',true,'rows',payload->'rows','digest',baseline));
  end loop;
  perform set_config('stock_parity.results',results::text,true);
end;
$test$;
select current_setting('stock_parity.results')::jsonb as role_parity_results;
rollback;
