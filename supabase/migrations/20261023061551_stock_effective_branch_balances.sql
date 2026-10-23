-- A branch balance includes the final allocation from the latest Daily Order run.
-- Daily Order is authoritative when its row exists; missing rows retain ledger
-- stock. Warehouse stock is always ledger stock and receives no allocation.
-- Normalize identities before deduplication; never sum duplicate branch rows.
create function stock_management_private.effective_stock_balances()
returns table(item_code text,branch_key text,branch text,branch_group text,
  company text,base_qty numeric,final_qty numeric,qty numeric,order_run_date date)
language sql stable security invoker set search_path='' as $balance$
  with active as materialized (
    select public._norm_text(b.branch_name) branch_key,max(b.branch_name) branch,
      max(b.branch_group) branch_group
    from public.branches b where b.is_active is true
      and public._norm_text(b.branch_name) not in
        ('store','main virtual','new virtual','store - expired item','store-ws')
    group by public._norm_text(b.branch_name)
  ), ledger as materialized (
    select btrim(l.item_code) item_code,public._norm_text(l.branch_name) branch_key,
      max(l.company) company,max(coalesce(l.actual_qty,0)) qty
    from public.stk_ledger l where nullif(btrim(l.item_code),'') is not null
    group by btrim(l.item_code),public._norm_text(l.branch_name)
  ), latest_run as materialized (
    select max(d.run_date) run_date from public.daily_order d
  ), orders as materialized (
    select distinct on (btrim(d.item_code),public._norm_text(d.branch))
      btrim(d.item_code) item_code,public._norm_text(d.branch) branch_key,
      d.branch_stock,greatest(coalesce(d.total_final_reorder_today,0),0) final_qty,
      d.run_date
    from public.daily_order d join latest_run r on d.run_date=r.run_date
      join active a on a.branch_key=public._norm_text(d.branch)
    where nullif(btrim(d.item_code),'') is not null
    order by btrim(d.item_code),public._norm_text(d.branch),
      d.created_at desc nulls last,d.branch
  ), balances as (
    select coalesce(l.item_code,o.item_code) item_code,
      coalesce(l.branch_key,o.branch_key) branch_key,
      coalesce(a.branch,'STORE') branch,a.branch_group,l.company,
      case when coalesce(l.branch_key,o.branch_key)='store' then coalesce(l.qty,0)
        else coalesce(o.branch_stock,l.qty,0) end base_qty,
      coalesce(o.final_qty,0) final_qty,(select run_date from latest_run) order_run_date
    from ledger l full join orders o using(item_code,branch_key)
      left join active a on a.branch_key=coalesce(l.branch_key,o.branch_key)
    where a.branch_key is not null or coalesce(l.branch_key,o.branch_key)='store'
  )
  select b.item_code,b.branch_key,b.branch,b.branch_group,b.company,
    b.base_qty,b.final_qty,b.base_qty+b.final_qty,b.order_run_date from balances b;
$balance$;
revoke all on function stock_management_private.effective_stock_balances()
  from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION stock_management_private.refresh_catalog()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET enable_nestloop TO 'off'
AS $function$
declare v_end date; v_start date; v_recent_days integer; v_baseline_days integer; v_meta jsonb; v_count integer;
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_month date := date_trunc('month',v_today)::date;
begin
  if coalesce(current_setting('request.jwt.claims',true)::jsonb->>'role','') <> 'service_role'
     and not (auth.uid() is not null and coalesce(public.item_tracker_my_role(),'')='inventory') then
    raise exception 'Inventory access required' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtext('stock_catalog_refresh'));
  select max(inv_date),greatest(min(inv_date),max(inv_date)-44) into v_end,v_start from public.sales_last_45_days;
  v_recent_days := greatest(least(v_end-v_start+1,3),0);
  v_baseline_days := greatest(v_end-v_start+1-v_recent_days,0);
  v_meta := jsonb_build_object('refreshed_at',now(),
    'catalog_updated_at',(select max(created_at) from public.item_report_apg),
    'catalog_source','item_report_apg',
    'stock_updated_at',(select max(created_at) from public.stk_ledger),
    'demand_from',v_start,'demand_through',v_end,'recent_from',greatest(v_start,v_end-2),
    'baseline_through',v_end-3,'recent_days',v_recent_days,'baseline_days',v_baseline_days,
    'demand_days',v_recent_days+v_baseline_days,
    'sales_2026_through',greatest(
      (select max(to_date(month,'MM/YYYY')) from public.sales_history
       where month ~ '^(0[1-9]|1[0-2])/2026$' and to_date(month,'MM/YYYY')<v_month),
      case when extract(year from v_month)=2026 then v_month end),
    'monthly_sales_through',v_month,'monthly_current_month',v_month,
    'monthly_current_source','sales_last_45_days',
    'monthly_current_from',case when v_end>=v_month then greatest(v_start,v_month) end,
    'monthly_current_through',case when v_end>=v_month then least(v_end,v_today) end,
    'branch_stock_source','daily_order.branch_stock + daily_order.total_final_reorder_today; ledger fallback',
    'order_run_date',(select max(run_date) from public.daily_order),
    'scope','STORE ledger + effective stock of active registered branches. Annual sales include all source branches.',
    'surge_multiple',2,'surge_min_units',3);
  delete from public.stock_catalog_snapshot;
  insert into public.stock_catalog_snapshot(item_code,item_name,category,supplier,total_stock,days_on_hand,sales_2026,demand_surge,payload)
  with latest_catalog as materialized (
    -- Resolve the latest import BEFORE filtering: an older allowed row must not
    -- revive a newer blocked/inactive product. At equal timestamps a disallowed
    -- row wins, so contradictory source records never leak into the register.
    select distinct on (btrim(i.item_code)) i.*
    from public.item_report_apg i
    where nullif(btrim(i.item_code),'') is not null
    order by btrim(i.item_code),i.created_at desc nulls last,
      coalesce(lower(btrim(i.status))='active'
        and lower(btrim(i.is_block))='unchecked'
        and btrim(i.item_status) ~ '^[123](#|[[:space:]]|$)',false),
      (to_jsonb(i)-'all_barcode')::text
  ), catalog as materialized (
    select btrim(i.item_code) item_code,coalesce(i.item_name,'') item_name,
      coalesce(i.category,'') category,coalesce(i.supplier,'') supplier,coalesce(i.company,'') company,
      (to_jsonb(i)-'created_at'-'all_barcode') || jsonb_build_object(
        'added_date_time',(i.added_date_time at time zone 'Asia/Dubai')::date) facts
    from latest_catalog i
    where lower(btrim(i.status))='active'
      and lower(btrim(i.is_block))='unchecked'
      and btrim(i.item_status) ~ '^[123](#|[[:space:]]|$)'
  ), store_receipt_lines as materialized (
    select c.item_code,m.mrn_date,coalesce(m.mrn_no,'') mrn_no,
      sum(coalesce(m.received_quantity,0)) received_qty
    from catalog c join public.mrn_apg_2026 m on btrim(m.item_code)=c.item_code
    where lower(btrim(m.status))='approved'
      and lower(btrim(m.warehouse))='store'
      and m.mrn_date between (c.facts->>'added_date_time')::date
        and (now() at time zone 'Asia/Dubai')::date
    group by c.item_code,m.mrn_date,coalesce(m.mrn_no,'')
    having sum(coalesce(m.received_quantity,0))>0
  ), store_receipt_summary as (
    select item_code,min(mrn_date) first_date,max(mrn_date) last_date,
      sum(received_qty) received_qty
    from store_receipt_lines group by item_code
  ), active as materialized (
    select public._norm_text(branch_name) branch_key,max(branch_name) branch,max(branch_group) branch_group
    from public.branches where is_active is true and public._norm_text(branch_name) not in
      ('store','main virtual','new virtual','store - expired item','store-ws')
    group by public._norm_text(branch_name)
  ), ledger as materialized (
    select l.* from stock_management_private.effective_stock_balances() l
    join catalog c using(item_code)
  ), stock as (
    select l.item_code,coalesce(sum(qty) filter(where l.branch_key='store'),0) store_stock,
      coalesce(sum(qty) filter(where a.branch_key is not null),0) branches_stock,
      coalesce(sum(base_qty) filter(where a.branch_key is not null),0) branches_base_stock,
      coalesce(sum(final_qty) filter(where a.branch_key is not null),0) branches_final_reorder,
      coalesce(sum(qty) filter(where a.branch_group='APG'),0) apg_stock,
      coalesce(sum(qty) filter(where a.branch_group='71'),0) stock_71,
      coalesce(jsonb_object_agg(l.branch_key,jsonb_build_object('stock',qty,'base_stock',base_qty,'final_reorder',final_qty)) filter(where a.branch_key is not null),'{}'::jsonb) branch_stock
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
  ), order_observed as materialized (
    select distinct public._norm_text(d.branch) branch_key
    from public.daily_order d join order_run r on d.run_date=r.run_date
  ), order_expected as materialized (
    -- Include every participating branch, even when its metadata says Online.
    -- Only an Online-only branch absent from this run is outside allocation.
    select a.branch_key from active a where exists (
      select 1 from public.branches b
      where public._norm_text(b.branch_name)=a.branch_key
        and lower(btrim(coalesce(b.branch_type,'')))<>'online'
    ) or exists (select 1 from order_observed o where o.branch_key=a.branch_key)
  ), order_branches as materialized (
    select c.item_code,a.branch_key,
      max(coalesce((s.branch_stock->a.branch_key->>'stock')::numeric,0)) stock,
      max(greatest(coalesce(d.reorder_qty_num,0),0)) reorder_qty,
      max(greatest(coalesce(d.total_final_reorder_today,0),0)) final_qty,
      bool_or(
        upper(btrim(coalesce(d.reason,'')))='NEW ITEM' or coalesce(d.tma_qty,0)>0 or
        (upper(btrim(coalesce(f.formulary,d.branch_formulary,''))) not in ('NON','NON FORMULARY','NON-FORMULARY')
         and upper(btrim(coalesce(d.reorder_qty,''))) not in ('NON','NON FORMULARY','NON-FORMULARY')
         and upper(btrim(coalesce(d.final_reorder_qty_store_stock_gt_0,''))) not in ('NON','NON FORMULARY','NON-FORMULARY'))
      ) eligible
    from order_run r join public.daily_order d on d.run_date=r.run_date
    join catalog c on c.item_code=btrim(d.item_code)
    join active a on a.branch_key=public._norm_text(d.branch)
    join order_expected oe on oe.branch_key=a.branch_key
    left join stock s on s.item_code=c.item_code
    left join formulary_rules f on f.item_code=c.item_code and f.branch_key=a.branch_key
    group by c.item_code,a.branch_key
  ), distribution as (
    select item_code,
      jsonb_build_object(
        'run_date',(select run_date from order_run),
        'as_of',(now() at time zone 'Asia/Dubai')::date,
        'observed',count(*),'active',(select count(*) from order_expected),
        'complete',count(*)=(select count(*) from order_expected),
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
  ), classified_lines as materialized (
    select c.item_code,public._norm_text(s.branch_name) branch_key,s.inv_date,coalesce(s.qty,0) qty,
      case
        when lower(regexp_replace(btrim(coalesce(s.inv_type,'')), '[[:space:]]+', ' ', 'g'))
          in ('insurance','direct insurance','dirict insurance') then
          case lower(regexp_replace(btrim(coalesce(s.customer_name,'')), '[[:space:]]+', ' ', 'g'))
            when 'national health insurance company - daman basic' then 'insurance_basic'
            when 'national health insurance company - daman thiqa' then 'insurance_thiqa'
            else 'other_insurance' end
        when lower(btrim(coalesce(s.sales_type,''))) in ('delivery invoice','return delivery invoice')
          then 'online'
        else 'cash'
      end channel
    from public.sales_last_45_days s join catalog c on c.item_code=btrim(s.item_code)
    where s.inv_date between v_start and v_end or s.inv_date between v_month and v_today
  ), recent_lines as materialized (
    select r.* from classified_lines r join active a using(branch_key)
    where r.inv_date between v_start and v_end
  ), current_branch_totals as (
    select item_code,branch_key,sum(qty) total from classified_lines
    where inv_date between v_month and v_today group by item_code,branch_key
  ), current_branch_sales as (
    select item_code,jsonb_object_agg(branch_key,total) branches
    from current_branch_totals group by item_code
  ), current_month as (
    select c.item_code,v_month month_start,
      coalesce(sum(r.qty) filter(where r.channel='cash'),0) cash,
      coalesce(sum(r.qty) filter(where r.channel in ('insurance_basic','insurance_thiqa','other_insurance')),0) insurance,
      coalesce(sum(r.qty) filter(where r.channel='online'),0) online
    from catalog c left join classified_lines r on r.item_code=c.item_code
      and r.inv_date between v_month and v_today
    group by c.item_code
  ), recent_branch as materialized (
    select item_code,branch_key,
      coalesce(sum(qty) filter(where inv_date>=v_end-2),0) last_3_sales,
      coalesce(sum(qty) filter(where inv_date<v_end-2),0) baseline_sales
    from recent_lines group by item_code,branch_key
  ), daily_mix as (
    select item_code,inv_date,
      coalesce(sum(qty) filter(where channel='cash'),0) cash,
      coalesce(sum(qty) filter(where channel='online'),0) online,
      coalesce(sum(qty) filter(where channel='insurance_basic'),0) insurance_basic,
      coalesce(sum(qty) filter(where channel='insurance_thiqa'),0) insurance_thiqa,
      coalesce(sum(qty) filter(where channel='other_insurance'),0) other_insurance
    from recent_lines group by item_code,inv_date
  ), daily_series as (
    -- Sparse storage; the client fills every missing calendar day with zero.
    select item_code,jsonb_agg(jsonb_build_object(
      'date',inv_date,'cash',cash,'online',online,'insurance_basic',insurance_basic,
      'insurance_thiqa',insurance_thiqa,'other_insurance',other_insurance,
      'total',cash+online+insurance_basic+insurance_thiqa+other_insurance
    ) order by inv_date) days
    from daily_mix group by item_code
  ), demand as (
    select item_code,sum(last_3_sales) last_3_sales,sum(baseline_sales) baseline_sales,
      jsonb_object_agg(branch_key,jsonb_build_object('last_3_sales',last_3_sales,'baseline_sales',baseline_sales,
        'recent_sales',last_3_sales+baseline_sales)) branch_demand
    from recent_branch group by item_code
  ), history_raw as (
    select btrim(h.item_code) item_code,to_date(month,'MM/YYYY') month_start,
      coalesce(cash,0) cash,coalesce(insurance,0) insurance,coalesce(online,0) online
    from public.sales_history_2025 h join catalog c on c.item_code=btrim(h.item_code)
    where month ~ '^(0[1-9]|1[0-2])/2025$' and to_date(month,'MM/YYYY')<v_month
    union all
    select btrim(h.item_code),to_date(month,'MM/YYYY'),coalesce(cash,0),coalesce(insurance,0),coalesce(online,0)
    from public.sales_history h join catalog c on c.item_code=btrim(h.item_code)
    where month ~ '^(0[1-9]|1[0-2])/(20[2-9][0-9])$'
      and to_date(month,'MM/YYYY')>=date '2026-01-01'
      and to_date(month,'MM/YYYY')<v_month
    union all
    select item_code,month_start,cash,insurance,online from current_month
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
      'total',total,'cash',cash,'insurance',insurance,'online',online,
      'source',case when month_start=v_month then 'sales_last_45_days' else 'sales_history' end,
      'through',case when month_start=v_month then case when v_end>=v_month then least(v_end,v_today) end
        else (month_start+interval '1 month'-interval '1 day')::date end) order by month_start) monthly_sales
    from monthly group by item_code
  ), combined as (
    select c.*,jsonb_build_object('checked',true,'first_date',sr.first_date,
      'last_date',sr.last_date,'received_qty',coalesce(sr.received_qty,0),
      'source','mrn_apg_2026','warehouse','STORE') store_receipt,
      coalesce(s.store_stock,0) store_stock,coalesce(s.branches_stock,0) branches_stock,
      coalesce(s.branches_base_stock,0) branches_base_stock,
      coalesce(s.branches_final_reorder,0) branches_final_reorder,
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
    from catalog c left join store_receipt_summary sr using(item_code) left join stock s using(item_code) left join distribution dist using(item_code) left join demand d using(item_code)
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
      'store_stock',store_stock,'branches_stock',branches_stock,
      'branches_base_stock',branches_base_stock,'branches_final_reorder',branches_final_reorder,'apg_stock',apg_stock+store_stock+stock_71,'apg_branches_stock',apg_stock,'stock_71',stock_71,'total_stock',total_stock,
      'store_receipt',store_receipt,'distribution',distribution,'distribution_orders',distribution_orders,
      'branch_stock',branch_stock,'branch_demand',branch_demand,'last_3_sales',last_3_sales,'baseline_sales',baseline_sales,
      'recent_sales',recent_sales,'recent_daily',recent_daily,'baseline_daily',baseline_daily,'daily_sales',daily_sales,
      'days_on_hand',days_on_hand,'stock_status',stock_status,'demand_surge',demand_surge,'new_demand',new_demand,
      'growth_percent',growth_percent,'years',years,'monthly_sales',monthly_sales,
      'daily_sales_45d',coalesce(ds.days,'[]'::jsonb),'daily_sales_45d_available',true,
      'current_month_branch_sales',coalesce(cm.branches,'{}'::jsonb),'meta',v_meta)
  from final left join daily_series ds using(item_code) left join current_branch_sales cm using(item_code);
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'No eligible active APG products; previous snapshot preserved'; end if;
end;
$function$;

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
    or (auth.uid() is not null and coalesce(public.item_tracker_my_role(),'') = 'inventory')
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
    'branch_stock_source','daily_order.branch_stock + daily_order.total_final_reorder_today; ledger fallback',
    'order_run_date',(select max(run_date) from public.daily_order),
    'scope', 'STORE ledger + effective stock of active branches; other warehouses excluded',
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
    select l.*,l.company ledger_company
    from stock_management_private.effective_stock_balances() l join report_items r using(item_code)
  ),
  stock as (
    select l.item_code,
      coalesce(sum(l.qty) filter (where l.branch_key='store'),0) store_stock,
      coalesce(sum(l.qty) filter (where a.branch_key is not null),0) branches_stock,
      coalesce(sum(l.base_qty) filter (where a.branch_key is not null),0) branches_base_stock,
      coalesce(sum(l.final_qty) filter (where a.branch_key is not null),0) branches_final_reorder,
      count(*) filter (where a.branch_key is not null and l.qty>0) stocked_branches,
      coalesce(jsonb_agg(jsonb_build_object('branch',l.branch,'stock',l.qty,'base_stock',l.base_qty,'final_reorder',l.final_qty,
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
  demand as (
    select btrim(s.item_code) item_code,sum(coalesce(s.qty,0)) recent_qty
    from public.sales_last_45_days s join report_items r on r.item_code=btrim(s.item_code)
      join active_branches a on a.branch_key=public._norm_text(s.branch_name)
    where s.inv_date between v_sales_start and v_sales_end
    group by btrim(s.item_code)
  ),
  saved_sales_updated as (
    -- Refresh current stock and analytics, including receipt-only saved products.
    -- Receipt evidence, fingerprints and review records remain untouched.
    update public.stock_expiry_alert_receipts e set product_data =
      coalesce(e.product_data,'{}'::jsonb) || jsonb_build_object(
        'years',coalesce(y.years,'{}'::jsonb),'monthly_sales',coalesce(m.monthly_sales,'[]'::jsonb),
        'branch_year_sales',coalesce(byd.branches,'{}'::jsonb),
        'store_stock',coalesce(s.store_stock,0),'branches_stock',coalesce(s.branches_stock,0),
        'branches_base_stock',coalesce(s.branches_base_stock,0),
        'branches_final_reorder',coalesce(s.branches_final_reorder,0),
        'total_stock',coalesce(s.store_stock,0)+coalesce(s.branches_stock,0),
        'stocked_branches',coalesce(s.stocked_branches,0),
        'recent_sales',coalesce(d.recent_qty,0),
        'daily_sales',greatest(coalesce(d.recent_qty,0),0)/v_days,
        'store_branches_ratio',case when s.branches_stock>0 then coalesce(s.store_stock,0)/s.branches_stock end,
        'days_on_hand',case when coalesce(s.store_stock,0)+coalesce(s.branches_stock,0)<=0 then 0
          when d.recent_qty>0 then (coalesce(s.store_stock,0)+coalesce(s.branches_stock,0))*v_days/d.recent_qty end,
        'stock_status',case when coalesce(s.store_stock,0)+coalesce(s.branches_stock,0)<=0 then 'no_stock'
          when coalesce(d.recent_qty,0)<=0 then 'no_sales'
          when (coalesce(s.store_stock,0)+coalesce(s.branches_stock,0))*v_days/d.recent_qty<30 then 'low_cover'
          else 'in_stock' end,
        'branches',coalesce((select jsonb_agg(
      b.value || jsonb_build_object(
        'sales_2025',coalesce((byd.branches->public._norm_text(b.value->>'branch')->>'2025')::numeric,0),
        'sales_2026',coalesce((byd.branches->public._norm_text(b.value->>'branch')->>'2026')::numeric,0))
      order by coalesce((b.value->>'stock')::numeric,0) desc,b.value->>'branch')
      from jsonb_array_elements(coalesce(s.branches,'[]'::jsonb)) b),'[]'::jsonb),
        'meta',coalesce(e.product_data->'meta','{}'::jsonb)||v_meta)
    from report_items r left join stock s using(item_code) left join demand d using(item_code)
      left join year_data y using(item_code)
      left join month_data m using(item_code) left join branch_year_data byd using(item_code)
    where e.item_code=r.item_code
    returning e.item_code
  ),
  combined as (
    select r.*,coalesce(s.store_stock,0) store_stock,
      coalesce(s.branches_stock,0) branches_stock,
      coalesce(s.branches_base_stock,0) branches_base_stock,
      coalesce(s.branches_final_reorder,0) branches_final_reorder,
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
      'store_stock',store_stock,'branches_stock',branches_stock,
      'branches_base_stock',branches_base_stock,'branches_final_reorder',branches_final_reorder,'total_stock',total_stock,
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

notify pgrst,'reload schema';
