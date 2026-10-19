-- Reuse precisely the overview's product facts, without large chart/branch arrays.
create or replace view public.stock_expiry_candidates with(security_invoker=true) as
with receipts as (
  select btrim(m.item_code) item_code,m.expiry_date,m.mrn_date,
    coalesce(m.mrn_no,'') mrn_no,lower(btrim(m.warehouse)) warehouse,
    sum(coalesce(m.received_quantity,0)) received_qty
  from public.mrn_apg_2026 m
  where lower(btrim(m.status))='approved'
    and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
    and m.expiry_date < ((now() at time zone 'Asia/Dubai')::date+interval '6 months')::date
    and nullif(btrim(m.item_code),'') is not null
  group by btrim(m.item_code),m.expiry_date,m.mrn_date,coalesce(m.mrn_no,''),lower(btrim(m.warehouse))
), grouped as (
  select item_code,expiry_date,sum(received_qty) received_qty,count(*) receipt_count,
    max(mrn_date) last_receipt_date,
    md5(string_agg(jsonb_build_array(mrn_date,mrn_no,warehouse,trim_scale(received_qty))::text,
      '|' order by mrn_date nulls first,mrn_no,warehouse)) receipt_fingerprint,
    jsonb_agg(jsonb_build_object('mrn_date',mrn_date,'mrn_no',mrn_no,
      'warehouse',warehouse,'received_qty',received_qty)
      order by mrn_date desc nulls last,mrn_no desc,warehouse) receipts
  from receipts group by item_code,expiry_date having sum(received_qty)>0
)
select g.*,s.item_name,s.supplier,s.company,s.category,s.total_stock,
  (s.payload->>'store_stock')::numeric store_stock,
  (s.payload->>'branches_stock')::numeric branches_stock,
  s.updated_at stock_snapshot_at,s.payload->'meta'->>'stock_updated_at' stock_updated_at,
  g.expiry_date-(now() at time zone 'Asia/Dubai')::date days_left,
  s.payload - 'branches' - 'monthly_sales' - 'meta' as product_data
from grouped g join public.stock_management_snapshot s on s.item_code=g.item_code
where s.total_stock>0;
