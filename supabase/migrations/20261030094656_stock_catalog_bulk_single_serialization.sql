-- Preserve the existing RPC contract; serialize the register only once.
-- Source/snapshot rows, receipt scope, RLS, timeout and bulk limits are unchanged.
set local lock_timeout = '3s';

create or replace function public.get_stock_catalog_register_batch(
  p_offset integer default 0, p_limit integer default 5000
) returns jsonb language sql stable security invoker
set search_path = '' set enable_nestloop = 'off'
as $function$
with page as materialized (
  select item_code, payload
  from public.stock_catalog_snapshot
  order by item_code
  limit least(greatest(p_limit, 1), 5000) offset greatest(p_offset, 0)
), codes as materialized (
  -- Enrichment has always matched the payload identity, not a display label.
  select distinct payload->>'item_code' item_code from page
), purchase as materialized (
  select s.item_code,
    string_agg(distinct nullif(btrim(s.status_name), ''), ' · '
      order by nullif(btrim(s.status_name), '')) status_name
  from public.availability_kpi_purchase_status s join codes c using(item_code)
  group by s.item_code
), latest as materialized (
  -- Catalog references cover all approved source warehouses, as before.
  select btrim(m.item_code) item_code, max(m.mrn_date) mrn_date
  from public.mrn_apg_2026 m join codes c on c.item_code=btrim(m.item_code)
  where lower(btrim(m.status))='approved'
  group by btrim(m.item_code)
), refs as materialized (
  select t.item_code, t.mrn_date,
    sum(coalesce(m.total_qty, 0)) total_qty,
    sum(coalesce(m.bonus, 0)) bonus,
    string_agg(distinct nullif(btrim(m.reference), ''), ' · '
      order by nullif(btrim(m.reference), '')) reference
  from latest t join public.mrn_apg_2026 m
    on btrim(m.item_code)=t.item_code and m.mrn_date=t.mrn_date
  where lower(btrim(m.status))='approved'
  group by t.item_code, t.mrn_date
), version as materialized (
  select stock_management_private.reference_version() token
)
select jsonb_build_object(
  'rows', coalesce((
    select jsonb_agg(
      (p.payload - array['distribution_orders','branch_stock','branch_demand',
        'monthly_sales','current_month_branch_sales','daily_sales_45d',
        'daily_sales_45d_available','meta']::text[])
      || jsonb_build_object(
        'supply_insight', coalesce(i.summary,
          '{"status":"pending","scope":"STORE","confidence":"unavailable"}'::jsonb)
          || jsonb_build_object('generated_at', i.updated_at),
        'total_qty', coalesce(r.total_qty, 0),
        'bonus', coalesce(r.bonus, 0),
        'received_quantity', coalesce(r.total_qty, 0),
        'received_qty', coalesce(r.total_qty, 0),
        'last_mrn_qty', coalesce(r.total_qty, 0),
        'reference', coalesce(r.reference, ''),
        'purchase_status_items', coalesce(ps.status_name, 'Not assigned')
      ) order by p.item_code
    )
    from page p
    left join public.stock_supply_insights i using(item_code)
    left join refs r on r.item_code=p.payload->>'item_code'
    left join purchase ps on ps.item_code=p.payload->>'item_code'
  ), '[]'::jsonb),
  'total', (select count(*) from public.stock_catalog_snapshot),
  'snapshot_at', coalesce((
    select payload->'meta'->>'refreshed_at' from public.stock_catalog_snapshot limit 1
  ), ''),
  'reference_version', version.token,
  'meta', jsonb_build_object('reference_version', version.token)
) from version;
$function$;
