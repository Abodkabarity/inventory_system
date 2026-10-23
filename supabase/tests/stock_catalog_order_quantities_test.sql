-- Integration assertions against uploaded Daily Order data; no rows are modified.
begin;
do $test$
declare mismatch_count bigint; expected_branches bigint; actor uuid; page jsonb; item jsonb;
begin
  if (select status from public.stock_catalog_refresh_state where singleton)<>'complete' then
    raise exception 'Wait for the catalog refresh to complete before verifying';
  end if;
  create temporary table expected_order_branches on commit drop as
    select distinct public._norm_text(b.branch_name) branch_key from public.branches b
    where b.is_active is true and public._norm_text(b.branch_name) not in
      ('store','main virtual','new virtual','store - expired item','store-ws')
      and (lower(btrim(coalesce(b.branch_type,'')))<>'online' or exists (
        select 1 from public.daily_order d where d.run_date=(select max(run_date) from public.daily_order)
          and public._norm_text(d.branch)=public._norm_text(b.branch_name)));
  select count(*) into expected_branches from expected_order_branches;
  if exists(select 1 from public.stock_catalog_snapshot
    where (payload->'distribution'->>'active')::integer is distinct from expected_branches::integer
      and payload->'distribution'->>'run_date' is not null) then
    raise exception 'Participating branches, including Online/APG/71, were omitted';
  end if;

  create temporary table expected_branch_quantities on commit drop as
    select btrim(d.item_code) item_code,public._norm_text(d.branch) branch_key,
      greatest(max(coalesce(d.reorder_qty_num,0)),0) reorder_qty,
      greatest(max(coalesce(d.total_final_reorder_today,0)),0) final_qty
    from public.daily_order d join expected_order_branches b on b.branch_key=public._norm_text(d.branch)
    where d.run_date=(select max(run_date) from public.daily_order)
    group by btrim(d.item_code),public._norm_text(d.branch);

  select count(*) into mismatch_count from public.stock_catalog_snapshot s
    cross join lateral jsonb_each(s.payload->'distribution_orders') o
    full join expected_branch_quantities e on e.item_code=s.item_code and e.branch_key=o.key
    where (s.item_code is not null or exists(select 1 from public.stock_catalog_snapshot x where x.item_code=e.item_code))
      and (o.value is null or e.item_code is null
        or (o.value->>'reorder_qty')::numeric is distinct from e.reorder_qty
        or (o.value->>'final_qty')::numeric is distinct from e.final_qty);
  if mismatch_count<>0 then raise exception '% branch quantities differ from Daily Order',mismatch_count; end if;

  select count(*) into mismatch_count from public.stock_catalog_snapshot s
    cross join lateral (
      select count(*) filter(where (o.value->>'eligible')::boolean and (o.value->>'reorder_qty')::numeric>0) reorder_count,
        count(*) filter(where (o.value->>'eligible')::boolean and (o.value->>'final_qty')::numeric>0) final_count,
        coalesce(sum((o.value->>'reorder_qty')::numeric) filter(where (o.value->>'eligible')::boolean),0) reorder_qty,
        coalesce(sum((o.value->>'final_qty')::numeric) filter(where (o.value->>'eligible')::boolean),0) final_qty
      from jsonb_each(s.payload->'distribution_orders') o
    ) a where s.payload->'distribution'->>'run_date' is not null and (
      (s.payload->'distribution'->>'reorder')::bigint<>a.reorder_count or
      (s.payload->'distribution'->>'final')::bigint<>a.final_count or
      (s.payload->'distribution'->>'reorder_qty')::numeric<>a.reorder_qty or
      (s.payload->'distribution'->>'final_qty')::numeric<>a.final_qty);
  if mismatch_count<>0 then raise exception '% product branch counts or totals differ',mismatch_count; end if;

  select user_id into actor from public.app_users where role='inventory' and is_active limit 1;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  execute 'set local role authenticated';
  page:=public.get_stock_catalog_register_batch(0,5000);
  if not exists(select 1 from jsonb_array_elements(page->'rows') r where r->'distribution' is not null) then
    raise exception 'Register RPC omitted distribution facts';
  end if;
  item:=public.get_stock_catalog_item((page->'rows'->0->>'item_code'));
  if item->'distribution' is distinct from page->'rows'->0->'distribution' then
    raise exception 'Details and register disagree on branch requests';
  end if;
end;
$test$;
rollback;
