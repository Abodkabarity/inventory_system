-- Review a receipt day independently: item + expiry + MRN date.
-- Preserve the old review table as a legacy archive; never infer that a review
-- of one receipt day covers a later delivery.
create table public.stock_expiry_receipt_reviews (
  item_code text not null,
  expiry_date date not null,
  mrn_date date not null,
  note text not null default '' check (length(note)<=4000),
  is_reviewed boolean not null default false,
  reviewed_fingerprint text,
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid references auth.users(id) on delete set null,
  primary key(item_code,expiry_date,mrn_date)
);
alter table public.stock_expiry_receipt_reviews enable row level security;
revoke all on public.stock_expiry_receipt_reviews from public,anon,authenticated;
grant select on public.stock_expiry_receipt_reviews to authenticated;
grant all on public.stock_expiry_receipt_reviews to service_role;
create policy stock_expiry_receipt_reviews_inventory_read
  on public.stock_expiry_receipt_reviews for select to authenticated
  using ((select public.item_tracker_my_role())='inventory');
create policy stock_expiry_receipt_reviews_view_read
  on public.stock_expiry_receipt_reviews for select to authenticated
  using ((select stock_management_private.is_view_user()));
create index stock_expiry_receipt_reviews_updated_by_idx
  on public.stock_expiry_receipt_reviews(updated_by);
create index stock_expiry_receipt_reviews_reviewed_by_idx
  on public.stock_expiry_receipt_reviews(reviewed_by);

-- Copy notes to each historical receipt day. Only a still-valid review of the
-- complete former group can cover its existing days. Orphaned legacy notes are
-- retained in the original table, without fabricating an MRN date.
insert into public.stock_expiry_receipt_reviews
  (item_code,expiry_date,mrn_date,note,is_reviewed,reviewed_fingerprint,
   reviewed_at,reviewed_by,updated_at,updated_by)
select r.item_code,r.expiry_date,d.mrn_date,r.note,
  coalesce(r.is_reviewed and r.reviewed_fingerprint=c.receipt_fingerprint,false),
  case when r.reviewed_fingerprint=c.receipt_fingerprint then d.fingerprint end,
  r.reviewed_at,r.reviewed_by,r.updated_at,r.updated_by
from public.stock_expiry_reviews r
join public.stock_expiry_candidates c using(item_code,expiry_date)
join lateral (
  select e.mrn_date,
    md5(string_agg(jsonb_build_array(e.mrn_date,e.mrn_no,e.warehouse,trim_scale(e.received_qty))::text,
      '|' order by e.mrn_date,e.mrn_no,e.warehouse)) fingerprint
  from public.stock_expiry_alert_receipts e
  where e.item_code=r.item_code and e.expiry_date=r.expiry_date
  group by e.mrn_date
) d on true;

create or replace view public.stock_expiry_candidates with(security_invoker=true) as
 WITH grouped AS (
         SELECT stock_expiry_alert_receipts.item_code,
            stock_expiry_alert_receipts.expiry_date,
            sum(stock_expiry_alert_receipts.received_qty) AS received_qty,
            count(*) AS receipt_count,
            max(stock_expiry_alert_receipts.mrn_date) AS last_receipt_date,
            md5(string_agg(jsonb_build_array(stock_expiry_alert_receipts.mrn_date, stock_expiry_alert_receipts.mrn_no, stock_expiry_alert_receipts.warehouse, trim_scale(stock_expiry_alert_receipts.received_qty))::text, '|'::text ORDER BY stock_expiry_alert_receipts.mrn_date, stock_expiry_alert_receipts.mrn_no, stock_expiry_alert_receipts.warehouse)) AS receipt_fingerprint,
            jsonb_agg(jsonb_build_object('mrn_date', stock_expiry_alert_receipts.mrn_date, 'mrn_no', stock_expiry_alert_receipts.mrn_no, 'warehouse', stock_expiry_alert_receipts.warehouse, 'received_qty', stock_expiry_alert_receipts.received_qty, 'ordered_qty', stock_expiry_alert_receipts.ordered_qty) ORDER BY stock_expiry_alert_receipts.mrn_date DESC, stock_expiry_alert_receipts.mrn_no DESC, stock_expiry_alert_receipts.warehouse) AS receipts,
            (array_agg(stock_expiry_alert_receipts.product_data ORDER BY stock_expiry_alert_receipts.mrn_date DESC, stock_expiry_alert_receipts.mrn_no DESC, stock_expiry_alert_receipts.warehouse))[1] AS saved_product,
            min(stock_expiry_alert_receipts.first_detected_at) AS first_detected_at,
            max(stock_expiry_alert_receipts.last_changed_at) AS last_changed_at,
            sum(stock_expiry_alert_receipts.ordered_qty) AS ordered_qty,
            string_agg(distinct nullif(stock_expiry_alert_receipts.mrn_no,''), ' · ' order by nullif(stock_expiry_alert_receipts.mrn_no,'')) AS mrn_numbers
           FROM stock_expiry_alert_receipts
          GROUP BY stock_expiry_alert_receipts.item_code, stock_expiry_alert_receipts.expiry_date, stock_expiry_alert_receipts.mrn_date
        ), enriched AS (
         SELECT g.item_code,
            g.expiry_date,
            g.received_qty,
            g.receipt_count,
            g.last_receipt_date,
            g.receipt_fingerprint,
            g.receipts,
            g.saved_product,
            g.first_detected_at,
            g.last_changed_at,
            g.ordered_qty,
            g.mrn_numbers,
            COALESCE(s.payload, g.saved_product) AS product,
            s.updated_at AS snapshot_at
           FROM grouped g
             LEFT JOIN stock_management_snapshot s ON s.item_code = g.item_code
        )
 SELECT item_code,
    expiry_date,
    received_qty,
    receipt_count,
    last_receipt_date,
    receipt_fingerprint,
    receipts,
    COALESCE(product ->> 'item_name'::text, item_code) AS item_name,
    COALESCE(product ->> 'supplier'::text, ''::text) AS supplier,
    COALESCE(product ->> 'company'::text, ''::text) AS company,
    COALESCE(product ->> 'category'::text, ''::text) AS category,
    (product ->> 'total_stock'::text)::numeric AS total_stock,
    (product ->> 'store_stock'::text)::numeric AS store_stock,
    (product ->> 'branches_stock'::text)::numeric AS branches_stock,
    snapshot_at AS stock_snapshot_at,
    (product -> 'meta'::text) ->> 'stock_updated_at'::text AS stock_updated_at,
    expiry_date - (now() AT TIME ZONE 'Asia/Dubai'::text)::date AS days_left,
    product - 'branches'::text - 'monthly_sales'::text - 'meta'::text - 'branch_year_sales'::text AS product_data,
    first_detected_at,
    last_changed_at,
    snapshot_at IS NULL AS stock_snapshot_missing,
    ordered_qty,
    mrn_numbers
   FROM enriched;

create function stock_management_private.expiry_vendor(p_item_code text,p_expiry date,p_mrn_date date)
returns text language sql stable security invoker set search_path='' as $function$
  select left(upper(nullif(btrim(r.vendor),'')),10)
  from public.stock_expiry_alert_receipts r
  where r.item_code=p_item_code and r.expiry_date=p_expiry and r.mrn_date=p_mrn_date
    and nullif(btrim(r.vendor),'') is not null
  order by r.mrn_no desc,r.warehouse,r.vendor limit 1;
$function$;
revoke all on function stock_management_private.expiry_vendor(text,date,date) from public,anon;
grant execute on function stock_management_private.expiry_vendor(text,date,date) to authenticated,service_role;

-- Keep optional supply analysis when installed; older Stock Management schemas
-- use the same receipt-day query without requiring that separate feature.
do $compat$
begin
  if to_regclass('public.stock_supply_insights') is not null then
    execute $definition$
CREATE OR REPLACE FUNCTION public.get_stock_expiry_page(p_search text DEFAULT ''::text, p_review_state text DEFAULT 'pending'::text, p_urgency text DEFAULT ''::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
select q.value||jsonb_build_object('rows',coalesce((
    select jsonb_agg(r.row||jsonb_build_object('supply_insight',
      coalesce(i.summary,'{"status":"pending","scope":"STORE","confidence":"unavailable"}'::jsonb)
      ||jsonb_build_object('generated_at',i.updated_at)) order by r.ordinal)
    from jsonb_array_elements(q.value->'rows') with ordinality r(row,ordinal)
    left join public.stock_supply_insights i on i.item_code=r.row->>'item_code'),'[]'::jsonb))
 from (
with candidates as materialized (
    select c.*,coalesce(r.note,'') note,r.updated_at review_updated_at,r.reviewed_at,
      coalesce(r.is_reviewed and r.reviewed_fingerprint=c.receipt_fingerprint,false) is_reviewed,
      coalesce(r.is_reviewed and r.reviewed_fingerprint is distinct from c.receipt_fingerprint,false) new_receipts
    from public.stock_expiry_candidates c left join public.stock_expiry_receipt_reviews r
      on r.item_code=c.item_code and r.expiry_date=c.expiry_date and r.mrn_date=c.last_receipt_date
  ), filtered as materialized (
    select * from candidates c where
      (coalesce(btrim(p_search),'')='' or strpos(lower(c.item_code||' '||c.item_name||' '||c.supplier||' '||c.company),lower(btrim(p_search)))>0)
      and (p_review_state='all' or (p_review_state='reviewed' and c.is_reviewed)
        or (coalesce(p_review_state,'pending')='pending' and not c.is_reviewed))
      and (coalesce(p_urgency,'')='' or (p_urgency='near' and days_left>=0)
        or (p_urgency='expired' and days_left<0) or (p_urgency='urgent' and days_left between 0 and 30)
        or (p_urgency='soon' and days_left between 31 and 90) or (p_urgency='later' and days_left>90))
  ), paged as (
    select * from filtered order by last_receipt_date desc,expiry_date,item_name,item_code
    limit least(greatest(coalesce(p_limit,30),1),5000) offset greatest(coalesce(p_offset,0),0)
  ) select jsonb_build_object(
    'rows',coalesce((select jsonb_agg((to_jsonb(p)-'receipts') || jsonb_build_object('vendor',stock_management_private.expiry_vendor(p.item_code,p.expiry_date,p.last_receipt_date),'product_data',
        coalesce(p.product_data,'{}'::jsonb) || jsonb_build_object('added_date_time',i.added_date_time)) order by last_receipt_date desc,expiry_date,item_name,item_code) from paged p left join lateral (
        select (i.added_date_time at time zone 'Asia/Dubai')::date added_date_time
        from public.item_report i where btrim(i.item_code)=p.item_code
        order by i.created_at desc nulls last limit 1
      ) i on true),'[]'::jsonb),
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
      'source','mrn_apg_2026','persistent',true,'grouping','item_expiry_mrn_date','batch_stock_available',false)
  )
)q(value);
$function$;
$definition$;
  else
    execute $definition$
CREATE OR REPLACE FUNCTION public.get_stock_expiry_page(p_search text DEFAULT ''::text, p_review_state text DEFAULT 'pending'::text, p_urgency text DEFAULT ''::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
with candidates as materialized (
    select c.*,coalesce(r.note,'') note,r.updated_at review_updated_at,r.reviewed_at,
      coalesce(r.is_reviewed and r.reviewed_fingerprint=c.receipt_fingerprint,false) is_reviewed,
      coalesce(r.is_reviewed and r.reviewed_fingerprint is distinct from c.receipt_fingerprint,false) new_receipts
    from public.stock_expiry_candidates c left join public.stock_expiry_receipt_reviews r
      on r.item_code=c.item_code and r.expiry_date=c.expiry_date and r.mrn_date=c.last_receipt_date
  ), filtered as materialized (
    select * from candidates c where
      (coalesce(btrim(p_search),'')='' or strpos(lower(c.item_code||' '||c.item_name||' '||c.supplier||' '||c.company),lower(btrim(p_search)))>0)
      and (p_review_state='all' or (p_review_state='reviewed' and c.is_reviewed)
        or (coalesce(p_review_state,'pending')='pending' and not c.is_reviewed))
      and (coalesce(p_urgency,'')='' or (p_urgency='near' and days_left>=0)
        or (p_urgency='expired' and days_left<0) or (p_urgency='urgent' and days_left between 0 and 30)
        or (p_urgency='soon' and days_left between 31 and 90) or (p_urgency='later' and days_left>90))
  ), paged as (
    select * from filtered order by last_receipt_date desc,expiry_date,item_name,item_code
    limit least(greatest(coalesce(p_limit,30),1),5000) offset greatest(coalesce(p_offset,0),0)
  ) select jsonb_build_object(
    'rows',coalesce((select jsonb_agg((to_jsonb(p)-'receipts') || jsonb_build_object('vendor',stock_management_private.expiry_vendor(p.item_code,p.expiry_date,p.last_receipt_date),'product_data',
        coalesce(p.product_data,'{}'::jsonb) || jsonb_build_object('added_date_time',i.added_date_time)) order by last_receipt_date desc,expiry_date,item_name,item_code) from paged p left join lateral (
        select (i.added_date_time at time zone 'Asia/Dubai')::date added_date_time
        from public.item_report i where btrim(i.item_code)=p.item_code
        order by i.created_at desc nulls last limit 1
      ) i on true),'[]'::jsonb),
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
      'source','mrn_apg_2026','persistent',true,'grouping','item_expiry_mrn_date','batch_stock_available',false)
  );
$function$;
$definition$;
  end if;
end;
$compat$;

-- Keep optional supply analysis when installed; older Stock Management schemas
-- use the same receipt-day query without requiring that separate feature.
do $compat$
begin
  if to_regclass('public.stock_supply_insights') is not null then
    execute $definition$
CREATE OR REPLACE FUNCTION public.get_stock_expiry_item(p_item_code text, p_expiry_date date, p_mrn_date date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
select q.value||jsonb_build_object('product_data',q.value->'product_data'||jsonb_build_object('supply_insight',coalesce(i.detail,'{}'::jsonb)), 'supply_insight',
    coalesce(i.detail,'{"status":"pending","scope":"STORE","confidence":"unavailable"}'::jsonb)
    ||jsonb_build_object('generated_at',i.updated_at))
 from (
select to_jsonb(c)||jsonb_build_object('vendor',stock_management_private.expiry_vendor(c.item_code,c.expiry_date,c.last_receipt_date),'note',coalesce(r.note,''),
    'review_updated_at',r.updated_at,'reviewed_at',r.reviewed_at,
    'is_reviewed',coalesce(r.is_reviewed and r.reviewed_fingerprint=c.receipt_fingerprint,false),
    'new_receipts',coalesce(r.is_reviewed and r.reviewed_fingerprint is distinct from c.receipt_fingerprint,false),
    'product_data',(case when c.stock_snapshot_missing then
      (select evidence.product_data from public.stock_expiry_alert_receipts evidence
       where evidence.item_code=c.item_code and evidence.expiry_date=c.expiry_date and evidence.mrn_date=c.last_receipt_date
       order by evidence.mrn_date desc,evidence.mrn_no desc,evidence.warehouse limit 1)
      else c.product_data end) || jsonb_build_object('added_date_time',i.added_date_time))
  from public.stock_expiry_candidates c left join public.stock_expiry_receipt_reviews r
    on r.item_code=c.item_code and r.expiry_date=c.expiry_date and r.mrn_date=c.last_receipt_date
  left join lateral (
    select (i.added_date_time at time zone 'Asia/Dubai')::date added_date_time
    from public.item_report i where btrim(i.item_code)=c.item_code
    order by i.created_at desc nulls last limit 1
  ) i on true
  where c.item_code=p_item_code and c.expiry_date=p_expiry_date and c.last_receipt_date=p_mrn_date
)q(value) left join public.stock_supply_insights i on i.item_code=p_item_code;
$function$;
$definition$;
  else
    execute $definition$
CREATE OR REPLACE FUNCTION public.get_stock_expiry_item(p_item_code text, p_expiry_date date, p_mrn_date date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
select to_jsonb(c)||jsonb_build_object('vendor',stock_management_private.expiry_vendor(c.item_code,c.expiry_date,c.last_receipt_date),'note',coalesce(r.note,''),
    'review_updated_at',r.updated_at,'reviewed_at',r.reviewed_at,
    'is_reviewed',coalesce(r.is_reviewed and r.reviewed_fingerprint=c.receipt_fingerprint,false),
    'new_receipts',coalesce(r.is_reviewed and r.reviewed_fingerprint is distinct from c.receipt_fingerprint,false),
    'product_data',(case when c.stock_snapshot_missing then
      (select evidence.product_data from public.stock_expiry_alert_receipts evidence
       where evidence.item_code=c.item_code and evidence.expiry_date=c.expiry_date and evidence.mrn_date=c.last_receipt_date
       order by evidence.mrn_date desc,evidence.mrn_no desc,evidence.warehouse limit 1)
      else c.product_data end) || jsonb_build_object('added_date_time',i.added_date_time))
  from public.stock_expiry_candidates c left join public.stock_expiry_receipt_reviews r
    on r.item_code=c.item_code and r.expiry_date=c.expiry_date and r.mrn_date=c.last_receipt_date
  left join lateral (
    select (i.added_date_time at time zone 'Asia/Dubai')::date added_date_time
    from public.item_report i where btrim(i.item_code)=c.item_code
    order by i.created_at desc nulls last limit 1
  ) i on true
  where c.item_code=p_item_code and c.expiry_date=p_expiry_date and c.last_receipt_date=p_mrn_date;
$function$;
$definition$;
  end if;
end;
$compat$;

revoke all on function public.get_stock_expiry_item(text,date,date) from public,anon;
grant execute on function public.get_stock_expiry_item(text,date,date) to authenticated,service_role;

CREATE OR REPLACE FUNCTION stock_management_private.save_expiry_review(p_item_code text, p_expiry_date date, p_fingerprint text, p_note text, p_action text, p_expected_updated_at timestamp with time zone, p_mrn_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_current text; v_previous public.stock_expiry_receipt_reviews; v_saved public.stock_expiry_receipt_reviews;
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'Inventory access required' using errcode='42501';
  end if;
  if p_action is null or p_action not in ('note','review','reopen') then
    raise exception 'Invalid review action' using errcode='22023';
  end if;
  if length(coalesce(p_note,''))>4000 then raise exception 'Notes are limited to 4000 characters'; end if;
  if p_mrn_date is null then raise exception 'MRN date is required. Reload the alert.' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_item_code||':'||p_expiry_date::text||':'||p_mrn_date::text,0));
  select receipt_fingerprint into v_current from public.stock_expiry_candidates
    where item_code=p_item_code and expiry_date=p_expiry_date and last_receipt_date=p_mrn_date;
  if v_current is null or v_current is distinct from p_fingerprint then
    raise exception 'Receipt data changed or the alert is no longer eligible. Reload before saving.' using errcode='40001';
  end if;
  select * into v_previous from public.stock_expiry_receipt_reviews
    where item_code=p_item_code and expiry_date=p_expiry_date and mrn_date=p_mrn_date for update;
  if v_previous.updated_at is distinct from p_expected_updated_at then
    raise exception 'Another user changed this note or review. Reload before saving.' using errcode='40001';
  end if;
  insert into public.stock_expiry_receipt_reviews(item_code,expiry_date,mrn_date,note,is_reviewed,
    reviewed_fingerprint,reviewed_at,reviewed_by,updated_at,updated_by)
  values(p_item_code,p_expiry_date,p_mrn_date,coalesce(p_note,''),
    case when p_action='review' then true when p_action='reopen' then false else coalesce(v_previous.is_reviewed,false) end,
    case when p_action='review' then v_current else v_previous.reviewed_fingerprint end,
    case when p_action='review' then clock_timestamp() else v_previous.reviewed_at end,
    case when p_action='review' then auth.uid() else v_previous.reviewed_by end,clock_timestamp(),auth.uid())
  on conflict(item_code,expiry_date,mrn_date) do update set note=excluded.note,is_reviewed=excluded.is_reviewed,
    reviewed_fingerprint=excluded.reviewed_fingerprint,reviewed_at=excluded.reviewed_at,
    reviewed_by=excluded.reviewed_by,updated_at=excluded.updated_at,updated_by=excluded.updated_by
  returning * into v_saved;
  return to_jsonb(v_saved);
end;
$function$;

revoke all on function stock_management_private.save_expiry_review(text,date,text,text,text,timestamptz,date)
  from public,anon,service_role;
grant execute on function stock_management_private.save_expiry_review(text,date,text,text,text,timestamptz,date)
  to authenticated;

create function public.save_stock_expiry_review(
  p_item_code text,p_expiry_date date,p_fingerprint text,p_note text,
  p_action text,p_expected_updated_at timestamptz,p_mrn_date date
) returns jsonb language sql security invoker set search_path='' as $function$
  select stock_management_private.save_expiry_review(
    p_item_code,p_expiry_date,p_fingerprint,p_note,p_action,p_expected_updated_at,p_mrn_date);
$function$;
revoke all on function public.save_stock_expiry_review(text,date,text,text,text,timestamptz,date)
  from public,anon,service_role;
grant execute on function public.save_stock_expiry_review(text,date,text,text,text,timestamptz,date)
  to authenticated;

-- Old app versions must never silently open or mark an arbitrary receipt day.
-- Two-argument callers remain supported for unambiguous, single-day alerts.
create function stock_management_private.expiry_receipt_day(p_item_code text,p_expiry_date date)
returns date language plpgsql stable security invoker set search_path='' as $function$
declare v_date date; v_count integer;
begin
  select count(*),max(c.last_receipt_date) into v_count,v_date
    from public.stock_expiry_candidates c
    where c.item_code=p_item_code and c.expiry_date=p_expiry_date;
  if v_count>1 then
    raise exception 'This product has separate MRN dates. Reload the updated application and select a receipt day.'
      using errcode='22023';
  end if;
  return v_date;
end;
$function$;
revoke all on function stock_management_private.expiry_receipt_day(text,date) from public,anon;
grant execute on function stock_management_private.expiry_receipt_day(text,date) to authenticated,service_role;
create or replace function public.get_stock_expiry_item(p_item_code text,p_expiry_date date)
returns jsonb language sql stable security invoker set search_path='' as $function$
  select public.get_stock_expiry_item(p_item_code,p_expiry_date,
    stock_management_private.expiry_receipt_day(p_item_code,p_expiry_date));
$function$;
create or replace function stock_management_private.save_expiry_review(
  p_item_code text,p_expiry_date date,p_fingerprint text,p_note text,
  p_action text,p_expected_updated_at timestamptz
) returns jsonb language sql security invoker set search_path='' as $function$
  select stock_management_private.save_expiry_review(
    p_item_code,p_expiry_date,p_fingerprint,p_note,p_action,p_expected_updated_at,
    stock_management_private.expiry_receipt_day(p_item_code,p_expiry_date));
$function$;

create function stock_management_private.bump_expiry_receipt_review_revision()
returns trigger language plpgsql security definer set search_path='' as $function$
begin
  update public.stock_workspace_cache_revisions set revision=revision+1 where source='expiry_reviews';
  return null;
end;
$function$;
revoke all on function stock_management_private.bump_expiry_receipt_review_revision()
  from public,anon,authenticated,service_role;
create trigger stock_workspace_cache_expiry_receipt_reviews
  after insert or update or delete or truncate on public.stock_expiry_receipt_reviews
  for each statement execute function stock_management_private.bump_expiry_receipt_review_revision();
-- Invalidate complete-register and detail caches after the grouping change.
update public.stock_workspace_cache_revisions set revision=revision+1
  where source in ('expiry_receipts','expiry_reviews');
notify pgrst,'reload schema';
