-- Preserve the MRN receipt and reference scopes while serializing only once.
-- No source/snapshot writes, helper changes, new grants, or timeout changes.
set local lock_timeout = '3s';

create or replace function public.get_stock_management_register_batch(
  p_offset integer default 0, p_limit integer default 5000
) returns jsonb language sql stable security invoker
set search_path = '' set enable_nestloop = 'off'
as $function$
with page as materialized (
  select item_code, last_mrn_date, payload
  from public.stock_management_snapshot
  order by last_mrn_date desc, item_code
  limit least(greatest(coalesce(p_limit, 5000), 1), 5000)
  offset greatest(coalesce(p_offset, 0), 0)
), receipts as materialized (
  -- Preserve STORE/virtual scope for vendor, ordered quantity and expiry facts.
  select p.item_code,
    min(m.expiry_date) filter(where coalesce(m.total_qty, 0)>0) expiry_date,
    sum(coalesce(m.ordered_quantity, 0)) ordered_quantity,
    sum(coalesce(m.total_qty, 0)) received_quantity,
    min(nullif(btrim(m.vendor), '')) vendor,
    count(distinct coalesce(m.mrn_no, '')) receipt_count,
    count(distinct m.expiry_date) filter(where coalesce(m.total_qty, 0)>0) expiry_count
  from page p join public.mrn_apg_2026 m
    on btrim(m.item_code)=p.item_code and m.mrn_date=p.last_mrn_date
  where lower(btrim(m.status))='approved'
    and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
  group by p.item_code
), targets as materialized (
  -- The existing enrichment resolves its date/identity from the payload.
  select distinct payload->>'item_code' item_code,
    nullif(payload->>'last_mrn_date', '')::date mrn_date
  from page
), codes as materialized (
  select distinct item_code from targets
), purchase as materialized (
  select s.item_code,
    string_agg(distinct nullif(btrim(s.status_name), ''), ' · '
      order by nullif(btrim(s.status_name), '')) status_name
  from public.availability_kpi_purchase_status s join codes c using(item_code)
  group by s.item_code
), refs as materialized (
  -- Reference/authoritative-total scope remains all approved source warehouses.
  select t.item_code, t.mrn_date,
    sum(coalesce(m.total_qty, 0)) total_qty,
    sum(coalesce(m.bonus, 0)) bonus,
    string_agg(distinct nullif(btrim(m.reference), ''), ' · '
      order by nullif(btrim(m.reference), '')) reference
  from targets t join public.mrn_apg_2026 m
    on btrim(m.item_code)=t.item_code and m.mrn_date=t.mrn_date
  where lower(btrim(m.status))='approved'
  group by t.item_code, t.mrn_date
), version as materialized (
  select stock_management_private.reference_version() token
)
select jsonb_build_object(
  'rows', coalesce((
    select jsonb_agg(
      (p.payload - array['branches','monthly_sales','meta','branch_year_sales',
        'receipt_lines']::text[])
      || jsonb_build_object(
        'receipt_scope', 'latest_mrn_date',
        'receipt_count', r.receipt_count,
        'expiry_count', r.expiry_count,
        'vendor', left(upper(r.vendor), 10),
        'expiry_date', r.expiry_date,
        'ordered_quantity', r.ordered_quantity,
        'received_quantity', r.received_quantity,
        -- Keep the legacy validation/fallback even though enrichment wins below.
        'last_mrn_qty', coalesce(r.received_quantity,
          (p.payload->>'last_mrn_qty')::numeric)
      )
      || jsonb_build_object(
        'supply_insight', coalesce(i.summary,
          '{"status":"pending","scope":"STORE","confidence":"unavailable"}'::jsonb)
          || jsonb_build_object('generated_at', i.updated_at),
        'total_qty', coalesce(ref.total_qty, 0),
        'bonus', coalesce(ref.bonus, 0),
        'received_quantity', coalesce(ref.total_qty, 0),
        'received_qty', coalesce(ref.total_qty, 0),
        'last_mrn_qty', coalesce(ref.total_qty, 0),
        'reference', coalesce(ref.reference, ''),
        'purchase_status_items', coalesce(ps.status_name, 'Not assigned')
      ) order by p.last_mrn_date desc, p.item_code
    )
    from page p left join receipts r using(item_code)
    left join public.stock_supply_insights i using(item_code)
    left join refs ref on ref.item_code=p.payload->>'item_code'
      and ref.mrn_date is not distinct from nullif(p.payload->>'last_mrn_date', '')::date
    left join purchase ps on ps.item_code=p.payload->>'item_code'
  ), '[]'::jsonb),
  'total', (select count(*) from public.stock_management_snapshot),
  'snapshot_at', (select max(updated_at) from public.stock_management_snapshot),
  'reference_version', version.token
) from version;
$function$;
