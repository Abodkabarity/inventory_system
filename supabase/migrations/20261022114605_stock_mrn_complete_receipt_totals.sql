-- Sum every approved MRN on the latest receipt day; expand receipt lines only
-- in product details. Stock balances and expiry alert identity are unchanged.
create index if not exists mrn_apg_2026_item_receipt_day_idx
  on public.mrn_apg_2026 (btrim(item_code),mrn_date)
  where lower(btrim(status))='approved'
    and lower(btrim(warehouse)) in ('store','main virtual','new virtual');

create or replace function stock_management_private.mrn_receipt_details(p_item_code text,p_date date)
returns jsonb language sql stable security invoker set search_path='' as $function$
  with lines as materialized (
    select m.mrn_date,coalesce(m.mrn_no,'') mrn_no,lower(btrim(m.warehouse)) warehouse,
      m.expiry_date,sum(coalesce(m.ordered_quantity,0)) ordered_qty,
      sum(coalesce(m.received_quantity,0)) received_qty,
      bool_or(coalesce(m.received_quantity,0)>0) has_receipt,
      min(nullif(btrim(m.vendor),'')) vendor,
      string_agg(distinct nullif(btrim(m.reference),''),' · ' order by nullif(btrim(m.reference),'')) reference
    from public.mrn_apg_2026 m
    where btrim(m.item_code)=p_item_code and m.mrn_date=p_date
      and lower(btrim(m.status))='approved'
      and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
    group by m.mrn_date,coalesce(m.mrn_no,''),lower(btrim(m.warehouse)),m.expiry_date
  )
  select case when count(*)=0 then '{}'::jsonb else jsonb_build_object(
    'receipt_scope','latest_mrn_date','receipt_count',count(distinct mrn_no),
    'receipt_line_count',count(*),'expiry_count',count(distinct expiry_date) filter(where has_receipt),
    'expiry_date',min(expiry_date) filter(where has_receipt),
    'ordered_quantity',sum(ordered_qty),'received_quantity',sum(received_qty),
    'last_mrn_qty',sum(received_qty),'vendor',left(upper(min(vendor)),10),
    'receipt_lines',jsonb_agg(jsonb_build_object(
      'mrn_date',mrn_date,'mrn_no',mrn_no,'warehouse',warehouse,
      'expiry_date',expiry_date,'ordered_qty',ordered_qty,'received_qty',received_qty,
      'vendor',left(upper(vendor),10),'reference',coalesce(reference,''))
      order by mrn_date desc,mrn_no desc,expiry_date nulls last,warehouse)
  ) end from lines;
$function$;
revoke all on function stock_management_private.mrn_receipt_details(text,date) from public,anon;
grant execute on function stock_management_private.mrn_receipt_details(text,date) to authenticated,service_role;

CREATE OR REPLACE FUNCTION stock_management_private.refresh_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '120s'
 SET enable_nestloop TO 'off'
AS $function$
declare
  v_meta jsonb;
  v_sales_end date;
  v_sales_start date;
  v_days integer;
  v_count integer;
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_month date := date_trunc('month',v_today)::date;
  v_month_meta jsonb;
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
  v_month_meta := jsonb_build_object(
    'monthly_current_month',v_month,'monthly_current_source','sales_last_45_days',
    'monthly_sales_through',v_month,'sales_updated_at',now(),
    'monthly_current_from',case when v_sales_end>=v_month then greatest(v_sales_start,v_month) end,
    'monthly_current_through',case when v_sales_end>=v_month then least(v_sales_end,v_today) end,
    'sales_2026_through',greatest(
      (select max(to_date(month,'MM/YYYY')) from public.sales_history
       where month ~ '^(0[1-9]|1[0-2])/2026$' and to_date(month,'MM/YYYY')<v_month),
      case when extract(year from v_month)=2026 then v_month end));
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
  ) || v_month_meta;

  -- DELETE and INSERT are in the same transaction. Readers see the old
  -- complete snapshot until the new one commits, including on any failure.
  delete from public.stock_management_snapshot where true;
  with
  item_dates as materialized (
    select distinct on (btrim(i.item_code)) btrim(i.item_code) item_code,
      (i.added_date_time at time zone 'Asia/Dubai')::date added_date_time
    from public.item_report i where nullif(btrim(i.item_code),'') is not null
    order by btrim(i.item_code),i.created_at desc nulls last
  ),
  receipts as materialized (
    select btrim(item_code) item_code,mrn_date,max(coalesce(mrn_no,'')) mrn_no,
      max(item_name) item_name,max(category_1) category,
      max(supplier) supplier,max(company) company,min(nullif(btrim(vendor),'')) vendor,
      sum(coalesce(received_quantity,0)) last_mrn_qty,
      sum(coalesce(ordered_quantity,0)) ordered_quantity,
      min(expiry_date) filter(where coalesce(received_quantity,0)>0) expiry_date,
      count(distinct coalesce(mrn_no,'')) receipt_count,
      count(distinct expiry_date) filter(where coalesce(received_quantity,0)>0) expiry_count
    from public.mrn_apg_2026
    where lower(btrim(status))='approved'
      and lower(btrim(warehouse)) in ('store','main virtual','new virtual')
      and nullif(btrim(item_code),'') is not null and mrn_date is not null
    group by btrim(item_code),mrn_date
  ),
  last_receipts as materialized (
    select distinct on (item_code) * from receipts
    order by item_code,mrn_date desc,mrn_no desc
  ),
  report_items as materialized (
    select item_code from last_receipts
    union select item_code from public.stock_expiry_alert_receipts
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
  current_lines as materialized (
    select r.item_code,public._norm_text(s.branch_name) branch_key,coalesce(s.qty,0) qty,
      case when lower(regexp_replace(btrim(coalesce(s.inv_type,'')),'[[:space:]]+',' ','g'))
          in ('insurance','direct insurance','dirict insurance') then 'insurance'
        when lower(btrim(coalesce(s.sales_type,''))) in ('delivery invoice','return delivery invoice') then 'online'
        else 'cash' end channel
    from public.sales_last_45_days s join report_items r on r.item_code=btrim(s.item_code)
    where s.inv_date between v_month and v_today
  ),
  current_month as (
    select r.item_code,l.branch_key,v_month month_start,
      coalesce(sum(l.qty) filter(where l.channel='cash'),0) cash,
      coalesce(sum(l.qty) filter(where l.channel='insurance'),0) insurance,
      coalesce(sum(l.qty) filter(where l.channel='online'),0) online
    from report_items r left join current_lines l using(item_code)
    group by r.item_code,l.branch_key
  ),
  history_raw as materialized (
    select btrim(h.item_code) item_code,public._norm_text(h.branch_name) branch_key,
      to_date(h.month,'MM/YYYY') month_start,
      coalesce(h.cash,0) cash,coalesce(h.insurance,0) insurance,coalesce(h.online,0) online
    from public.sales_history_2025 h join report_items r on r.item_code=btrim(h.item_code)
    where h.month ~ '^(0[1-9]|1[0-2])/2025$' and to_date(h.month,'MM/YYYY')<v_month
    union all
    select btrim(h.item_code),public._norm_text(h.branch_name),to_date(h.month,'MM/YYYY'),
      coalesce(h.cash,0),coalesce(h.insurance,0),coalesce(h.online,0)
    from public.sales_history h join report_items r on r.item_code=btrim(h.item_code)
    where h.month ~ '^(0[1-9]|1[0-2])/(20[2-9][0-9])$'
      and to_date(h.month,'MM/YYYY')>=date '2026-01-01' and to_date(h.month,'MM/YYYY')<v_month
    union all select item_code,branch_key,month_start,cash,insurance,online from current_month
  ),
  branch_annual as (
    select item_code,branch_key,extract(year from month_start)::integer yr,sum(cash+insurance+online) total
    from history_raw where branch_key is not null group by item_code,branch_key,extract(year from month_start)
  ),
  branch_years as (
    select item_code,branch_key,jsonb_object_agg(yr::text,total) years
    from branch_annual group by item_code,branch_key
  ),
  branch_year_data as (
    select item_code,jsonb_object_agg(branch_key,years) branches
    from branch_years group by item_code
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
      'cash',cash,'insurance',insurance,'online',online,'total',total,
      'source',case when month_start=v_month then 'sales_last_45_days' else 'sales_history' end,
      'through',case when month_start=v_month then case when v_sales_end>=v_month then least(v_sales_end,v_today) end
        else (month_start+interval '1 month'-interval '1 day')::date end) order by month_start) monthly_sales
    from monthly group by item_code
  ),
  saved_sales_updated as (
    -- Only mutable sales analytics are refreshed. Receipt quantities, dates,
    -- fingerprints, review records and saved stock facts remain untouched.
    update public.stock_expiry_alert_receipts e set product_data =
      coalesce(e.product_data,'{}'::jsonb) || jsonb_build_object(
        'years',coalesce(y.years,'{}'::jsonb),'monthly_sales',coalesce(m.monthly_sales,'[]'::jsonb),
        'branch_year_sales',coalesce(byd.branches,'{}'::jsonb),
        'branches',coalesce((select jsonb_agg(
      b.value || jsonb_build_object(
        'sales_2025',coalesce((byd.branches->public._norm_text(b.value->>'branch')->>'2025')::numeric,0),
        'sales_2026',coalesce((byd.branches->public._norm_text(b.value->>'branch')->>'2026')::numeric,0))
      order by coalesce((b.value->>'stock')::numeric,0) desc,b.value->>'branch')
      from jsonb_array_elements(coalesce(e.product_data->'branches','[]'::jsonb)) b),'[]'::jsonb),
        'meta',coalesce(e.product_data->'meta','{}'::jsonb)||v_month_meta)
    from report_items r left join year_data y using(item_code)
      left join month_data m using(item_code) left join branch_year_data byd using(item_code)
    where e.item_code=r.item_code
    returning e.item_code
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
      coalesce((select jsonb_agg(
      b.value || jsonb_build_object(
        'sales_2025',coalesce((byd.branches->public._norm_text(b.value->>'branch')->>'2025')::numeric,0),
        'sales_2026',coalesce((byd.branches->public._norm_text(b.value->>'branch')->>'2026')::numeric,0))
      order by coalesce((b.value->>'stock')::numeric,0) desc,b.value->>'branch')
      from jsonb_array_elements(coalesce(s.branches,'[]'::jsonb)) b),'[]'::jsonb) branches,
      coalesce(byd.branches,'{}'::jsonb) branch_year_sales,
      coalesce(d.recent_qty,0) recent_qty,
      greatest(coalesce(d.recent_qty,0),0)/v_days daily_sales,
      coalesce(y.years,'{}'::jsonb) years,
      coalesce(m.monthly_sales,'[]'::jsonb) monthly_sales
    from last_receipts r left join stock s on s.item_code=r.item_code
      left join demand d on d.item_code=r.item_code
      left join year_data y on y.item_code=r.item_code
      left join month_data m on m.item_code=r.item_code
      left join branch_year_data byd on byd.item_code=r.item_code
  ),
  final as (
    select c.*,case when total_stock<=0 then 0 when daily_sales>0
        then total_stock/daily_sales end days_on_hand,
      case when total_stock<=0 then 'no_stock' when daily_sales<=0 then 'no_sales'
        when total_stock/daily_sales<30 then 'low_cover' else 'in_stock' end stock_status
    from combined c
  )
  insert into public.stock_management_snapshot
    (item_code,item_name,category,supplier,company,last_mrn_date,total_stock,
     days_on_hand,stock_status,sales_2026,payload)
  select item_code,coalesce(item_name,''),coalesce(category,''),coalesce(supplier,''),
    coalesce(company,''),mrn_date,total_stock,days_on_hand,stock_status,
    coalesce((years->'2026'->>'total')::numeric,0),
    jsonb_build_object(
      'item_code',item_code,'item_name',coalesce(item_name,''),'category',coalesce(category,''),
      'supplier',coalesce(supplier,''),'company',coalesce(company,''),'vendor',vendor,
      'added_date_time',i.added_date_time,
      'last_mrn_date',mrn_date,'last_mrn_no',mrn_no,'last_mrn_qty',last_mrn_qty,
      'receipt_scope','latest_mrn_date','receipt_count',receipt_count,'expiry_count',expiry_count,
      'received_quantity',last_mrn_qty,'ordered_quantity',ordered_quantity,'expiry_date',expiry_date,
      'store_stock',store_stock,'branches_stock',branches_stock,'total_stock',total_stock,
      'store_branches_ratio',case when branches_stock>0 then store_stock/branches_stock end,
      'stocked_branches',stocked_branches,'branches',branches,'recent_sales',recent_qty,
      'daily_sales',daily_sales,'days_on_hand',days_on_hand,'stock_status',stock_status,
      'years',years,'monthly_sales',monthly_sales,'branch_year_sales',branch_year_sales,'meta',v_meta
    )
  from final left join item_dates i using(item_code);
  get diagnostics v_count = row_count;
  if v_count=0 then raise exception 'No MRN products found; the existing snapshot was preserved.'; end if;
  return v_meta || jsonb_build_object('items',v_count);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_management_item(p_item_code text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with snapshot as materialized (
    select * from public.stock_management_snapshot where item_code=p_item_code
  ), sales_2025 as (
    select public._norm_text(h.branch_name) as branch_key,
      sum(coalesce(h.cash, 0) + coalesce(h.insurance, 0) + coalesce(h.online, 0))
        as total_sales
    from public.sales_history_2025 h
    where btrim(h.item_code) = p_item_code
      and h.month ~ '^(0[1-9]|1[0-2])/2025$'
      and not exists(select 1 from snapshot where payload ? 'branch_year_sales')
    group by public._norm_text(h.branch_name)
  ),
  sales_2026 as (
    select public._norm_text(h.branch_name) as branch_key,
      sum(coalesce(h.cash, 0) + coalesce(h.insurance, 0) + coalesce(h.online, 0))
        as total_sales
    from public.sales_history h
    where btrim(h.item_code) = p_item_code
      and h.month ~ '^(0[1-9]|1[0-2])/2026$'
      and not exists(select 1 from snapshot where payload ? 'branch_year_sales')
    group by public._norm_text(h.branch_name)
  ),
  branch_details as (
    select coalesce(
      jsonb_agg(
        b.branch || jsonb_build_object(
          'sales_2025', coalesce(y25.total_sales, 0),
          'sales_2026', coalesce(y26.total_sales, 0)
        )
        order by coalesce((b.branch->>'stock')::numeric, 0) desc,
          b.branch->>'branch'
      ),
      '[]'::jsonb
    ) as branches
    from snapshot
    cross join lateral jsonb_array_elements(snapshot.payload->'branches') b(branch)
    left join sales_2025 y25
      on y25.branch_key = public._norm_text(b.branch->>'branch')
    left join sales_2026 y26
      on y26.branch_key = public._norm_text(b.branch->>'branch')
    where snapshot.item_code = p_item_code
  )
  select (snapshot.payload-'branch_year_sales') ||
    stock_management_private.mrn_receipt_details(snapshot.item_code,snapshot.last_mrn_date) ||
    jsonb_build_object(
    'reference', coalesce((
      select nullif(btrim(m.reference), '')
      from public.mrn_apg_2026 m
      where m.item_code = snapshot.item_code
        and m.mrn_date = snapshot.last_mrn_date
        and coalesce(m.mrn_no, '') = coalesce(snapshot.payload->>'last_mrn_no', '')
        and nullif(btrim(m.reference), '') is not null
      order by m.reference
      limit 1
    ), ''),
    'branches',case when snapshot.payload ? 'branch_year_sales' then snapshot.payload->'branches'
      else (select branches from branch_details) end
  )
  from snapshot
  where snapshot.item_code = p_item_code;
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_management_product_details(p_item_code text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with mrn as materialized (
    select s.payload || public.get_stock_management_item(p_item_code) payload
    from public.stock_management_snapshot s where s.item_code=p_item_code
  ), catalog as materialized (
    select public.get_stock_catalog_item(p_item_code)-'_cache_version' payload
  ) select case when c.payload is not null then
      ((m.payload-'branch_year_sales') || c.payload || jsonb_build_object(
        'mrn_details',m.payload-'branch_year_sales','reference',m.payload->>'reference','vendor',m.payload->>'vendor',
        'last_mrn_date',m.payload->'last_mrn_date','last_mrn_no',m.payload->'last_mrn_no',
        'last_mrn_qty',m.payload->'last_mrn_qty','received_quantity',m.payload->'received_quantity',
        'ordered_quantity',m.payload->'ordered_quantity','expiry_date',m.payload->'expiry_date',
        'receipt_scope',m.payload->'receipt_scope','receipt_count',m.payload->'receipt_count',
        'expiry_count',m.payload->'expiry_count','receipt_lines',m.payload->'receipt_lines') ||
      case when m.payload->'meta'->>'monthly_current_source'='sales_last_45_days' then
        jsonb_build_object('years',m.payload->'years','monthly_sales',m.payload->'monthly_sales',
          'meta',coalesce(c.payload->'meta','{}'::jsonb)||coalesce((select jsonb_object_agg(e.key,e.value)
        from jsonb_each(m.payload->'meta') e where e.key in ('monthly_current_month','monthly_current_source','monthly_sales_through','sales_updated_at','monthly_current_from','monthly_current_through','sales_2026_through')),'{}'::jsonb),
          'branches',coalesce((select jsonb_agg(
      b.value || jsonb_build_object(
        'sales_2025',coalesce(((m.payload->'branch_year_sales')->public._norm_text(b.value->>'branch')->>'2025')::numeric,0),
        'sales_2026',coalesce(((m.payload->'branch_year_sales')->public._norm_text(b.value->>'branch')->>'2026')::numeric,0))
      order by coalesce((b.value->>'stock')::numeric,0) desc,b.value->>'branch')
      from jsonb_array_elements(coalesce(c.payload->'branches','[]'::jsonb)) b),'[]'::jsonb))
      else '{}'::jsonb end)
    else public.get_stock_management_item(p_item_code) ||
      jsonb_build_object('catalog_unavailable',true,'mrn_details',m.payload-'branch_year_sales')
    end
  from mrn m cross join catalog c;
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_management_page(p_search text DEFAULT ''::text, p_status text DEFAULT ''::text, p_category text DEFAULT ''::text, p_supplier text DEFAULT ''::text, p_received_from date DEFAULT NULL::date, p_received_to date DEFAULT NULL::date, p_sort text DEFAULT 'latest_mrn'::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with filtered as materialized (
    select * from public.stock_management_snapshot s
    where (coalesce(p_search,'')='' or strpos(lower(s.item_code||' '||s.item_name||' '||s.supplier||' '||s.company),lower(btrim(p_search)))>0)
      and (coalesce(p_status,'')='' or s.stock_status=p_status)
      and (coalesce(p_category,'')='' or s.category=p_category)
      and (coalesce(p_supplier,'')='' or s.supplier=p_supplier)
      and (p_received_from is null or s.last_mrn_date>=p_received_from)
      and (p_received_to is null or s.last_mrn_date<=p_received_to)
  ), paged as (
    select * from filtered order by
      case when p_sort='stock_high' then total_stock end desc nulls last,
      case when p_sort='sales_high' then sales_2026 end desc nulls last,
      case when p_sort='days_low' then days_on_hand end asc nulls last,
      last_mrn_date desc,item_code
    limit least(greatest(p_limit,1),5000) offset greatest(p_offset,0)
  )
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg((payload - 'branches' - 'monthly_sales' - 'meta' - 'branch_year_sales') || jsonb_build_object('vendor',left(upper(payload->>'vendor'),10))) from paged),'[]'::jsonb),
    'summary',(select jsonb_build_object('items',count(*),
      'no_stock',count(*) filter (where stock_status='no_stock'),
      'low_cover',count(*) filter (where stock_status='low_cover'),
      'no_sales',count(*) filter (where stock_status='no_sales'),
      'total_stock',coalesce(sum(total_stock),0)) from filtered),
    'meta',coalesce((select payload->'meta' from public.stock_management_snapshot limit 1),'{}'::jsonb)
      || (select jsonb_build_object('snapshot_at',max(updated_at),'refreshed_at',max(updated_at))
          from public.stock_management_snapshot),
    'categories',coalesce((select jsonb_agg(category order by category) from
      (select distinct category from public.stock_management_snapshot where category<>'') c),'[]'::jsonb),
    'suppliers',coalesce((select jsonb_agg(supplier order by supplier) from
      (select distinct supplier from public.stock_management_snapshot where supplier<>'') c),'[]'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_management_register_batch(p_offset integer DEFAULT 0,p_limit integer DEFAULT 5000)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO '' SET enable_nestloop TO 'off'
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
      order by p.last_mrn_date desc,p.item_code)
      from page p left join receipts r using(item_code)),'[]'::jsonb),
    'total',(select count(*) from public.stock_management_snapshot),
    'snapshot_at',(select max(updated_at) from public.stock_management_snapshot));
$function$;

NOTIFY pgrst,'reload schema';
