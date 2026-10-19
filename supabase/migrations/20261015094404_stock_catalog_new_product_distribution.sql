-- Distribution facts reuse the current Daily Order run and authoritative active branches.
-- Keep raw branch identities. Only compact counts travel with the register.
select pg_advisory_xact_lock(hashtext('stock_catalog_refresh'));

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
  ), order_run as materialized (
    select max(run_date) run_date from public.daily_order
  ), formulary_rules as materialized (
    select distinct on (btrim(item_code),public._norm_text(branch_name))
      btrim(item_code) item_code,public._norm_text(branch_name) branch_key,
      upper(btrim(revised_branch_formulary)) formulary
    from public.branch_formulary
    where revised_date <= (now() at time zone 'Asia/Dubai')::date
    order by btrim(item_code),public._norm_text(branch_name),revised_date desc,created_at desc,id desc
  ), order_branches as materialized (
    select c.item_code,a.branch_key,
      max(coalesce((s.branch_stock->a.branch_key->>'stock')::numeric,0)) stock,
      max(greatest(coalesce(d.total_reorder_today,0),0)) reorder_qty,
      max(greatest(coalesce(d.total_final_reorder_today,0),0)) final_qty,
      bool_or(
        upper(btrim(coalesce(d.reason,'')))='NEW ITEM' or coalesce(d.tma_qty,0)>0 or
        (upper(btrim(coalesce(f.formulary,d.branch_formulary,''))) not in ('NON','NON FORMULARY','NON-FORMULARY')
         and upper(btrim(coalesce(d.reorder_qty,''))) not in ('NON','NON FORMULARY','NON-FORMULARY')
         and upper(btrim(coalesce(d.final_reorder_qty_store_stock_gt_0,''))) not in ('NON','NON FORMULARY','NON-FORMULARY'))
      ) eligible
    from order_run r join public.daily_order d on d.run_date=r.run_date
    join catalog c on c.item_code=d.item_code
    join active a on a.branch_key=public._norm_text(d.branch)
    left join stock s on s.item_code=c.item_code
    left join formulary_rules f on f.item_code=c.item_code and f.branch_key=a.branch_key
    group by c.item_code,a.branch_key
  ), distribution as (
    select item_code,
      jsonb_build_object(
        'run_date',(select run_date from order_run),
        'as_of',(now() at time zone 'Asia/Dubai')::date,
        'observed',count(*),'active',(select count(*) from active),
        'complete',count(*)=(select count(*) from active),
        'eligible',count(*) filter(where eligible),
        'stocked',count(*) filter(where eligible and stock>0),
        'reorder',count(*) filter(where eligible and reorder_qty>0),
        'final',count(*) filter(where eligible and final_qty>0),
        'covered',count(*) filter(where eligible and (stock>0 or final_qty>0)),
        'uncovered',count(*) filter(where eligible and stock<=0 and final_qty<=0),
        'reorder_qty',coalesce(sum(reorder_qty) filter(where eligible),0),
        'final_qty',coalesce(sum(final_qty) filter(where eligible),0)
      ) distribution,
      jsonb_object_agg(branch_key,jsonb_build_object('eligible',eligible,
        'reorder_qty',reorder_qty,'final_qty',final_qty)) distribution_orders
    from order_branches group by item_code
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
      coalesce(s.branch_stock,'{}'::jsonb) branch_stock,
      coalesce(dist.distribution,'{}'::jsonb) distribution,coalesce(dist.distribution_orders,'{}'::jsonb) distribution_orders,coalesce(d.branch_demand,'{}'::jsonb) branch_demand,
      coalesce(d.last_3_sales,0) last_3_sales,coalesce(d.baseline_sales,0) baseline_sales,
      coalesce(d.last_3_sales,0)+coalesce(d.baseline_sales,0) recent_sales,
      coalesce(d.last_3_sales,0)/nullif(v_recent_days,0) recent_daily,
      coalesce(d.baseline_sales,0)/nullif(v_baseline_days,0) baseline_daily,
      (coalesce(d.last_3_sales,0)+coalesce(d.baseline_sales,0))/nullif(v_recent_days+v_baseline_days,0) daily_sales,
      coalesce(y.years,'{}'::jsonb) years,coalesce(m.monthly_sales,'[]'::jsonb) monthly_sales
    from catalog c left join stock s using(item_code) left join distribution dist using(item_code) left join demand d using(item_code)
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
      'distribution',distribution,'distribution_orders',distribution_orders,
      'branch_stock',branch_stock,'branch_demand',branch_demand,'last_3_sales',last_3_sales,'baseline_sales',baseline_sales,
      'recent_sales',recent_sales,'recent_daily',recent_daily,'baseline_daily',baseline_daily,'daily_sales',daily_sales,
      'days_on_hand',days_on_hand,'stock_status',stock_status,'demand_surge',demand_surge,'new_demand',new_demand,
      'growth_percent',growth_percent,'years',years,'monthly_sales',monthly_sales,'meta',v_meta)
  from final;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Item Report is empty; previous snapshot preserved'; end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_catalog_item(p_item_code text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with snapshot as materialized (select payload from public.stock_catalog_snapshot where item_code=p_item_code),
  annual as (
    select public._norm_text(branch_name) branch_key,2025 yr,sum(coalesce(cash,0)+coalesce(insurance,0)+coalesce(online,0)) total
    from public.sales_history_2025 where btrim(item_code)=p_item_code and month ~ '^(0[1-9]|1[0-2])/2025$' group by public._norm_text(branch_name)
    union all
    select public._norm_text(branch_name),2026,sum(coalesce(cash,0)+coalesce(insurance,0)+coalesce(online,0))
    from public.sales_history where btrim(item_code)=p_item_code and month ~ '^(0[1-9]|1[0-2])/2026$' group by public._norm_text(branch_name)
  ), branches as (
    select b.branch_name branch,b.branch_group,
      (s.payload->'distribution_orders'->public._norm_text(b.branch_name)->>'eligible')::boolean distribution_eligible,
      (s.payload->'distribution_orders'->public._norm_text(b.branch_name)->>'reorder_qty')::numeric reorder_qty,
      (s.payload->'distribution_orders'->public._norm_text(b.branch_name)->>'final_qty')::numeric final_qty,
      coalesce((s.payload->'branch_stock'->public._norm_text(b.branch_name)->>'stock')::numeric,0) stock,
      coalesce((s.payload->'branch_demand'->public._norm_text(b.branch_name)->>'recent_sales')::numeric,0) recent_sales,
      coalesce((s.payload->'branch_demand'->public._norm_text(b.branch_name)->>'last_3_sales')::numeric,0) last_3_sales,
      coalesce((s.payload->'branch_demand'->public._norm_text(b.branch_name)->>'baseline_sales')::numeric,0) baseline_sales,
      coalesce((select total from annual where branch_key=public._norm_text(b.branch_name) and yr=2025),0) sales_2025,
      coalesce((select total from annual where branch_key=public._norm_text(b.branch_name) and yr=2026),0) sales_2026
    from public.branches b cross join snapshot s where b.is_active is true and public._norm_text(b.branch_name) not in
      ('store','main virtual','new virtual','store - expired item','store-ws')
  ) select payload-'branch_stock'-'branch_demand'-'distribution_orders' || jsonb_build_object('branches',
    coalesce((select jsonb_agg(to_jsonb(b) order by recent_sales desc,branch) from branches b),'[]'::jsonb)) from snapshot;
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_catalog_page(p_search text DEFAULT ''::text, p_signal text DEFAULT ''::text, p_category text DEFAULT ''::text, p_supplier text DEFAULT ''::text, p_sort text DEFAULT 'name'::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with filtered as materialized (
    select * from public.stock_catalog_snapshot s where
      (coalesce(p_search,'')='' or strpos(lower(s.item_code||' '||s.item_name||' '||s.supplier||' '||coalesce(s.payload->>'company','')),lower(btrim(p_search)))>0)
      and (coalesce(p_category,'')='' or s.category=p_category) and (coalesce(p_supplier,'')='' or s.supplier=p_supplier)
      and (coalesce(p_signal,'')='' or
        (p_signal='surge' and (demand_surge or (payload->>'new_demand')::boolean)) or
        (p_signal='shortage' and (payload->>'recent_sales')::numeric>total_stock) or
        (p_signal='low_cover' and payload->>'stock_status'='low_cover') or
        (p_signal='no_stock' and total_stock<=0) or (p_signal='no_sales' and payload->>'stock_status'='no_sales'))
  ), page as (
    select * from filtered order by
      case when p_sort='stock' then total_stock end desc nulls last,
      case when p_sort='sales' then sales_2026 end desc nulls last,
      case when p_sort='cover' then days_on_hand end asc nulls last,
      case when p_sort='growth' then (payload->>'growth_percent')::numeric end desc nulls last,
      item_name,item_code limit least(greatest(p_limit,1),100) offset greatest(p_offset,0)
  ) select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(payload-'distribution_orders'-'branch_stock'-'branch_demand'-'monthly_sales'-'meta') from page),'[]'::jsonb),
    'summary',(select jsonb_build_object('items',count(*),'surge',count(*) filter(where demand_surge or (payload->>'new_demand')::boolean),
      'shortage',count(*) filter(where (payload->>'recent_sales')::numeric>total_stock),
      'low_cover',count(*) filter(where payload->>'stock_status'='low_cover'),
      'no_stock',count(*) filter(where total_stock<=0),'total_stock',coalesce(sum(total_stock),0)) from filtered),
    'meta',(select payload->'meta' from public.stock_catalog_snapshot limit 1),
    'categories',coalesce((select jsonb_agg(category order by category) from (select distinct category from public.stock_catalog_snapshot where category<>'') c),'[]'::jsonb),
    'suppliers',coalesce((select jsonb_agg(supplier order by supplier) from (select distinct supplier from public.stock_catalog_snapshot where supplier<>'') c),'[]'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_stock_catalog_register_batch(p_offset integer DEFAULT 0, p_limit integer DEFAULT 4000)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(payload-'distribution_orders'-'branch_stock'-'branch_demand'-'monthly_sales'-'meta' order by item_code)
      from (select item_code,payload from public.stock_catalog_snapshot order by item_code
        limit least(greatest(p_limit,1),4000) offset greatest(p_offset,0)) p),'[]'::jsonb),
    'total',(select count(*) from public.stock_catalog_snapshot),
    'snapshot_at',coalesce((select payload->'meta'->>'refreshed_at' from public.stock_catalog_snapshot limit 1),'')
  );
$function$;
