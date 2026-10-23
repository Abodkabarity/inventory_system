-- Verify rebuilt registers against the common effective balances and detail RPCs.
-- Run after both stock refresh states report complete.
begin isolation level repeatable read;
create temporary table expected_effective_stock on commit drop as
  select * from stock_management_private.effective_stock_balances();
create temporary table expected_product_stock on commit drop as
  select item_code,
    coalesce(sum(qty) filter(where branch_key='store'),0) store_stock,
    coalesce(sum(qty) filter(where branch_key<>'store'),0) branches_stock,
    coalesce(sum(base_qty) filter(where branch_key<>'store'),0) branches_base_stock,
    coalesce(sum(final_qty) filter(where branch_key<>'store'),0) branches_final_reorder,
    coalesce(sum(qty) filter(where branch_group='APG'),0) apg_stock,
    coalesce(sum(qty) filter(where branch_group='71'),0) stock_71,
    count(*) filter(where branch_key<>'store' and qty>0) stocked_branches
  from expected_effective_stock group by item_code;
create temporary table published_stock on commit drop as
  select 'overview' workspace,item_code,payload from public.stock_catalog_snapshot
  union all select 'mrn',item_code,payload from public.stock_management_snapshot
  union all select 'expiry_saved',item_code,product_data from public.stock_expiry_alert_receipts;
do $test$
declare mismatches bigint; actor uuid; details jsonb; code text;
begin
  if exists(select 1 from public.stock_catalog_refresh_state where status<>'complete')
    or exists(select 1 from public.stock_management_refresh_state where status<>'complete') then
    raise exception 'Wait for both stock refreshes to finish';
  end if;
  select count(*) into mismatches from published_stock s
    left join expected_product_stock e using(item_code)
    where (s.payload->>'branches_stock')::numeric is distinct from coalesce(e.branches_stock,0)
      or (s.payload->>'branches_base_stock')::numeric is distinct from coalesce(e.branches_base_stock,0)
      or (s.payload->>'branches_final_reorder')::numeric is distinct from coalesce(e.branches_final_reorder,0)
      or (s.payload->>'store_stock')::numeric is distinct from coalesce(e.store_stock,0)
      or (s.payload->>'total_stock')::numeric is distinct from coalesce(e.store_stock,0)+coalesce(e.branches_stock,0)
      or (s.payload->'meta'->>'order_run_date')::date is distinct from (select max(run_date) from public.daily_order);
  if mismatches>0 then raise exception '% published stock totals/source dates differ',mismatches; end if;
  select count(*) into mismatches from published_stock s
    left join expected_product_stock e using(item_code)
    where s.workspace<>'overview'
      and (s.payload->>'stocked_branches')::bigint is distinct from coalesce(e.stocked_branches,0);
  if mismatches>0 then raise exception '% stocked branch counts differ',mismatches; end if;
  select count(*) into mismatches from published_stock s
    left join expected_product_stock e using(item_code)
    where s.workspace='overview' and (
      (s.payload->>'apg_branches_stock')::numeric is distinct from coalesce(e.apg_stock,0)
      or (s.payload->>'stock_71')::numeric is distinct from coalesce(e.stock_71,0));
  if mismatches>0 then raise exception '% APG/71 totals differ',mismatches; end if;
  select count(*) into mismatches from published_stock s
    cross join lateral jsonb_each(s.payload->'branch_stock') b
    left join expected_effective_stock e on e.item_code=s.item_code and e.branch_key=b.key
    where s.workspace='overview' and ((b.value->>'stock')::numeric is distinct from e.qty);
  if mismatches>0 then raise exception '% Overview branch balances differ',mismatches; end if;
  select count(*) into mismatches from published_stock s
    cross join lateral jsonb_array_elements(s.payload->'branches') b
    left join expected_effective_stock e
      on e.item_code=s.item_code and e.branch_key=public._norm_text(b->>'branch')
    where s.workspace<>'overview' and ((b->>'stock')::numeric is distinct from e.qty);
  if mismatches>0 then raise exception '% MRN/expiry branch balances differ',mismatches; end if;
  select count(*) into mismatches from published_stock s
    where (s.payload->>'days_on_hand')::numeric is distinct from
      case when (s.payload->>'total_stock')::numeric<=0 then 0
        when (s.payload->>'daily_sales')::numeric>0
          then (s.payload->>'total_stock')::numeric/(s.payload->>'daily_sales')::numeric end
      and abs(coalesce((s.payload->>'days_on_hand')::numeric,0) -
        case when (s.payload->>'total_stock')::numeric<=0 then 0
          when (s.payload->>'daily_sales')::numeric>0
            then (s.payload->>'total_stock')::numeric/(s.payload->>'daily_sales')::numeric else 0 end)>0.000001;
  if mismatches>0 then raise exception '% days-on-hand values differ',mismatches; end if;
  select count(*) into mismatches from published_stock s where
    s.payload->>'stock_status' is distinct from
      case when (s.payload->>'total_stock')::numeric<=0 then 'no_stock'
        when coalesce((s.payload->>'daily_sales')::numeric,0)<=0 then 'no_sales'
        when (s.payload->>'total_stock')::numeric/(s.payload->>'daily_sales')::numeric<30 then 'low_cover'
        else 'in_stock' end;
  if mismatches>0 then raise exception '% stock statuses differ',mismatches; end if;
  select count(*) into mismatches from public.stock_catalog_snapshot s
    cross join lateral (
      select count(*) filter(where (o.value->>'eligible')::boolean
          and coalesce((s.payload->'branch_stock'->o.key->>'stock')::numeric,0)>0) covered,
        count(*) filter(where (o.value->>'eligible')::boolean
          and coalesce((s.payload->'branch_stock'->o.key->>'stock')::numeric,0)<=0) uncovered
      from jsonb_each(s.payload->'distribution_orders')o
    ) c where s.payload->'distribution'->>'run_date' is not null and (
      (s.payload->'distribution'->>'stocked')::bigint is distinct from c.covered
      or (s.payload->'distribution'->>'covered')::bigint is distinct from c.covered
      or (s.payload->'distribution'->>'uncovered')::bigint is distinct from c.uncovered);
  if mismatches>0 then raise exception '% distribution counts ignore effective balances',mismatches; end if;
  select user_id into actor from public.app_users where role='inventory' and is_active limit 1;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor::text,'role','authenticated')::text,true);
  foreach code in array array['16-01-00184','16-01-00225','16-01-00231'] loop
    execute 'set local role authenticated';
    details:=public.get_stock_catalog_item(code);
    execute 'reset role';
    if details is null then raise exception 'Missing representative details %',code; end if;
    select count(*) into mismatches from jsonb_array_elements(details->'branches') b
      left join expected_effective_stock e on e.item_code=code and e.branch_key=public._norm_text(b->>'branch')
      where (b->>'stock')::numeric is distinct from coalesce(e.qty,0);
    if mismatches>0 then raise exception 'Detail RPC branch balances differ for %',code; end if;
  end loop;
end;
$test$;
select jsonb_build_object('rows',(select jsonb_object_agg(workspace,rows) from
  (select workspace,count(*) rows from published_stock group by workspace)c),
  'zero_stock_with_final',(select count(*) from expected_effective_stock where base_qty=0 and final_qty>0 and qty>0),
  'result','all balances, counts, APG/71 totals, coverage, statuses, source dates and detail RPCs passed') as effective_stock_results;
rollback;
