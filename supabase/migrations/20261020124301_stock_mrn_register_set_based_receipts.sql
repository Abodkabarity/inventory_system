-- Aggregate matching receipt facts once for the entire batch. This keeps RLS
-- checks statement-scoped rather than repeating an MRN subquery per product.
-- Preserve the earliest expiry, exact MRN identity, vendor fallback and 5000 cap.
create or replace function public.get_stock_management_register_batch(
 p_offset integer default 0,p_limit integer default 5000)
-- CTE cardinality estimates otherwise favor a quadratic nested-loop join of
-- two ~5000-row receipt summaries. This planner setting applies only inside
-- this bulk RPC and is restored automatically when the function returns.
returns jsonb language sql stable security invoker set search_path=''
set enable_nestloop=off as $$
with page as materialized (
    select item_code,last_mrn_date,payload,coalesce(payload->>'last_mrn_no','') mrn_no
    from public.stock_management_snapshot
    order by last_mrn_date desc,item_code
    limit least(greatest(coalesce(p_limit,5000),1),5000)
    offset greatest(coalesce(p_offset,0),0)
  ), receipts as materialized (
    select p.item_code,m.expiry_date,
      sum(coalesce(m.ordered_quantity,0)) ordered_quantity,
      sum(coalesce(m.received_quantity,0)) received_quantity,
      min(nullif(btrim(m.vendor),'')) vendor
    from page p join public.mrn_apg_2026 m
      on m.item_code=p.item_code and m.mrn_date=p.last_mrn_date
      and coalesce(m.mrn_no,'')=p.mrn_no
    where coalesce(m.received_quantity,0)>0
      and lower(btrim(m.status))='approved'
      and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
    group by p.item_code,m.expiry_date
  ), first_expiry as materialized (
    select distinct on(item_code) * from receipts where expiry_date is not null
    order by item_code,expiry_date
  ), fallback_vendor as (
    select item_code,min(vendor) vendor from receipts group by item_code
  )
  select jsonb_build_object(
    'rows',coalesce((
      select jsonb_agg(
        (p.payload-'branches'-'monthly_sales'-'meta') ||
        jsonb_build_object(
          'vendor',left(upper(case when e.expiry_date is null then v.vendor else e.vendor end),10),
          'expiry_date',e.expiry_date,'ordered_quantity',e.ordered_quantity,
          'received_quantity',e.received_quantity)
        order by p.last_mrn_date desc,p.item_code)
      from page p left join first_expiry e using(item_code)
      left join fallback_vendor v using(item_code)
    ),'[]'::jsonb),
    'total',(select count(*) from public.stock_management_snapshot),
    'snapshot_at',(select max(updated_at) from public.stock_management_snapshot)
  );
$$;
revoke all on function public.get_stock_management_register_batch(integer,integer) from public,anon;
grant execute on function public.get_stock_management_register_batch(integer,integer) to authenticated,service_role;
notify pgrst,'reload schema';
