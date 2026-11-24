-- Resumable, bounded initial/import preparation. This is private maintenance,
-- never triggered by opening a page and never writes a source/global table.
alter table zone_overview_private.history_items add column version text not null default '';
update zone_overview_private.history_items set version=coalesce(
  (select version from zone_overview_private.history_state where singleton),'legacy');
alter table zone_overview_private.history_items drop constraint history_items_pkey;
alter table zone_overview_private.history_items add primary key(version,item_code);
alter table zone_overview_private.history_items alter column version drop default;
create table zone_overview_private.history_build (
  singleton boolean primary key check(singleton),version text not null,
  cursor_code text not null default '',processed integer not null default 0,
  total integer not null,started_at timestamptz not null
);
alter table zone_overview_private.history_build enable row level security;
revoke all on zone_overview_private.history_build from public,anon,authenticated,service_role;

create function zone_overview_private.history_version() returns text
language sql stable security definer set search_path='' as $$
  with contexts as materialized (
    select zone_overview_private.scope_for(user_id) value from public.app_users
    where is_active and lower(btrim(role::text))='zone_manager'
  ), branches as (
    select distinct branch->>'key' branch_key from contexts
    cross join lateral jsonb_array_elements(contexts.value->'branches') branch where contexts.value is not null
  ) select md5(
    coalesce((select payload->'meta'->>'monthly_current_month' from public.stock_catalog_snapshot limit 1),'')
    ||coalesce((select string_agg(source||':'||revision::text,',' order by source)
      from public.stock_catalog_cache_revisions where source in ('sales_2025','sales_2026')),'')
    ||coalesce((select md5(string_agg(item_code,',' order by item_code)) from public.stock_catalog_snapshot),'')
    ||coalesce((select md5(string_agg(branch_key,',' order by branch_key)) from branches),''));
$$;
revoke all on function zone_overview_private.history_version() from public,anon,authenticated,service_role;

create function zone_overview_private.seed_history(p_limit integer default 500) returns jsonb
language plpgsql security definer set search_path='' set work_mem='16MB'
set max_parallel_workers_per_gather='0' set jit='off' as $$
declare v_version text; v_month date; v_cursor text; v_codes text[];
  v_total integer; v_processed integer; v_limit integer:=least(greatest(p_limit,1),500);
begin
  if coalesce(current_setting('role',true),'none') not in ('none','postgres','service_role') then
    raise exception 'Maintenance access required' using errcode='42501';
  end if;
  if not pg_try_advisory_xact_lock(hashtext('zone_overview_private.seed_history')) then
    return jsonb_build_object('status','busy');
  end if;
  v_version:=zone_overview_private.history_version();
  if exists(select 1 from zone_overview_private.history_state where singleton and version=v_version) then
    return jsonb_build_object('status','history_ready');
  end if;
  select (payload->'meta'->>'monthly_current_month')::date into v_month
    from public.stock_catalog_snapshot limit 1;
  if v_month is null then raise exception 'Prepared catalog unavailable' using errcode='PT409'; end if;
  select count(*) into v_total from public.stock_catalog_snapshot;
  if not exists(select 1 from zone_overview_private.history_build where singleton and version=v_version) then
    delete from zone_overview_private.history_items where version=v_version;
    insert into zone_overview_private.history_build values(true,v_version,'',0,v_total,clock_timestamp())
      on conflict(singleton) do update set version=excluded.version,cursor_code='',processed=0,
        total=excluded.total,started_at=excluded.started_at;
  end if;
  select cursor_code,processed into v_cursor,v_processed from zone_overview_private.history_build where singleton;
  select array_agg(item_code order by item_code) into v_codes from (
    select item_code from public.stock_catalog_snapshot where item_code>v_cursor order by item_code limit v_limit
  ) codes;
  if coalesce(cardinality(v_codes),0)>0 then
    insert into zone_overview_private.history_items(version,item_code,months)
    with contexts as materialized (
      select zone_overview_private.scope_for(user_id) value from public.app_users
      where is_active and lower(btrim(role::text))='zone_manager'
    ), branches as materialized (
      select distinct branch->>'key' branch_key from contexts
      cross join lateral jsonb_array_elements(contexts.value->'branches') branch where contexts.value is not null
    ), raw as (
      select btrim(h.item_code) item_code,public._norm_text(h.branch_name) branch_key,
        to_date(h.month,'MM/YYYY') month_start,coalesce(h.cash,0) cash,
        coalesce(h.insurance,0) insurance,coalesce(h.online,0) online
      from public.sales_history_2025 h join branches b on b.branch_key=public._norm_text(h.branch_name)
      where btrim(h.item_code)=any(v_codes) and h.month ~ '^(0[1-9]|1[0-2])/2025$'
        and to_date(h.month,'MM/YYYY')<v_month
      union all
      select btrim(h.item_code),public._norm_text(h.branch_name),to_date(h.month,'MM/YYYY'),
        coalesce(h.cash,0),coalesce(h.insurance,0),coalesce(h.online,0)
      from public.sales_history h join branches b on b.branch_key=public._norm_text(h.branch_name)
      where btrim(h.item_code)=any(v_codes) and h.month ~ '^(0[1-9]|1[0-2])/(20[2-9][0-9])$'
        and to_date(h.month,'MM/YYYY')>=date '2026-01-01' and to_date(h.month,'MM/YYYY')<v_month
    ), monthly as (
      select item_code,branch_key,month_start,sum(cash) cash,sum(insurance) insurance,
        sum(online) online,sum(cash+insurance+online) total from raw group by item_code,branch_key,month_start
    ) select v_version,item_code,jsonb_agg(jsonb_build_object('branch_key',branch_key,
      'month_start',month_start,'cash',cash,'insurance',insurance,'online',online,'total',total))
      from monthly group by item_code on conflict(version,item_code) do update set months=excluded.months;
    v_processed:=v_processed+cardinality(v_codes);
    select max(code) into v_cursor from unnest(v_codes) code;
    update zone_overview_private.history_build set cursor_code=v_cursor,processed=v_processed where singleton;
  end if;
  if zone_overview_private.history_version() is distinct from v_version then
    raise exception 'Historical inputs changed; restart next maintenance pass' using errcode='PT409';
  end if;
  if v_processed>=v_total then
    insert into zone_overview_private.history_state values(true,v_version,clock_timestamp())
      on conflict(singleton) do update set version=excluded.version,prepared_at=excluded.prepared_at;
    delete from zone_overview_private.history_items where version<>v_version;
    return jsonb_build_object('status','history_ready','processed',v_processed,'total',v_total);
  end if;
  return jsonb_build_object('status','preparing_history','processed',v_processed,'total',v_total);
end; $$;
revoke all on function zone_overview_private.seed_history(integer) from public,anon,authenticated;
grant execute on function zone_overview_private.seed_history(integer) to service_role;


create or replace function zone_overview_private.prepare() returns jsonb
language plpgsql security definer set search_path='' set enable_nestloop='off'
set work_mem='16MB' set max_parallel_workers_per_gather='0' set jit='off' as $$
declare v_source text; v_meta jsonb; v_start date; v_end date; v_month date;
  v_days integer; v_recent integer; v_baseline integer; v_scope record;
  v_token text; v_now timestamptz:=clock_timestamp(); v_count integer:=0;
  v_mark timestamptz:=clock_timestamp(); v_timings jsonb:='{}';
  v_history_version text;
begin
  if coalesce(current_setting('role',true),'none') not in ('none','postgres','service_role') then
    raise exception 'Maintenance access required' using errcode='42501';
  end if;
  if not pg_try_advisory_xact_lock(hashtext('zone_overview_private.prepare')) then
    return jsonb_build_object('status','busy');
  end if;
  if exists(select 1 from public.stock_catalog_refresh_state where singleton
    and status in ('queued','running')) then
    return jsonb_build_object('status','waiting_for_overview');
  end if;
  v_source:=stock_management_private.catalog_cache_version(true);
  select payload->'meta' into v_meta from public.stock_catalog_snapshot limit 1;
  if v_source is null or v_meta is null then
    raise exception 'Prepared Overview is unavailable' using errcode='PT409';
  end if;
  v_start:=(v_meta->>'demand_from')::date; v_end:=(v_meta->>'demand_through')::date;
  v_month:=(v_meta->>'monthly_current_month')::date;
  v_recent:=(v_meta->>'recent_days')::integer;
  v_baseline:=(v_meta->>'baseline_days')::integer;
  v_days:=v_recent+v_baseline;

  drop table if exists pg_temp.zov_scopes;
  create temporary table zov_scopes on commit drop as
    select distinct s->>'key' scope_key,s->'branches' branches
    from public.app_users u cross join lateral zone_overview_private.scope_for(u.user_id) s
    where u.is_active is true and lower(btrim(u.role::text))='zone_manager' and s is not null;
  if not exists(select 1 from pg_temp.zov_scopes x
    left join zone_overview_private.scopes old using(scope_key)
    where old.source_version is distinct from v_source or old.branches is distinct from x.branches) then
    return jsonb_build_object('status','unchanged');
  end if;
  v_history_version:=zone_overview_private.history_version();
  if not exists(select 1 from zone_overview_private.history_state
    where singleton and version=v_history_version) then
    return zone_overview_private.seed_history(500);
  end if;
  create temporary table zov_catalog on commit drop as
    select s.item_code,s.payload,
      coalesce((select jsonb_object_agg(e.key,e.value) from jsonb_each(s.payload) e
        where e.key=any(array['item_code','item_name','category','supplier','company','unit','brand',
          'is_upp','retail','status','barcode','subunit','is_block','haad_code','unit_type','indication',
          'item_status','tax_percent','product_type','sub_category','concentration','item_priority',
          'subunit_count','insurance_tier','min_order_unit','added_date_time','main_ingredient',
          'pack_size_volume','store_classification','store_receipt','store_stock'])), '{}') facts
    from public.stock_catalog_snapshot s;
  create unique index on pg_temp.zov_catalog(item_code);
  insert into zone_overview_private.products select item_code,facts from pg_temp.zov_catalog
    on conflict(item_code) do update set facts=excluded.facts;
  v_timings:=v_timings||jsonb_build_object('catalog_ms',extract(epoch from clock_timestamp()-v_mark)*1000);
  v_mark:=clock_timestamp();
  create temporary table zov_reference on commit drop as
    with latest as (
      select btrim(m.item_code) item_code,max(m.mrn_date) mrn_date
      from public.mrn_apg_2026 m join pg_temp.zov_catalog c on c.item_code=btrim(m.item_code)
      where lower(btrim(m.status))='approved' and lower(btrim(m.warehouse))='store'
      group by btrim(m.item_code)
    ) select l.item_code,string_agg(distinct nullif(btrim(m.reference),''),' · ') reference,
      sum(coalesce(m.total_qty,0)) total_qty,sum(coalesce(m.bonus,0)) bonus
    from latest l join public.mrn_apg_2026 m on btrim(m.item_code)=l.item_code and m.mrn_date=l.mrn_date
    where lower(btrim(m.status))='approved' and lower(btrim(m.warehouse))='store'
    group by l.item_code;
  create unique index on pg_temp.zov_reference(item_code);
  create temporary table zov_purchase on commit drop as
    select p.item_code,string_agg(distinct nullif(btrim(p.status_name),''),' · ') status_name
    from public.availability_kpi_purchase_status p join pg_temp.zov_catalog c using(item_code)
    group by p.item_code;
  create unique index on pg_temp.zov_purchase(item_code);
  v_timings:=v_timings||jsonb_build_object('reference_ms',extract(epoch from clock_timestamp()-v_mark)*1000);
  v_mark:=clock_timestamp();
  create temporary table zov_branches on commit drop as
    select distinct value->>'key' branch_key,value->>'name' branch,
      value->>'branch_group' branch_group,value->>'branch_type' branch_type
    from pg_temp.zov_scopes cross join lateral jsonb_array_elements(branches);
  create unique index on pg_temp.zov_branches(branch_key);
  create temporary table zov_daily on commit drop as
    select btrim(r.item_code) item_code,public._norm_text(r.branch_name) branch_key,r.inv_date,
      case when lower(regexp_replace(btrim(coalesce(r.inv_type,'')),'[[:space:]]+',' ','g'))
        in ('insurance','direct insurance','dirict insurance') then
          case lower(regexp_replace(btrim(coalesce(r.customer_name,'')),'[[:space:]]+',' ','g'))
            when 'national health insurance company - daman basic' then 'insurance_basic'
            when 'national health insurance company - daman thiqa' then 'insurance_thiqa'
            else 'other_insurance' end
        when lower(btrim(coalesce(r.sales_type,''))) in ('delivery invoice','return delivery invoice')
          then 'online' else 'cash' end channel,sum(coalesce(r.qty,0)) qty
    from public.sales_last_45_days r
    join pg_temp.zov_catalog c on c.item_code=btrim(r.item_code)
    join pg_temp.zov_branches b on b.branch_key=public._norm_text(r.branch_name)
    where r.inv_date between least(v_start,v_month) and v_end
    group by btrim(r.item_code),public._norm_text(r.branch_name),r.inv_date,channel;
  create index on pg_temp.zov_daily(branch_key,item_code);
  v_timings:=v_timings||jsonb_build_object('daily_ms',extract(epoch from clock_timestamp()-v_mark)*1000);
  v_mark:=clock_timestamp();
  create temporary table zov_history on commit drop as
    select h.item_code,r.* from zone_overview_private.history_items h
    cross join lateral jsonb_to_recordset(h.months) as r(
      branch_key text,month_start date,cash numeric,insurance numeric,online numeric,total numeric)
    where h.version=v_history_version;
  create temporary table zov_months on commit drop as
    select item_code,branch_key,month_start,sum(cash) cash,sum(insurance) insurance,
      sum(online) online,sum(total) total from (
      select * from pg_temp.zov_history
      union all
      select item_code,branch_key,v_month,
        case when channel='cash' then qty else 0 end,
        case when channel in ('insurance_basic','insurance_thiqa','other_insurance') then qty else 0 end,
        case when channel='online' then qty else 0 end,qty
      from pg_temp.zov_daily where inv_date>=v_month
    ) all_months group by item_code,branch_key,month_start;
  create index on pg_temp.zov_months(branch_key,item_code);
  v_timings:=v_timings||jsonb_build_object('monthly_ms',extract(epoch from clock_timestamp()-v_mark)*1000);
  v_mark:=clock_timestamp();
  if current_setting('zone_overview.profile_stop',true)='monthly' then
    return jsonb_build_object('status','maintenance_profile','timings_ms',v_timings);
  end if;
  create temporary table zov_annual on commit drop as
    select item_code,branch_key,sum(total) filter(where extract(year from month_start)=2025) y25,
      sum(total) filter(where extract(year from month_start)=2026) y26
    from pg_temp.zov_months group by item_code,branch_key;
  create unique index on pg_temp.zov_annual(item_code,branch_key);
  create temporary table zov_branch_facts on commit drop as
    with stocks as materialized (
      select s.item_code,e.key branch_key,(e.value->>'stock')::numeric stock,
        (e.value->>'base_stock')::numeric base_stock,(e.value->>'final_reorder')::numeric allocated
      from pg_temp.zov_catalog s cross join lateral jsonb_each(coalesce(s.payload->'branch_stock','{}')) e
    ), demand as materialized (
      select s.item_code,e.key branch_key,(e.value->>'recent_sales')::numeric recent_sales,
        (e.value->>'last_3_sales')::numeric last_3_sales,(e.value->>'baseline_sales')::numeric baseline_sales
      from pg_temp.zov_catalog s cross join lateral jsonb_each(coalesce(s.payload->'branch_demand','{}')) e
    ), orders as materialized (
      select s.item_code,e.key branch_key,(e.value->>'eligible')::boolean distribution_eligible,
        (e.value->>'reorder_qty')::numeric reorder_qty,(e.value->>'final_qty')::numeric final_qty
      from pg_temp.zov_catalog s cross join lateral jsonb_each(coalesce(s.payload->'distribution_orders','{}')) e
    ), keys as (select item_code,branch_key from stocks union select item_code,branch_key from demand
      union select item_code,branch_key from orders)
    select k.*,s.stock,s.base_stock,s.allocated,d.recent_sales,d.last_3_sales,d.baseline_sales,
      o.branch_key is not null observed,o.distribution_eligible,o.reorder_qty,o.final_qty
    from keys k left join stocks s using(item_code,branch_key)
      left join demand d using(item_code,branch_key) left join orders o using(item_code,branch_key);
  create unique index on pg_temp.zov_branch_facts(branch_key,item_code);
  analyze pg_temp.zov_branch_facts;
  create temporary table zov_orders on commit drop as
    select distinct branch_key from pg_temp.zov_branch_facts where observed;
  create unique index on pg_temp.zov_orders(branch_key);
  analyze pg_temp.zov_catalog; analyze pg_temp.zov_daily; analyze pg_temp.zov_months;
  analyze pg_temp.zov_annual; analyze pg_temp.zov_branches;
  v_timings:=v_timings||jsonb_build_object('indexes_ms',extract(epoch from clock_timestamp()-v_mark)*1000);
  v_mark:=clock_timestamp();

  for v_scope in select * from pg_temp.zov_scopes loop
    if exists(select 1 from zone_overview_private.scopes s where s.scope_key=v_scope.scope_key
      and s.source_version=v_source and s.branches=v_scope.branches) then continue; end if;
    v_token:=md5(v_source||v_scope.scope_key||v_now::text);
    insert into zone_overview_private.scopes values(v_scope.scope_key,v_scope.branches,v_source,v_token,v_now,
      v_meta||jsonb_build_object('scope_kind','zone','scope','STORE + your assigned branches',
        'scope_token',v_scope.scope_key,'catalog_cache_version',v_token,'reference_version',v_token,
        'source_snapshot_at',v_meta->'refreshed_at','branch_annual_source','prepared_zone',
        'refreshed_at',v_now,'prepared_at',v_now), '{}'::jsonb,'[]'::jsonb,'[]'::jsonb)
    on conflict(scope_key) do update set source_version=excluded.source_version,version=excluded.version,
      prepared_at=excluded.prepared_at,meta=excluded.meta,branches=excluded.branches;
    delete from zone_overview_private.items where scope_key=v_scope.scope_key;
    insert into zone_overview_private.items(scope_key,item_code,header,detail)
    with b as materialized (
      select value->>'key' branch_key,value->>'name' branch,value->>'branch_group' branch_group,
        (lower(coalesce(value->>'branch_type',''))<>'online' or exists
          (select 1 from pg_temp.zov_orders o where o.branch_key=value->>'key')) expected
      from jsonb_array_elements(v_scope.branches)
    ), scoped_facts as materialized (
      select f.* from pg_temp.zov_branch_facts f join b using(branch_key)
    ), bf as materialized (
      select s.item_code,b.*,
        coalesce(f.stock,0) stock,coalesce(f.base_stock,0) base_stock,coalesce(f.allocated,0) allocated,
        coalesce(f.recent_sales,0) recent_sales,coalesce(f.last_3_sales,0) last_3_sales,
        coalesce(f.baseline_sales,0) baseline_sales,coalesce(f.observed,false) observed,
        coalesce(f.distribution_eligible,false) distribution_eligible,
        coalesce(f.reorder_qty,0) reorder_qty,coalesce(f.final_qty,0) final_qty,
        coalesce(y.y25,0) sales_2025,coalesce(y.y26,0) sales_2026
      from pg_temp.zov_catalog s cross join b
      left join scoped_facts f on f.item_code=s.item_code and f.branch_key=b.branch_key
      left join pg_temp.zov_annual y on y.item_code=s.item_code and y.branch_key=b.branch_key
    ), totals as (
      select item_code,sum(stock) branches_stock,sum(base_stock) branches_base_stock,
        sum(allocated) branches_final_reorder,sum(stock) filter(where branch_group='71') stock_71,
        sum(stock) filter(where branch_group='APG') apg_branches_stock,
        sum(recent_sales) recent_sales,sum(last_3_sales) last_3_sales,sum(baseline_sales) baseline_sales,
        jsonb_agg(to_jsonb(bf)-array['item_code','branch_key','expected','observed','allocated','base_stock']
          order by recent_sales desc,branch) branches,
        jsonb_build_object('run_date',v_meta->'order_run_date','as_of',(v_now at time zone 'Asia/Dubai')::date,
          'observed',count(*) filter(where expected and observed),'active',count(*) filter(where expected),
          'complete',count(*) filter(where expected and observed)=count(*) filter(where expected),
          'eligible',count(*) filter(where expected and distribution_eligible),
          'stocked',count(*) filter(where expected and distribution_eligible and stock>0),
          'covered',count(*) filter(where expected and distribution_eligible and stock>0),
          'uncovered',count(*) filter(where expected and distribution_eligible and stock<=0),
          'reorder',count(*) filter(where expected and distribution_eligible and reorder_qty>0),
          'final',count(*) filter(where expected and distribution_eligible and final_qty>0),
          'reorder_qty',coalesce(sum(reorder_qty) filter(where expected and distribution_eligible),0),
          'final_qty',coalesce(sum(final_qty) filter(where expected and distribution_eligible),0)) distribution
      from bf group by item_code
    ), monthly as materialized (
      select m.item_code,m.month_start,sum(cash) cash,sum(insurance) insurance,sum(online) online,sum(total) total
      from pg_temp.zov_months m join b using(branch_key) group by m.item_code,m.month_start
    ), year_totals as (
      select item_code,extract(year from month_start)::integer yr,sum(cash) cash,sum(insurance) insurance,
        sum(online) online,sum(total) total from monthly group by item_code,extract(year from month_start)
    ), best as (
      select distinct on(item_code,extract(year from month_start)) item_code,
        extract(year from month_start)::integer yr,to_char(month_start,'MM/YYYY') best_month,total best_qty
      from monthly where total>0 order by item_code,extract(year from month_start),total desc,month_start
    ), years as (
      select y.item_code,jsonb_object_agg(y.yr::text,jsonb_build_object('cash',cash,'insurance',insurance,
        'online',online,'total',total,'best_month',best_month,'best_qty',best_qty)) years
      from year_totals y left join best using(item_code,yr) group by y.item_code
    ), months as (
      select item_code,jsonb_agg(jsonb_build_object('month',to_char(month_start,'MM/YYYY'),
        'cash',cash,'insurance',insurance,'online',online,'total',total,
        'source',case when month_start=v_month then 'sales_last_45_days' else 'sales_history' end,
        'through',case when month_start=v_month then v_end else (month_start+interval '1 month'-interval '1 day')::date end)
        order by month_start) monthly_sales from monthly group by item_code
    ), daily as (
      select d.item_code,d.inv_date,sum(qty) filter(where channel='cash') cash,
        sum(qty) filter(where channel='online') online,
        sum(qty) filter(where channel='insurance_basic') insurance_basic,
        sum(qty) filter(where channel='insurance_thiqa') insurance_thiqa,
        sum(qty) filter(where channel='other_insurance') other_insurance,sum(qty) total
      from pg_temp.zov_daily d join b using(branch_key) where inv_date between v_start and v_end
      group by d.item_code,d.inv_date
    ), series as (
      select item_code,jsonb_agg(jsonb_build_object('date',inv_date,'cash',coalesce(cash,0),
        'online',coalesce(online,0),'insurance_basic',coalesce(insurance_basic,0),
        'insurance_thiqa',coalesce(insurance_thiqa,0),'other_insurance',coalesce(other_insurance,0),
        'total',total) order by inv_date) days from daily group by item_code
    ), metric as (
      select s.*,t.branches,t.distribution,t.branches_stock,t.branches_base_stock,t.branches_final_reorder,
        coalesce(t.stock_71,0) stock_71,coalesce(t.apg_branches_stock,0) apg_branches_stock,
        coalesce((s.facts->>'store_stock')::numeric,0)+t.branches_stock total_stock,
        t.recent_sales,t.last_3_sales,t.baseline_sales,
        t.recent_sales/nullif(v_days,0) daily_sales,t.last_3_sales/nullif(v_recent,0) recent_daily,
        t.baseline_sales/nullif(v_baseline,0) baseline_daily
      from pg_temp.zov_catalog s join totals t using(item_code)
    ), result as (
      select m.item_code,jsonb_build_object('item_code',m.item_code,
        'store_stock',coalesce((facts->>'store_stock')::numeric,0),'branches_stock',branches_stock,
        'branches_base_stock',branches_base_stock,'branches_final_reorder',branches_final_reorder,
        'total_stock',total_stock,'stock_71',stock_71,'apg_branches_stock',apg_branches_stock,
        'apg_stock',total_stock,'recent_sales',recent_sales,'last_3_sales',last_3_sales,
        'baseline_sales',baseline_sales,'daily_sales',daily_sales,'recent_daily',recent_daily,
        'baseline_daily',baseline_daily,'growth_percent',case when baseline_daily>0 then (recent_daily/baseline_daily-1)*100 end,
        'days_on_hand',case when total_stock<=0 then 0 when daily_sales>0 then total_stock/daily_sales end,
        'stock_status',case when total_stock<=0 then 'no_stock' when coalesce(daily_sales,0)<=0 then 'no_sales'
          when total_stock/daily_sales<30 then 'low_cover' else 'in_stock' end,
        'demand_surge',coalesce(last_3_sales>=3 and baseline_daily>0 and recent_daily>=2*baseline_daily,false),
        'new_demand',coalesce(last_3_sales>=3 and baseline_daily<=0 and v_baseline>0,false),
        'distribution',distribution,'years',coalesce(y.years,'{}'::jsonb),
        'reference',coalesce(ref.reference,''),'total_qty',coalesce(ref.total_qty,0),'bonus',coalesce(ref.bonus,0),
        'received_qty',coalesce(ref.total_qty,0),'received_quantity',coalesce(ref.total_qty,0),
        'last_mrn_qty',coalesce(ref.total_qty,0),'purchase_status_items',coalesce(p.status_name,'Not assigned'),
        'supply_insight',zone_overview_private.store_evidence(si.detail,daily_sales,
          coalesce((facts->>'store_stock')::numeric,0))
      ) header,jsonb_build_object('branches',branches,'monthly_sales',coalesce(mo.monthly_sales,'[]'::jsonb),
        'daily_sales_45d',coalesce(ds.days,'[]'::jsonb),'daily_sales_45d_available',true,
        'meta',(select meta from zone_overview_private.scopes where scope_key=v_scope.scope_key)) detail
      from metric m left join years y using(item_code) left join months mo using(item_code)
      left join series ds using(item_code)
      left join public.stock_supply_insights si using(item_code)
      left join pg_temp.zov_reference ref using(item_code)
      left join pg_temp.zov_purchase p using(item_code)
    ) select v_scope.scope_key,item_code,header-array['supply_insight']||jsonb_build_object(
      'supply_insight',(header->'supply_insight')-array['events','chart_timeline']),
      detail||jsonb_build_object('supply_insight',header->'supply_insight') from result;
    get diagnostics v_count=row_count;
    if v_count<>(select count(*) from pg_temp.zov_catalog) then
      raise exception 'Incomplete zonal snapshot; previous results preserved' using errcode='PT409';
    end if;
    update zone_overview_private.scopes s set summary=q.summary,categories=q.categories,suppliers=q.suppliers
    from (
      select jsonb_build_object('items',count(*),'total_stock',sum((header->>'total_stock')::numeric),
        'surge',count(*) filter(where (header->>'demand_surge')::boolean or (header->>'new_demand')::boolean),
        'shortage',count(*) filter(where (header->>'recent_sales')::numeric>(header->>'total_stock')::numeric),
        'low_cover',count(*) filter(where header->>'stock_status'='low_cover')) summary,
        coalesce(jsonb_agg(distinct p.facts->'category') filter(where coalesce(p.facts->>'category','')<>''),'[]') categories,
        coalesce(jsonb_agg(distinct p.facts->'supplier') filter(where coalesce(p.facts->>'supplier','')<>''),'[]') suppliers
      from zone_overview_private.items i join zone_overview_private.products p using(item_code)
      where i.scope_key=v_scope.scope_key
    ) q where s.scope_key=v_scope.scope_key;
  end loop;
  v_timings:=v_timings||jsonb_build_object('scopes_ms',extract(epoch from clock_timestamp()-v_mark)*1000);
  if stock_management_private.catalog_cache_version(true) is distinct from v_source then
    raise exception 'Source changed during zonal preparation; retry next run' using errcode='PT409';
  end if;
  delete from zone_overview_private.scopes where scope_key not in(select scope_key from pg_temp.zov_scopes);
  delete from zone_overview_private.products where item_code not in(select item_code from pg_temp.zov_catalog);
  return jsonb_build_object('status','complete','prepared_at',v_now,'last_scope_items',v_count,'timings_ms',v_timings);
end; $$;





create function zone_overview_private.work() returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_start timestamptz:=clock_timestamp(); result jsonb;
begin
  if coalesce(current_setting('role',true),'none') not in ('none','postgres','service_role') then
    raise exception 'Maintenance access required' using errcode='42501';
  end if;
  loop
    result:=zone_overview_private.prepare();
    if result->>'status' not in ('preparing_history','history_ready') then return result; end if;
    if clock_timestamp()-v_start>interval '6 seconds' then return result; end if;
  end loop;
end; $$;
revoke all on function zone_overview_private.work() from public,anon,authenticated;
grant execute on function zone_overview_private.work() to service_role;
