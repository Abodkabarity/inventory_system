-- Preserve each alert's actual receipt identity. A newer product receipt must
-- never replace the original MRN date/number or keep a corrected expiry alive.
create table stock_management_private.expiry_receipt_corrections (
  id bigint generated always as identity primary key,
  corrected_at timestamptz not null default clock_timestamp(),
  reason text not null check(reason in ('source_receipt_corrected','today_receipt_withdrawn')),
  saved_receipt jsonb not null,
  source_receipts jsonb not null,
  receipt_signature text not null unique
);
alter table stock_management_private.expiry_receipt_corrections enable row level security;
revoke all on stock_management_private.expiry_receipt_corrections from public,anon,authenticated;
grant select on stock_management_private.expiry_receipt_corrections to service_role;
comment on table stock_management_private.expiry_receipt_corrections is
  'Private audit of superseded expiry alerts. Original receipt evidence and review notes are retained; source MRNs are never rewritten.';

create or replace function stock_management_private.discover_expiry_receipts()
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_start date; v_count integer; v_removed integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('stock-expiry-discovery',0));
  select receipt_start into strict v_start from public.stock_expiry_watch_state where singleton;

  -- Scan relevant product histories once, including cancelled/zero-quantity
  -- source rows so corrections can invalidate a previously approved alert.
  -- A different/newer MRN for the same product is never evidence of correction.
  with source as materialized (
    select btrim(m.item_code) item_code,coalesce(m.mrn_no,'') mrn_no,
      lower(btrim(m.warehouse)) warehouse,m.mrn_date,m.expiry_date,
      sum(coalesce(m.total_qty,0)) filter(where lower(btrim(m.status))='approved') qty
    from public.mrn_apg_2026 m
    join (select distinct item_code from public.stock_expiry_alert_receipts) a
      on a.item_code=btrim(m.item_code)
    where m.mrn_date<=v_today
      and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
    group by 1,2,3,4,5
  ), stale as materialized (
    select a.item_code,a.expiry_date,a.mrn_date,a.mrn_no,a.warehouse,
      coalesce((select jsonb_agg(to_jsonb(s) order by s.mrn_date,s.expiry_date)
        from source s where s.item_code=a.item_code and s.mrn_no=a.mrn_no
          and s.warehouse=a.warehouse),'[]'::jsonb) source_receipts
    from public.stock_expiry_alert_receipts a
    where (a.mrn_date=v_today or (a.mrn_no<>'' and exists(
      select 1 from source s where s.item_code=a.item_code
        and s.mrn_no=a.mrn_no and s.warehouse=a.warehouse)))
      and not exists(
        select 1 from source s where s.item_code=a.item_code
          and s.mrn_no=a.mrn_no and s.warehouse=a.warehouse
          and s.mrn_date=a.mrn_date and s.expiry_date=a.expiry_date and s.qty>0
          and s.expiry_date<(least(v_today,s.mrn_date+7)+interval '6 months')::date
      )
  ), removed as (
    delete from public.stock_expiry_alert_receipts a using stale s
    where (a.item_code,a.expiry_date,a.mrn_date,a.mrn_no,a.warehouse)=
      (s.item_code,s.expiry_date,s.mrn_date,s.mrn_no,s.warehouse)
    returning to_jsonb(a) saved_receipt,s.source_receipts
  ), audit as (
    insert into stock_management_private.expiry_receipt_corrections
      (reason,saved_receipt,source_receipts,receipt_signature)
    select case when source_receipts='[]'::jsonb then 'today_receipt_withdrawn'
      else 'source_receipt_corrected' end,saved_receipt,source_receipts,
      md5(saved_receipt::text)
    from removed on conflict(receipt_signature) do nothing
    returning id
  ) select count(*) into v_removed from removed;

  -- Keep durable historical evidence if its original source MRN disappeared.
  -- Only matching source corrections above invalidate it; age and new receipts
  -- for the same product cannot remove it. Review rows are never deleted.
  with receipts as (
    select btrim(m.item_code) item_code,m.expiry_date,m.mrn_date,
      coalesce(m.mrn_no,'') mrn_no,lower(btrim(m.warehouse)) warehouse,
      sum(m.ordered_quantity) ordered_qty,sum(coalesce(m.total_qty,0)) received_qty,
      max(m.item_name) item_name,max(m.supplier) supplier,max(m.company) company,
      max(m.category_1) category,min(nullif(btrim(m.vendor),'')) vendor
    from public.mrn_apg_2026 m
    where m.mrn_date between v_start and v_today
      and lower(btrim(m.status))='approved'
      and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
      and nullif(btrim(m.item_code),'') is not null
      and m.expiry_date<(least(v_today,m.mrn_date+7)+interval '6 months')::date
    group by btrim(m.item_code),m.expiry_date,m.mrn_date,
      coalesce(m.mrn_no,''),lower(btrim(m.warehouse))
    having sum(coalesce(m.total_qty,0))>0
  )
  insert into public.stock_expiry_alert_receipts as saved
    (item_code,expiry_date,mrn_date,mrn_no,warehouse,ordered_qty,received_qty,vendor,product_data)
  select r.item_code,r.expiry_date,r.mrn_date,r.mrn_no,r.warehouse,
    r.ordered_qty,r.received_qty,r.vendor,
    coalesce(s.payload,jsonb_build_object(
      'item_code',r.item_code,'item_name',r.item_name,'supplier',coalesce(r.supplier,''),
      'company',coalesce(r.company,''),'category',coalesce(r.category,''),'stock_unavailable',true))
      ||jsonb_build_object('last_mrn_date',r.mrn_date,'last_mrn_no',r.mrn_no,
        'expiry_date',r.expiry_date,'last_mrn_qty',r.received_qty)
  from receipts r left join public.stock_management_snapshot s on s.item_code=r.item_code
  on conflict(item_code,expiry_date,mrn_date,mrn_no,warehouse) do update
    set vendor=excluded.vendor,ordered_qty=excluded.ordered_qty,
      received_qty=excluded.received_qty,last_changed_at=clock_timestamp()
    where saved.ordered_qty is distinct from excluded.ordered_qty
      or saved.received_qty is distinct from excluded.received_qty
      or saved.vendor is distinct from excluded.vendor;
  get diagnostics v_count=row_count;
  update public.stock_expiry_watch_state
    set last_scanned_at=clock_timestamp(),scanned_through=v_today where singleton;
  return jsonb_build_object('changed_receipts',v_count+v_removed,
    'corrected_receipts',v_removed,'receipt_start',v_start,
    'window_from',v_today-7,'window_through',v_today);
end;
$function$;
-- Retain the existing private definer boundary, not a new public capability.
revoke all on function stock_management_private.discover_expiry_receipts()
  from public,anon,authenticated,service_role;

create or replace view public.stock_expiry_candidates with(security_invoker=true) as
with grouped as (
  select a.item_code,a.expiry_date,sum(a.received_qty) received_qty,count(*) receipt_count,
    max(a.mrn_date) last_receipt_date,
    md5(string_agg(jsonb_build_array(a.mrn_date,a.mrn_no,a.warehouse,
      trim_scale(a.received_qty))::text,'|' order by a.mrn_date,a.mrn_no,a.warehouse)) receipt_fingerprint,
    jsonb_agg(jsonb_build_object('mrn_date',a.mrn_date,'mrn_no',a.mrn_no,
      'warehouse',a.warehouse,'received_qty',a.received_qty,'ordered_qty',a.ordered_qty)
      order by a.mrn_date desc,a.mrn_no desc,a.warehouse) receipts,
    (array_agg(a.product_data order by a.mrn_date desc,a.mrn_no desc,a.warehouse))[1] saved_product,
    min(a.first_detected_at) first_detected_at,max(a.last_changed_at) last_changed_at,
    sum(a.ordered_qty) ordered_qty,
    string_agg(distinct nullif(a.mrn_no,''),' · ' order by nullif(a.mrn_no,'')) mrn_numbers
  from public.stock_expiry_alert_receipts a
  group by a.item_code,a.expiry_date,a.mrn_date
), enriched as (
  select g.*,coalesce(s.payload,g.saved_product) product,s.updated_at snapshot_at
  from grouped g left join public.stock_management_snapshot s using(item_code)
)
select item_code,expiry_date,received_qty,receipt_count,last_receipt_date,
  receipt_fingerprint,receipts,coalesce(product->>'item_name',item_code) item_name,
  coalesce(product->>'supplier','') supplier,coalesce(product->>'company','') company,
  coalesce(product->>'category','') category,(product->>'total_stock')::numeric total_stock,
  (product->>'store_stock')::numeric store_stock,(product->>'branches_stock')::numeric branches_stock,
  snapshot_at stock_snapshot_at,product->'meta'->>'stock_updated_at' stock_updated_at,
  expiry_date-(now() at time zone 'Asia/Dubai')::date days_left,
  (product-array['branches','monthly_sales','meta','branch_year_sales']::text[])
    ||jsonb_build_object('last_mrn_date',last_receipt_date,'last_mrn_no',mrn_numbers,
      'expiry_date',expiry_date) product_data,
  first_detected_at,last_changed_at,snapshot_at is null stock_snapshot_missing,
  ordered_qty,mrn_numbers
from enriched;

-- One transactional reconciliation updates existing reports and cache revisions.
select stock_management_private.discover_expiry_receipts();
