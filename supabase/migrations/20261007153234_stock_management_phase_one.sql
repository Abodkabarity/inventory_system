-- One atomic, permissioned snapshot keeps million-row sales aggregates off
-- the browser and lets the product table paginate over ~10k MRN items.
create schema if not exists stock_management_private;
revoke all on schema stock_management_private from public, anon;
grant usage on schema stock_management_private to authenticated, service_role;

create table public.stock_management_snapshot (
  item_code text primary key,
  item_name text not null,
  category text not null,
  supplier text not null,
  company text not null,
  last_mrn_date date not null,
  total_stock numeric not null,
  days_on_hand numeric,
  stock_status text not null,
  sales_2026 numeric not null,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);
create index stock_management_snapshot_last_mrn_idx
  on public.stock_management_snapshot (last_mrn_date desc, item_code);
alter table public.stock_management_snapshot enable row level security;
revoke all on public.stock_management_snapshot from anon, authenticated;
grant select on public.stock_management_snapshot to authenticated;
grant all on public.stock_management_snapshot to service_role;
create policy stock_management_inventory_read on public.stock_management_snapshot
  for select to authenticated
  using ((select public.item_tracker_my_role()) = 'inventory');

create or replace function stock_management_private.refresh_snapshot()
returns jsonb language plpgsql security definer
set search_path = ''
set statement_timeout = '120s'
as $$
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
  delete from public.stock_management_snapshot;
  insert into public.stock_management_snapshot
    (item_code,item_name,category,supplier,company,last_mrn_date,total_stock,
     days_on_hand,stock_status,sales_2026,payload)
  with
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
      'last_mrn_date',mrn_date,'last_mrn_no',mrn_no,'last_mrn_qty',last_mrn_qty,
      'store_stock',store_stock,'branches_stock',branches_stock,'total_stock',total_stock,
      'store_branches_ratio',case when branches_stock>0 then store_stock/branches_stock end,
      'stocked_branches',stocked_branches,'branches',branches,'recent_sales',recent_qty,
      'daily_sales',daily_sales,'days_on_hand',days_on_hand,'stock_status',stock_status,
      'years',years,'monthly_sales',monthly_sales,'meta',v_meta
    )
  from final;
  get diagnostics v_count = row_count;
  if v_count=0 then raise exception 'No MRN products found; the existing snapshot was preserved.'; end if;
  return v_meta || jsonb_build_object('items',v_count);
end;
$$;
revoke all on function stock_management_private.refresh_snapshot() from public, anon;
grant execute on function stock_management_private.refresh_snapshot() to authenticated, service_role;

create function public.refresh_stock_management_snapshot()
returns jsonb language sql security invoker set search_path = ''
as $$ select stock_management_private.refresh_snapshot(); $$;
revoke all on function public.refresh_stock_management_snapshot() from public, anon;
grant execute on function public.refresh_stock_management_snapshot() to authenticated, service_role;

create function public.get_stock_management_page(
  p_search text default '',p_status text default '',p_category text default '',
  p_supplier text default '',p_received_from date default null,p_received_to date default null,
  p_sort text default 'latest_mrn',p_offset integer default 0,p_limit integer default 50
)
returns jsonb language sql stable security invoker set search_path = ''
as $$
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
    limit least(greatest(p_limit,1),100) offset greatest(p_offset,0)
  )
  select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(payload - 'branches' - 'monthly_sales' - 'meta') from paged),'[]'::jsonb),
    'summary',(select jsonb_build_object('items',count(*),
      'no_stock',count(*) filter (where stock_status='no_stock'),
      'low_cover',count(*) filter (where stock_status='low_cover'),
      'no_sales',count(*) filter (where stock_status='no_sales'),
      'total_stock',coalesce(sum(total_stock),0)) from filtered),
    'meta',(select payload->'meta' from public.stock_management_snapshot limit 1),
    'categories',coalesce((select jsonb_agg(category order by category) from
      (select distinct category from public.stock_management_snapshot where category<>'') c),'[]'::jsonb),
    'suppliers',coalesce((select jsonb_agg(supplier order by supplier) from
      (select distinct supplier from public.stock_management_snapshot where supplier<>'') c),'[]'::jsonb)
  );
$$;
revoke all on function public.get_stock_management_page(text,text,text,text,date,date,text,integer,integer) from public, anon;
grant execute on function public.get_stock_management_page(text,text,text,text,date,date,text,integer,integer) to authenticated, service_role;

create function public.get_stock_management_item(p_item_code text)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select payload from public.stock_management_snapshot where item_code=p_item_code; $$;
revoke all on function public.get_stock_management_item(text) from public, anon;
grant execute on function public.get_stock_management_item(text) to authenticated, service_role;
