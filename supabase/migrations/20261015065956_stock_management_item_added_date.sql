-- Item Report addition dates are Dubai calendar dates, never import created_at.
-- Preserve function owners, existing privileges, RLS and all branch identities.
select pg_advisory_xact_lock(hashtext('stock_management_refresh'));
select pg_advisory_xact_lock(hashtext('stock_catalog_refresh'));

CREATE OR REPLACE FUNCTION stock_management_private.refresh_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '120s'
AS $function$
declare
  v_meta jsonb;
  v_sales_end date;
  v_sales_start date;
  v_days integer;
  v_count integer;
begin
  if not (
    coalesce(auth.role() = 'service_role', false)
    or (auth.uid() is not null and public.item_tracker_my_role() = 'inventory')
  ) then
    raise exception 'Inventory access required' using errcode = '42501';
  end if;
  if not pg_try_advisory_xact_lock(hashtext('stock_management_refresh')) then
    raise exception 'A stock refresh is already running. Please try again shortly.';
  end if;

  select max(inv_date), greatest(min(inv_date), max(inv_date) - 44)
    into v_sales_end, v_sales_start from public.sales_last_45_days;
  v_days := greatest(v_sales_end - v_sales_start + 1, 1);
  v_meta := jsonb_build_object(
    'refreshed_at', now(),
    'stock_updated_at', (select max(created_at) from public.stk_ledger),
    'mrn_through', (select max(mrn_date) from public.mrn_apg_2026),
    'sales_2026_through', (select max(to_date(month, 'MM/YYYY')) from public.sales_history where month ~ '^(0[1-9]|1[0-2])/2026$'),
    'demand_from', v_sales_start, 'demand_through', v_sales_end,
    'demand_days', v_days,
    'scope', 'STORE + all active APG and 71 branches; other warehouses excluded',
    'mrn_source', 'mrn_apg_2026',
    'sales_2025_source', 'sales_history_2025', 'sales_2026_source', 'sales_history'
  );

  -- DELETE and INSERT are in the same transaction. Readers see the old
  -- complete snapshot until the new one commits, including on any failure.
  delete from public.stock_management_snapshot where true;
  insert into public.stock_management_snapshot
    (item_code,item_name,category,supplier,company,last_mrn_date,total_stock,
     days_on_hand,stock_status,sales_2026,payload)
  with
  item_dates as materialized (
    select distinct on (btrim(i.item_code)) btrim(i.item_code) item_code,
      (i.added_date_time at time zone 'Asia/Dubai')::date added_date_time
    from public.item_report i where nullif(btrim(i.item_code),'') is not null
    order by btrim(i.item_code),i.created_at desc nulls last
  ),
  receipts as materialized (
    select btrim(item_code) item_code, mrn_date, coalesce(mrn_no,'') mrn_no,
      max(item_name) item_name, max(category_1) category,
      max(supplier) supplier, max(company) company, max(vendor) vendor,
      sum(coalesce(received_quantity,0)) last_mrn_qty
    from public.mrn_apg_2026
    where lower(btrim(status)) = 'approved'
      and lower(btrim(warehouse)) in ('store','main virtual','new virtual')
      and nullif(btrim(item_code),'') is not null and mrn_date is not null
    group by btrim(item_code),mrn_date,coalesce(mrn_no,'')
  ),
  last_receipts as materialized (
    select distinct on (item_code) * from receipts
    order by item_code,mrn_date desc,mrn_no desc
  ),
  active_branches as materialized (
    select distinct public._norm_text(branch_name) branch_key
    from public.branches where is_active is true
      and public._norm_text(branch_name) not in
        ('store','main virtual','new virtual','store - expired item','store-ws')
  ),
  ledger as materialized (
    select btrim(l.item_code) item_code, max(l.branch_name) branch,
      public._norm_text(l.branch_name) branch_key,
      max(l.company) ledger_company, max(coalesce(l.actual_qty,0)) qty
    from public.stk_ledger l join last_receipts r on r.item_code=btrim(l.item_code)
    group by btrim(l.item_code),public._norm_text(l.branch_name)
  ),
  stock as (
    select l.item_code,
      coalesce(sum(l.qty) filter (where l.branch_key='store'),0) store_stock,
      coalesce(sum(l.qty) filter (where a.branch_key is not null),0) branches_stock,
      count(*) filter (where a.branch_key is not null and l.qty>0) stocked_branches,
      coalesce(jsonb_agg(jsonb_build_object('branch',l.branch,'stock',l.qty,
        'company',l.ledger_company) order by l.qty desc,l.branch)
        filter (where a.branch_key is not null),'[]'::jsonb) branches
    from ledger l left join active_branches a on a.branch_key=l.branch_key
    group by l.item_code
  ),
  history_raw as (
    select btrim(h.item_code) item_code, to_date(h.month,'MM/YYYY') month_start,
      coalesce(h.cash,0) cash,coalesce(h.insurance,0) insurance,coalesce(h.online,0) online
    from public.sales_history_2025 h join last_receipts r on r.item_code=btrim(h.item_code)
    where h.month ~ '^(0[1-9]|1[0-2])/2025$'
    union all
    select btrim(h.item_code),to_date(h.month,'MM/YYYY'),
      coalesce(h.cash,0),coalesce(h.insurance,0),coalesce(h.online,0)
    from public.sales_history h join last_receipts r on r.item_code=btrim(h.item_code)
    where h.month ~ '^(0[1-9]|1[0-2])/2026$'
  ),
  monthly as materialized (
    select item_code,month_start,sum(cash) cash,sum(insurance) insurance,
      sum(online) online,sum(cash+insurance+online) total
    from history_raw group by item_code,month_start
  ),
  annual as (
    select item_code,extract(year from month_start)::integer yr,
      sum(cash) cash,sum(insurance) insurance,sum(online) online,sum(total) total
    from monthly group by item_code,extract(year from month_start)
  ),
  best as (
    select distinct on (item_code,extract(year from month_start))
      item_code,extract(year from month_start)::integer yr,
      to_char(month_start,'MM/YYYY') best_month,total best_qty
    from monthly where total>0
    order by item_code,extract(year from month_start),total desc,month_start
  ),
  year_data as (
    select a.item_code,jsonb_object_agg(a.yr::text,jsonb_build_object(
      'cash',a.cash,'insurance',a.insurance,'online',a.online,'total',a.total,
      'best_month',b.best_month,'best_qty',b.best_qty)) years
    from annual a left join best b on b.item_code=a.item_code and b.yr=a.yr
    group by a.item_code
  ),
  month_data as (
    select item_code,jsonb_agg(jsonb_build_object('month',to_char(month_start,'MM/YYYY'),
      'cash',cash,'insurance',insurance,'online',online,'total',total) order by month_start) monthly_sales
    from monthly group by item_code
  ),
  demand as (
    select btrim(s.item_code) item_code,sum(coalesce(s.qty,0)) recent_qty
    from public.sales_last_45_days s join last_receipts r on r.item_code=btrim(s.item_code)
      join active_branches a on a.branch_key=public._norm_text(s.branch_name)
    where s.inv_date between v_sales_start and v_sales_end
    group by btrim(s.item_code)
  ),
  combined as (
    select r.*,coalesce(s.store_stock,0) store_stock,
      coalesce(s.branches_stock,0) branches_stock,
      coalesce(s.store_stock,0)+coalesce(s.branches_stock,0) total_stock,
      coalesce(s.stocked_branches,0) stocked_branches,
      coalesce(s.branches,'[]'::jsonb) branches,
      coalesce(d.recent_qty,0) recent_qty,
      greatest(coalesce(d.recent_qty,0),0)/v_days daily_sales,
      coalesce(y.years,'{}'::jsonb) years,
      coalesce(m.monthly_sales,'[]'::jsonb) monthly_sales
    from last_receipts r left join stock s on s.item_code=r.item_code
      left join demand d on d.item_code=r.item_code
      left join year_data y on y.item_code=r.item_code
      left join month_data m on m.item_code=r.item_code
  ),
  final as (
    select c.*,case when total_stock<=0 then 0 when daily_sales>0
        then total_stock/daily_sales end days_on_hand,
      case when total_stock<=0 then 'no_stock' when daily_sales<=0 then 'no_sales'
        when total_stock/daily_sales<30 then 'low_cover' else 'in_stock' end stock_status
    from combined c
  )
  select item_code,coalesce(item_name,''),coalesce(category,''),coalesce(supplier,''),
    coalesce(company,''),mrn_date,total_stock,days_on_hand,stock_status,
    coalesce((years->'2026'->>'total')::numeric,0),
    jsonb_build_object(
      'item_code',item_code,'item_name',coalesce(item_name,''),'category',coalesce(category,''),
      'supplier',coalesce(supplier,''),'company',coalesce(company,''),'vendor',vendor,
      'added_date_time',i.added_date_time,
      'last_mrn_date',mrn_date,'last_mrn_no',mrn_no,'last_mrn_qty',last_mrn_qty,
      'store_stock',store_stock,'branches_stock',branches_stock,'total_stock',total_stock,
      'store_branches_ratio',case when branches_stock>0 then store_stock/branches_stock end,
      'stocked_branches',stocked_branches,'branches',branches,'recent_sales',recent_qty,
      'daily_sales',daily_sales,'days_on_hand',days_on_hand,'stock_status',stock_status,
      'years',years,'monthly_sales',monthly_sales,'meta',v_meta
    )
  from final left join item_dates i using(item_code);
  get diagnostics v_count = row_count;
  if v_count=0 then raise exception 'No MRN products found; the existing snapshot was preserved.'; end if;
  return v_meta || jsonb_build_object('items',v_count);
end;
$function$;

CREATE OR REPLACE FUNCTION stock_management_private.refresh_catalog()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_end date; v_start date; v_recent_days integer; v_baseline_days integer; v_meta jsonb; v_count integer;
begin
  if coalesce(current_setting('request.jwt.claims',true)::jsonb->>'role','') <> 'service_role'
     and not (auth.uid() is not null and public.item_tracker_my_role()='inventory') then
    raise exception 'Inventory access required' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('stock_catalog_refresh'));
  select max(inv_date),greatest(min(inv_date),max(inv_date)-44) into v_end,v_start from public.sales_last_45_days;
  v_recent_days := greatest(least(v_end-v_start+1,3),0);
  v_baseline_days := greatest(v_end-v_start+1-v_recent_days,0);
  v_meta := jsonb_build_object('refreshed_at',now(),
    'catalog_updated_at',(select max(created_at) from public.item_report),
    'stock_updated_at',(select max(created_at) from public.stk_ledger),
    'demand_from',v_start,'demand_through',v_end,'recent_from',greatest(v_start,v_end-2),
    'baseline_through',v_end-3,'recent_days',v_recent_days,'baseline_days',v_baseline_days,
    'demand_days',v_recent_days+v_baseline_days,
    'sales_2026_through',(select max(to_date(month,'MM/YYYY')) from public.sales_history where month ~ '^(0[1-9]|1[0-2])/2026$'),
    'scope','Stock balances use STORE and active registered branches. Annual sales include all source branches.',
    'surge_multiple',2,'surge_min_units',3);
  delete from public.stock_catalog_snapshot;
  insert into public.stock_catalog_snapshot(item_code,item_name,category,supplier,total_stock,days_on_hand,sales_2026,demand_surge,payload)
  with catalog as materialized (
    select distinct on (btrim(item_code)) btrim(item_code) item_code,coalesce(item_name,'') item_name,
      coalesce(category,'') category,coalesce(supplier,'') supplier,coalesce(company,'') company,
      (to_jsonb(i)-'created_at'-'all_barcode') || jsonb_build_object(
        'added_date_time',(i.added_date_time at time zone 'Asia/Dubai')::date) facts
    from public.item_report i where nullif(btrim(item_code),'') is not null
    order by btrim(item_code),created_at desc nulls last
  ), active as materialized (
    select public._norm_text(branch_name) branch_key,max(branch_name) branch,max(branch_group) branch_group
    from public.branches where is_active is true and public._norm_text(branch_name) not in
      ('store','main virtual','new virtual','store - expired item','store-ws')
    group by public._norm_text(branch_name)
  ), ledger as materialized (
    select btrim(l.item_code) item_code,public._norm_text(l.branch_name) branch_key,max(coalesce(l.actual_qty,0)) qty
    from public.stk_ledger l join catalog c on c.item_code=btrim(l.item_code)
    group by btrim(l.item_code),public._norm_text(l.branch_name)
  ), stock as (
    select l.item_code,coalesce(sum(qty) filter(where l.branch_key='store'),0) store_stock,
      coalesce(sum(qty) filter(where a.branch_key is not null),0) branches_stock,
      coalesce(sum(qty) filter(where a.branch_group='APG'),0) apg_stock,
      coalesce(sum(qty) filter(where a.branch_group='71'),0) stock_71,
      coalesce(jsonb_object_agg(l.branch_key,jsonb_build_object('stock',qty)) filter(where a.branch_key is not null),'{}'::jsonb) branch_stock
    from ledger l left join active a using(branch_key) group by l.item_code
  ), recent_branch as materialized (
    select btrim(s.item_code) item_code,a.branch_key,
      coalesce(sum(coalesce(qty,0)) filter(where inv_date>=v_end-2),0) last_3_sales,
      coalesce(sum(coalesce(qty,0)) filter(where inv_date<v_end-2),0) baseline_sales
    from public.sales_last_45_days s join catalog c on c.item_code=btrim(s.item_code)
      join active a on a.branch_key=public._norm_text(s.branch_name)
    where inv_date between v_start and v_end group by btrim(s.item_code),a.branch_key
  ), demand as (
    select item_code,sum(last_3_sales) last_3_sales,sum(baseline_sales) baseline_sales,
      jsonb_object_agg(branch_key,jsonb_build_object('last_3_sales',last_3_sales,'baseline_sales',baseline_sales,
        'recent_sales',last_3_sales+baseline_sales)) branch_demand
    from recent_branch group by item_code
  ), history_raw as (
    select btrim(h.item_code) item_code,to_date(month,'MM/YYYY') month_start,
      coalesce(cash,0) cash,coalesce(insurance,0) insurance,coalesce(online,0) online
    from public.sales_history_2025 h join catalog c on c.item_code=btrim(h.item_code)
    where month ~ '^(0[1-9]|1[0-2])/2025$'
    union all
    select btrim(h.item_code),to_date(month,'MM/YYYY'),coalesce(cash,0),coalesce(insurance,0),coalesce(online,0)
    from public.sales_history h join catalog c on c.item_code=btrim(h.item_code)
    where month ~ '^(0[1-9]|1[0-2])/2026$'
  ), monthly as materialized (
    select item_code,month_start,sum(cash) cash,sum(insurance) insurance,sum(online) online,
      sum(cash+insurance+online) total from history_raw group by item_code,month_start
  ), annual as (
    select item_code,extract(year from month_start)::integer yr,sum(cash) cash,sum(insurance) insurance,
      sum(online) online,sum(total) total from monthly group by item_code,extract(year from month_start)
  ), best as (
    select distinct on (item_code,extract(year from month_start)) item_code,extract(year from month_start)::integer yr,
      to_char(month_start,'MM/YYYY') best_month,total best_qty from monthly where total>0
    order by item_code,extract(year from month_start),total desc,month_start
  ), years as (
    select a.item_code,jsonb_object_agg(a.yr::text,jsonb_build_object('cash',cash,'insurance',insurance,'online',online,
      'total',total,'best_month',best_month,'best_qty',best_qty)) years
    from annual a left join best b on a.item_code=b.item_code and a.yr=b.yr group by a.item_code
  ), months as (
    select item_code,jsonb_agg(jsonb_build_object('month',to_char(month_start,'MM/YYYY'),
      'total',total,'cash',cash,'insurance',insurance,'online',online) order by month_start) monthly_sales
    from monthly group by item_code
  ), combined as (
    select c.*,coalesce(s.store_stock,0) store_stock,coalesce(s.branches_stock,0) branches_stock,
      coalesce(s.apg_stock,0) apg_stock,coalesce(s.stock_71,0) stock_71,
      coalesce(s.store_stock,0)+coalesce(s.branches_stock,0) total_stock,
      coalesce(s.branch_stock,'{}'::jsonb) branch_stock,coalesce(d.branch_demand,'{}'::jsonb) branch_demand,
      coalesce(d.last_3_sales,0) last_3_sales,coalesce(d.baseline_sales,0) baseline_sales,
      coalesce(d.last_3_sales,0)+coalesce(d.baseline_sales,0) recent_sales,
      coalesce(d.last_3_sales,0)/nullif(v_recent_days,0) recent_daily,
      coalesce(d.baseline_sales,0)/nullif(v_baseline_days,0) baseline_daily,
      (coalesce(d.last_3_sales,0)+coalesce(d.baseline_sales,0))/nullif(v_recent_days+v_baseline_days,0) daily_sales,
      coalesce(y.years,'{}'::jsonb) years,coalesce(m.monthly_sales,'[]'::jsonb) monthly_sales
    from catalog c left join stock s using(item_code) left join demand d using(item_code)
      left join years y using(item_code) left join months m using(item_code)
  ), final as (
    select c.*,case when total_stock<=0 then 0 when daily_sales>0 then total_stock/daily_sales end days_on_hand,
      case when total_stock<=0 then 'no_stock' when coalesce(daily_sales,0)<=0 then 'no_sales'
        when total_stock/daily_sales<30 then 'low_cover' else 'in_stock' end stock_status,
      coalesce(last_3_sales>=3 and baseline_daily>0 and recent_daily>=2*baseline_daily,false) demand_surge,
      coalesce(last_3_sales>=3 and baseline_daily<=0 and v_baseline_days>0,false) new_demand,
      case when baseline_daily>0 then (recent_daily/baseline_daily-1)*100 end growth_percent
    from combined c
  )
  select item_code,item_name,category,supplier,total_stock,days_on_hand,coalesce((years->'2026'->>'total')::numeric,0),demand_surge,
    facts || jsonb_build_object('item_code',item_code,'item_name',item_name,'category',category,'supplier',supplier,'company',company,
      'store_stock',store_stock,'branches_stock',branches_stock,'apg_stock',apg_stock+store_stock+stock_71,'apg_branches_stock',apg_stock,'stock_71',stock_71,'total_stock',total_stock,
      'branch_stock',branch_stock,'branch_demand',branch_demand,'last_3_sales',last_3_sales,'baseline_sales',baseline_sales,
      'recent_sales',recent_sales,'recent_daily',recent_daily,'baseline_daily',baseline_daily,'daily_sales',daily_sales,
      'days_on_hand',days_on_hand,'stock_status',stock_status,'demand_surge',demand_surge,'new_demand',new_demand,
      'growth_percent',growth_percent,'years',years,'monthly_sales',monthly_sales,'meta',v_meta)
  from final;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Item Report is empty; previous snapshot preserved'; end if;
end;
$function$;

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
    'rows',coalesce((select jsonb_agg((to_jsonb(p)-'receipts') || jsonb_build_object('product_data',
        coalesce(p.product_data,'{}'::jsonb) || jsonb_build_object('added_date_time',i.added_date_time)) order by expiry_date,item_name,item_code) from paged p left join lateral (
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
      'source','mrn_apg_2026','persistent',true,'batch_stock_available',false)
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_expiry_item(p_item_code text, p_expiry_date date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select to_jsonb(c)||jsonb_build_object('note',coalesce(r.note,''),
    'review_updated_at',r.updated_at,'reviewed_at',r.reviewed_at,
    'is_reviewed',coalesce(r.is_reviewed and r.reviewed_fingerprint=c.receipt_fingerprint,false),
    'new_receipts',coalesce(r.is_reviewed and r.reviewed_fingerprint is distinct from c.receipt_fingerprint,false),
    'product_data',(case when c.stock_snapshot_missing then
      (select evidence.product_data from public.stock_expiry_alert_receipts evidence
       where evidence.item_code=c.item_code and evidence.expiry_date=c.expiry_date
       order by evidence.mrn_date desc,evidence.mrn_no desc,evidence.warehouse limit 1)
      else c.product_data end) || jsonb_build_object('added_date_time',i.added_date_time))
  from public.stock_expiry_candidates c left join public.stock_expiry_reviews r
    on r.item_code=c.item_code and r.expiry_date=c.expiry_date
  left join lateral (
    select (i.added_date_time at time zone 'Asia/Dubai')::date added_date_time
    from public.item_report i where btrim(i.item_code)=c.item_code
    order by i.created_at desc nulls last limit 1
  ) i on true
  where c.item_code=p_item_code and c.expiry_date=p_expiry_date;
$function$;

-- Backfill both complete snapshots without changing stock, sales or reviews.
with dates as materialized (select distinct on (btrim(i.item_code)) btrim(i.item_code) item_code,
      (i.added_date_time at time zone 'Asia/Dubai')::date added_date_time
    from public.item_report i where nullif(btrim(i.item_code),'') is not null
    order by btrim(i.item_code),i.created_at desc nulls last)
update public.stock_management_snapshot s
set payload = s.payload || jsonb_build_object('added_date_time',i.added_date_time),
    updated_at=now()
from dates i where s.item_code=i.item_code;

with dates as materialized (select distinct on (btrim(i.item_code)) btrim(i.item_code) item_code,
      (i.added_date_time at time zone 'Asia/Dubai')::date added_date_time
    from public.item_report i where nullif(btrim(i.item_code),'') is not null
    order by btrim(i.item_code),i.created_at desc nulls last)
update public.stock_catalog_snapshot s
set payload = jsonb_set(
    s.payload || jsonb_build_object('added_date_time',i.added_date_time),
    '{meta}', (s.payload->'meta') || jsonb_build_object('refreshed_at',now())
  ), updated_at=now()
from dates i where s.item_code=i.item_code;
