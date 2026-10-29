-- Join thin evidence before serialization; avoid unpacking and rebuilding a
-- complete 5,000-row JSON register. Snapshot/order/quantity semantics are kept.
create or replace function public.get_stock_catalog_register_batch(p_offset integer default 0,p_limit integer default 5000)
returns jsonb language sql stable set search_path='' set enable_nestloop='off' as $$
 with page as materialized (
   select item_code,payload from public.stock_catalog_snapshot order by item_code
   limit least(greatest(p_limit,1),5000) offset greatest(p_offset,0)
 ) select jsonb_build_object(
   'rows',coalesce((select jsonb_agg(
     (p.payload-'distribution_orders'-'branch_stock'-'branch_demand'-'monthly_sales'-'current_month_branch_sales'-'daily_sales_45d'-'daily_sales_45d_available'-'meta')
     ||jsonb_build_object('supply_insight',coalesce(i.summary,
       '{"status":"pending","scope":"STORE","confidence":"unavailable"}'::jsonb)
       ||jsonb_build_object('generated_at',i.updated_at)) order by p.item_code)
     from page p left join public.stock_supply_insights i using(item_code)),'[]'::jsonb),
   'total',(select count(*) from public.stock_catalog_snapshot),
   'snapshot_at',coalesce((select payload->'meta'->>'refreshed_at' from public.stock_catalog_snapshot limit 1),''));
$$;

CREATE OR REPLACE FUNCTION public.get_stock_management_register_batch(p_offset integer DEFAULT 0, p_limit integer DEFAULT 5000)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
 SET enable_nestloop TO 'off'
AS $function$
 with page as materialized (
    select item_code,last_mrn_date,payload from public.stock_management_snapshot
    order by last_mrn_date desc,item_code
    limit least(greatest(coalesce(p_limit,5000),1),5000) offset greatest(coalesce(p_offset,0),0)
  ), receipts as materialized (
    select p.item_code,min(m.expiry_date) filter(where coalesce(m.received_quantity,0)>0) expiry_date,
      sum(coalesce(m.ordered_quantity,0)) ordered_quantity,
      sum(coalesce(m.received_quantity,0)) received_quantity,
      min(nullif(btrim(m.vendor),'')) vendor,
      count(distinct coalesce(m.mrn_no,'')) receipt_count,
      count(distinct m.expiry_date) filter(where coalesce(m.received_quantity,0)>0) expiry_count
    from page p join public.mrn_apg_2026 m
      on btrim(m.item_code)=p.item_code and m.mrn_date=p.last_mrn_date
    where lower(btrim(m.status))='approved'
      and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
    group by p.item_code
  )
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(
      (p.payload-'branches'-'monthly_sales'-'meta'-'branch_year_sales'-'receipt_lines') ||
      jsonb_build_object('receipt_scope','latest_mrn_date',
        'receipt_count',r.receipt_count,'expiry_count',r.expiry_count,
        'vendor',left(upper(r.vendor),10),'expiry_date',r.expiry_date,
        'ordered_quantity',r.ordered_quantity,'received_quantity',r.received_quantity,
        'last_mrn_qty',coalesce(r.received_quantity,(p.payload->>'last_mrn_qty')::numeric))
      ||jsonb_build_object('supply_insight',coalesce(i.summary,
        '{"status":"pending","scope":"STORE","confidence":"unavailable"}'::jsonb)
        ||jsonb_build_object('generated_at',i.updated_at))
      order by p.last_mrn_date desc,p.item_code)
      from page p left join receipts r using(item_code)
      left join public.stock_supply_insights i using(item_code)),'[]'::jsonb),
    'total',(select count(*) from public.stock_management_snapshot),
    'snapshot_at',(select max(updated_at) from public.stock_management_snapshot));
$function$;
notify pgrst,'reload schema';
