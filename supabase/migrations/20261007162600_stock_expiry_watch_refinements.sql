-- Keep harmless numeric scale changes from reopening a review. Add a dedicated
-- upcoming-only filter so expired dates remain in their own queue by default.
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
  g.expiry_date-(now() at time zone 'Asia/Dubai')::date days_left
from grouped g join public.stock_management_snapshot s on s.item_code=g.item_code
where s.total_stock>0;

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
      (coalesce(p_search,'')='' or strpos(lower(c.item_code||' '||c.item_name||' '||c.supplier||' '||c.company),lower(btrim(p_search)))>0)
      and (p_review_state='all' or (p_review_state='reviewed' and c.is_reviewed)
        or (coalesce(p_review_state,'pending')='pending' and not c.is_reviewed))
      and (coalesce(p_urgency,'')='' or (p_urgency='near' and days_left>=0) or (p_urgency='expired' and days_left<0)
        or (p_urgency='urgent' and days_left between 0 and 30)
        or (p_urgency='soon' and days_left between 31 and 90)
        or (p_urgency='later' and days_left>90))
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
      'stock_updated_at',(select max(stock_updated_at) from candidates),
      'source','mrn_apg_2026','batch_stock_available',false)
  );
$$;
