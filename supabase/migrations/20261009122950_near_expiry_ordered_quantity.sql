-- Keep ordered quantity with the same durable MRN receipt evidence as received
-- quantity. The latest product snapshot can belong to a different MRN.
alter table public.stock_expiry_alert_receipts
  add column ordered_qty numeric;

update public.stock_expiry_alert_receipts as saved
set ordered_qty = (
  select sum(m.ordered_quantity)
  from public.mrn_apg_2026 m
  where btrim(m.item_code) = saved.item_code
    and m.expiry_date = saved.expiry_date
    and m.mrn_date = saved.mrn_date
    and coalesce(m.mrn_no, '') = saved.mrn_no
    and lower(btrim(m.warehouse)) = saved.warehouse
    and lower(btrim(m.status)) = 'approved'
);

create or replace function stock_management_private.discover_expiry_receipts()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_start date; v_count integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('stock-expiry-discovery', 0));
  select receipt_start into strict v_start
  from public.stock_expiry_watch_state where singleton;
  with receipts as (
    select btrim(m.item_code) item_code, m.expiry_date, m.mrn_date,
      coalesce(m.mrn_no, '') mrn_no, lower(btrim(m.warehouse)) warehouse,
      sum(m.ordered_quantity) ordered_qty,
      sum(coalesce(m.received_quantity, 0)) received_qty,
      max(m.item_name) item_name, max(m.supplier) supplier,
      max(m.company) company, max(m.category_1) category
    from public.mrn_apg_2026 m
    where m.mrn_date between v_start and v_today - 1
      and lower(btrim(m.status)) = 'approved'
      and lower(btrim(m.warehouse)) in ('store', 'main virtual', 'new virtual')
      and nullif(btrim(m.item_code), '') is not null
      and m.expiry_date < (least(v_today, m.mrn_date + 7) + interval '6 months')::date
    group by btrim(m.item_code), m.expiry_date, m.mrn_date,
      coalesce(m.mrn_no, ''), lower(btrim(m.warehouse))
    having sum(coalesce(m.received_quantity, 0)) > 0
  )
  insert into public.stock_expiry_alert_receipts as saved
    (item_code, expiry_date, mrn_date, mrn_no, warehouse,
     ordered_qty, received_qty, product_data)
  select r.item_code, r.expiry_date, r.mrn_date, r.mrn_no, r.warehouse,
    r.ordered_qty, r.received_qty,
    coalesce(s.payload, jsonb_build_object(
      'item_code', r.item_code, 'item_name', r.item_name,
      'supplier', coalesce(r.supplier, ''), 'company', coalesce(r.company, ''),
      'category', coalesce(r.category, ''), 'stock_unavailable', true,
      'last_mrn_date', r.mrn_date, 'last_mrn_no', r.mrn_no,
      'last_mrn_qty', r.received_qty))
  from receipts r
  left join public.stock_management_snapshot s on s.item_code = r.item_code
  on conflict (item_code, expiry_date, mrn_date, mrn_no, warehouse) do update
    set ordered_qty = excluded.ordered_qty,
        received_qty = excluded.received_qty,
        last_changed_at = clock_timestamp()
    where saved.ordered_qty is distinct from excluded.ordered_qty
       or saved.received_qty is distinct from excluded.received_qty;
  get diagnostics v_count = row_count;
  update public.stock_expiry_watch_state
  set last_scanned_at = clock_timestamp(), scanned_through = v_today - 1
  where singleton;
  return jsonb_build_object('changed_receipts', v_count, 'receipt_start', v_start,
    'window_from', v_today - 7, 'window_through', v_today - 1);
end;
$$;

-- Append the new field so CREATE OR REPLACE VIEW preserves the existing
-- column contract for dependent functions and views.
create or replace view public.stock_expiry_candidates with (security_invoker = true) as
with grouped as (
  select item_code, expiry_date, sum(received_qty) received_qty,
    count(*) receipt_count, max(mrn_date) last_receipt_date,
    md5(string_agg(jsonb_build_array(mrn_date, mrn_no, warehouse,
      trim_scale(received_qty))::text, '|' order by mrn_date, mrn_no, warehouse)) receipt_fingerprint,
    jsonb_agg(jsonb_build_object('mrn_date', mrn_date, 'mrn_no', mrn_no,
      'warehouse', warehouse, 'received_qty', received_qty,
      'ordered_qty', ordered_qty)
      order by mrn_date desc, mrn_no desc, warehouse) receipts,
    (array_agg(product_data order by mrn_date desc, mrn_no desc, warehouse))[1] saved_product,
    min(first_detected_at) first_detected_at,
    max(last_changed_at) last_changed_at,
    sum(ordered_qty) ordered_qty
  from public.stock_expiry_alert_receipts
  group by item_code, expiry_date
), enriched as (
  select g.*, coalesce(s.payload, g.saved_product) product,
    s.updated_at snapshot_at
  from grouped g
  left join public.stock_management_snapshot s on s.item_code = g.item_code
)
select item_code, expiry_date, received_qty, receipt_count,
  last_receipt_date, receipt_fingerprint, receipts,
  coalesce(product->>'item_name', item_code) item_name,
  coalesce(product->>'supplier', '') supplier,
  coalesce(product->>'company', '') company,
  coalesce(product->>'category', '') category,
  (product->>'total_stock')::numeric total_stock,
  (product->>'store_stock')::numeric store_stock,
  (product->>'branches_stock')::numeric branches_stock,
  snapshot_at stock_snapshot_at,
  product->'meta'->>'stock_updated_at' stock_updated_at,
  expiry_date - (now() at time zone 'Asia/Dubai')::date days_left,
  product - 'branches' - 'monthly_sales' - 'meta' as product_data,
  first_detected_at, last_changed_at, (snapshot_at is null) stock_snapshot_missing,
  ordered_qty
from enriched;
