-- The launch boundary is immutable. Discovery ends yesterday in Dubai; stored
-- receipt evidence is never removed by a moving week, stock changes or imports.
create table public.stock_expiry_watch_state (
  singleton boolean primary key default true check(singleton),
  started_on date not null,
  receipt_start date not null,
  last_scanned_at timestamptz,
  scanned_through date
);
insert into public.stock_expiry_watch_state(singleton,started_on,receipt_start)
values(true,(now() at time zone 'Asia/Dubai')::date,(now() at time zone 'Asia/Dubai')::date-7);
create table public.stock_expiry_alert_receipts (
  item_code text not null,
  expiry_date date not null,
  mrn_date date not null,
  mrn_no text not null,
  warehouse text not null,
  received_qty numeric not null check(received_qty>0),
  product_data jsonb not null,
  first_detected_at timestamptz not null default clock_timestamp(),
  last_changed_at timestamptz not null default clock_timestamp(),
  primary key(item_code,expiry_date,mrn_date,mrn_no,warehouse)
);
alter table public.stock_expiry_watch_state enable row level security;
alter table public.stock_expiry_alert_receipts enable row level security;
revoke all on public.stock_expiry_watch_state,public.stock_expiry_alert_receipts from anon,authenticated;
grant select on public.stock_expiry_watch_state,public.stock_expiry_alert_receipts to authenticated;
grant all on public.stock_expiry_watch_state,public.stock_expiry_alert_receipts to service_role;
create policy stock_expiry_watch_inventory_read on public.stock_expiry_watch_state
  for select to authenticated using((select public.item_tracker_my_role())='inventory');
create policy stock_expiry_receipts_inventory_read on public.stock_expiry_alert_receipts
  for select to authenticated using((select public.item_tracker_my_role())='inventory');
create index mrn_apg_2026_expiry_receipt_date_idx on public.mrn_apg_2026(mrn_date,item_code,expiry_date)
  where lower(btrim(status))='approved'
    and lower(btrim(warehouse)) in ('store','main virtual','new virtual');

create function stock_management_private.discover_expiry_receipts()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_start date; v_count integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('stock-expiry-discovery',0));
  select receipt_start into strict v_start from public.stock_expiry_watch_state where singleton;
  with receipts as (
    select btrim(m.item_code) item_code,m.expiry_date,m.mrn_date,
      coalesce(m.mrn_no,'') mrn_no,lower(btrim(m.warehouse)) warehouse,
      sum(coalesce(m.received_quantity,0)) received_qty,
      max(m.item_name) item_name,max(m.supplier) supplier,max(m.company) company,max(m.category_1) category
    from public.mrn_apg_2026 m
    where m.mrn_date between v_start and v_today-1
      and lower(btrim(m.status))='approved'
      and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
      and nullif(btrim(m.item_code),'') is not null
      -- Catch up missed/delayed imports, but an old long-dated receipt cannot
      -- become a NEW alert months later just because time has passed. The last
      -- day it belonged to a seven-day window bounds its detection horizon.
      and m.expiry_date < (least(v_today,m.mrn_date+7)+interval '6 months')::date
    group by btrim(m.item_code),m.expiry_date,m.mrn_date,coalesce(m.mrn_no,''),lower(btrim(m.warehouse))
    having sum(coalesce(m.received_quantity,0))>0
  )
  insert into public.stock_expiry_alert_receipts as saved
    (item_code,expiry_date,mrn_date,mrn_no,warehouse,received_qty,product_data)
  select r.item_code,r.expiry_date,r.mrn_date,r.mrn_no,r.warehouse,r.received_qty,
    coalesce(s.payload,jsonb_build_object('item_code',r.item_code,'item_name',r.item_name,
      'supplier',coalesce(r.supplier,''),'company',coalesce(r.company,''),'category',coalesce(r.category,''),
      'stock_unavailable',true,'last_mrn_date',r.mrn_date,'last_mrn_no',r.mrn_no,'last_mrn_qty',r.received_qty))
  from receipts r left join public.stock_management_snapshot s on s.item_code=r.item_code
  on conflict(item_code,expiry_date,mrn_date,mrn_no,warehouse) do update
    set received_qty=excluded.received_qty,last_changed_at=clock_timestamp()
    where saved.received_qty is distinct from excluded.received_qty;
  get diagnostics v_count=row_count;
  update public.stock_expiry_watch_state set last_scanned_at=clock_timestamp(),scanned_through=v_today-1 where singleton;
  return jsonb_build_object('changed_receipts',v_count,'receipt_start',v_start,
    'window_from',v_today-7,'window_through',v_today-1);
end;
$$;
revoke all on function stock_management_private.discover_expiry_receipts() from public,anon,authenticated,service_role;

create function stock_management_private.request_expiry_discovery()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if coalesce(auth.role(),'') <> 'service_role'
    and (auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory') then
    raise exception 'Inventory access required' using errcode='42501';
  end if;
  return stock_management_private.discover_expiry_receipts();
end;
$$;
revoke all on function stock_management_private.request_expiry_discovery() from public,anon;
grant execute on function stock_management_private.request_expiry_discovery() to authenticated,service_role;
create function public.refresh_stock_expiry_watch()
returns jsonb language sql security invoker set search_path='' as $$
  select stock_management_private.request_expiry_discovery();
$$;
revoke all on function public.refresh_stock_expiry_watch() from public,anon;
grant execute on function public.refresh_stock_expiry_watch() to authenticated,service_role;

-- Preserve the existing view's columns/RPC contract. Never require live stock
-- or source MRN existence to keep an outstanding alert visible.
create or replace view public.stock_expiry_candidates with(security_invoker=true) as
with grouped as (
  select item_code,expiry_date,sum(received_qty) received_qty,count(*) receipt_count,
    max(mrn_date) last_receipt_date,
    md5(string_agg(jsonb_build_array(mrn_date,mrn_no,warehouse,trim_scale(received_qty))::text,
      '|' order by mrn_date,mrn_no,warehouse)) receipt_fingerprint,
    jsonb_agg(jsonb_build_object('mrn_date',mrn_date,'mrn_no',mrn_no,
      'warehouse',warehouse,'received_qty',received_qty)
      order by mrn_date desc,mrn_no desc,warehouse) receipts,
    (array_agg(product_data order by mrn_date desc,mrn_no desc,warehouse))[1] saved_product,
    min(first_detected_at) first_detected_at,max(last_changed_at) last_changed_at
  from public.stock_expiry_alert_receipts group by item_code,expiry_date
), enriched as (
  select g.*,coalesce(s.payload,g.saved_product) product,s.updated_at snapshot_at
  from grouped g left join public.stock_management_snapshot s on s.item_code=g.item_code
)
select item_code,expiry_date,received_qty,receipt_count,last_receipt_date,receipt_fingerprint,receipts,
  coalesce(product->>'item_name',item_code) item_name,coalesce(product->>'supplier','') supplier,
  coalesce(product->>'company','') company,coalesce(product->>'category','') category,
  (product->>'total_stock')::numeric total_stock,(product->>'store_stock')::numeric store_stock,
  (product->>'branches_stock')::numeric branches_stock,snapshot_at stock_snapshot_at,
  product->'meta'->>'stock_updated_at' stock_updated_at,
  expiry_date-(now() at time zone 'Asia/Dubai')::date days_left,
  product-'branches'-'monthly_sales'-'meta' as product_data,
  first_detected_at,last_changed_at,(snapshot_at is null) stock_snapshot_missing
from enriched;

create or replace function public.get_stock_expiry_page(
  p_search text default '',p_review_state text default 'pending',p_urgency text default '',
  p_offset integer default 0,p_limit integer default 30
) returns jsonb language sql stable security invoker set search_path='' as $$
  with candidates as materialized (
    select c.*,coalesce(r.note,'') note,r.updated_at review_updated_at,r.reviewed_at,
      coalesce(r.is_reviewed and r.reviewed_fingerprint=c.receipt_fingerprint,false) is_reviewed,
      coalesce(r.is_reviewed and r.reviewed_fingerprint is distinct from c.receipt_fingerprint,false) new_receipts
    from public.stock_expiry_candidates c left join public.stock_expiry_reviews r
      on r.item_code=c.item_code and r.expiry_date=c.expiry_date
  ), filtered as materialized (
    select * from candidates c where
      (coalesce(btrim(p_search),'')='' or strpos(lower(c.item_code||' '||c.item_name||' '||c.supplier||' '||c.company),lower(btrim(p_search)))>0)
      and (p_review_state='all' or (p_review_state='reviewed' and c.is_reviewed)
        or (coalesce(p_review_state,'pending')='pending' and not c.is_reviewed))
      and (coalesce(p_urgency,'')='' or (p_urgency='near' and days_left>=0)
        or (p_urgency='expired' and days_left<0) or (p_urgency='urgent' and days_left between 0 and 30)
        or (p_urgency='soon' and days_left between 31 and 90) or (p_urgency='later' and days_left>90))
  ), paged as (
    select * from filtered order by expiry_date,item_name,item_code
    limit least(greatest(coalesce(p_limit,30),1),100) offset greatest(coalesce(p_offset,0),0)
  ) select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(to_jsonb(p)-'receipts' order by expiry_date,item_name,item_code) from paged p),'[]'::jsonb),
    'total',(select count(*) from filtered),
    'summary',(select jsonb_build_object('pending',count(*) filter(where not is_reviewed),
      'near_expiry',count(*) filter(where not is_reviewed and days_left>=0),
      'expired',count(*) filter(where not is_reviewed and days_left<0),
      'urgent',count(*) filter(where not is_reviewed and days_left between 0 and 30),
      'reviewed',count(*) filter(where is_reviewed),'products',count(distinct item_code)) from candidates),
    'meta',jsonb_build_object('as_of',(now() at time zone 'Asia/Dubai')::date,
      'before',((now() at time zone 'Asia/Dubai')::date+interval '6 months')::date,
      'window_from',(now() at time zone 'Asia/Dubai')::date-7,
      'window_through',(now() at time zone 'Asia/Dubai')::date-1,
      'receipt_start',(select receipt_start from public.stock_expiry_watch_state where singleton),
      'last_scanned_at',(select last_scanned_at from public.stock_expiry_watch_state where singleton),
      'stock_updated_at',(select max(stock_updated_at) from candidates),
      'source','mrn_apg_2026','persistent',true,'batch_stock_available',false)
  );
$$;

select stock_management_private.discover_expiry_receipts();
-- Hourly discovery runs without an open dashboard and picks up delayed imports.
select cron.schedule('stock-expiry-receipt-watch','10 * * * *',
  'select stock_management_private.discover_expiry_receipts();');
