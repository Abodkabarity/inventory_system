-- LOCAL FEATURE BACKEND ONLY. No existing sources, Overview caches or jobs change.
-- New isolated cache for the user's explicitly requested precomputed local page.
create schema if not exists online_overview_private;
revoke all on schema online_overview_private from public, anon;
grant usage on schema online_overview_private to authenticated;

create table if not exists online_overview_private.state (
 singleton boolean primary key default true check(singleton),
 status text not null default 'empty', generation text, requested_at timestamptz,
 completed_at timestamptz, error text, meta jsonb not null default '{}'
);
insert into online_overview_private.state(singleton) values(true) on conflict do nothing;
create table if not exists online_overview_private.items (
 generation text not null, item_code text not null, payload jsonb not null,
 primary key(generation,item_code)
);
create table if not exists online_overview_private.results (
 generation text not null, branch text not null, scope text not null,
 item_code text not null, ordinal integer not null, payload jsonb not null,
 primary key(generation,branch,scope,item_code)
);
create index if not exists online_overview_result_page_idx on
 online_overview_private.results(generation,branch,scope,ordinal);
alter table online_overview_private.state enable row level security;
alter table online_overview_private.items enable row level security;
alter table online_overview_private.results enable row level security;
revoke all on all tables in schema online_overview_private from public,anon,authenticated;

create or replace function online_overview_private.assert_access()
returns void language plpgsql stable security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')='service_role' or
    (coalesce(current_setting('request.jwt.claims',true),'')='' and session_user in ('postgres','service_role')) then
  return;
 end if;
 if auth.uid() is distinct from '94c7aa76-bc23-40e4-8c9a-f2cb9636c821'::uuid
    or coalesce(auth.role(),'')<>'authenticated'
    or not exists(select 1 from public.app_users u where u.user_id=auth.uid()
      and lower(btrim(u.role::text))='inventory' and u.is_active is true)
 then raise insufficient_privilege using message='Online Overview is not available for this account';end if;
end $$;
revoke all on function online_overview_private.assert_access() from public,anon,service_role;
grant execute on function online_overview_private.assert_access() to authenticated;

create or replace function online_overview_private.source_version()
returns text language sql stable security definer set search_path='' as $$
 select md5(jsonb_build_array(
   (select max(updated_at) from public.stock_catalog_snapshot),
   stock_management_private.reference_version(),
   (select md5(coalesce(jsonb_agg(to_jsonb(e) order by branch_name)::text,'')) from online_overview_private.branch_exclusions e),
   (select md5(coalesce(jsonb_agg(artifact order by id)::text,'')) from online_overview_private.models),
   (select jsonb_build_array(count(*),max(created_at)) from public.sales_history),
   (select jsonb_build_array(count(*),max(created_at)) from public.sales_history_2025),
   (select max(created_at) from public.stk_ledger),
   (select max(updated_at) from public.stk_statement_history_load_progress),
   (select max(created_at) from public.stk_statement),
   (select md5(coalesce(jsonb_agg(to_jsonb(b) order by branch_name)::text,'')) from public.branches b),
   (select jsonb_agg(jsonb_build_array(item_code,first_mrn) order by item_code) from (
    select btrim(item_code) item_code,min(mrn_date) first_mrn from public.mrn_apg_2026
    where lower(btrim(status))='approved' and coalesce(total_qty,received_quantity,0)>0
      and mrn_date<=(now() at time zone 'Asia/Dubai')::date group by btrim(item_code)) m),
   (now() at time zone 'Asia/Dubai')::date,
   'other-branch-stock-v1-n-store-v1'
 )::text)
$$;

create or replace function online_overview_private.display_item(p jsonb)
returns jsonb language sql immutable security invoker set search_path='' as $$
 select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(p)
 where key=any(array['item_code','item_name','item_status','purchase_status_items',
  'retail','store_stock','other_branch_stock','stock_unavailable','sales_orientation','added_date_time','supplier','category',
  'company','main_ingredient','sub_category','indication']::text[])
$$;

-- A saved generation must not expose a branch whose online access was removed.
create or replace function online_overview_private.roster_is_allowed(p_meta jsonb)
returns boolean language sql stable security invoker set search_path='' as $$
 select not exists (
  select 1 from jsonb_array_elements(p_meta->'branches') b
  where not exists (
   select 1 from online_overview_private.operational_branches() o
   where o.branch_name=b->>'name' and coalesce(o.branch_group,'APG')=b->>'group'
  )
 )
$$;

create or replace function online_overview_private.build()
returns void language plpgsql security definer set search_path='' set enable_nestloop='off' as $$
declare token text:=md5(clock_timestamp()::text||random()::text); version text;
 today date:=(now() at time zone 'Asia/Dubai')::date; stock_day date; through_day date;
 last_month date; completed_end date; roster jsonb; item_count integer; record_count integer; forecast_meta jsonb;
begin
 perform pg_advisory_xact_lock(hashtext('local_online_overview_build'));
 version:=online_overview_private.source_version();
 drop table if exists pg_temp.oo_branches,pg_temp.oo_catalog,pg_temp.oo_monthly,
   pg_temp.oo_pairs,pg_temp.oo_movement,pg_temp.oo_evidence,pg_temp.oo_demand,pg_temp.oo_scored;
 create temp table oo_branches on commit drop as
 select branch_name branch,public._norm_text(branch_name) branch_key,
   coalesce(branch_group,'APG') branch_group,
   case when branch_group='71' then '71 Pharmacy L.L.C.' else 'APG' end company
 from online_overview_private.operational_branches();
 if not exists(select 1 from pg_temp.oo_branches) or exists(
   select branch_key from pg_temp.oo_branches group by branch_key having count(*)>1)
 then raise exception 'Online branch metadata is missing or ambiguous'; end if;
 if exists(select 1 from online_overview_private.models where id='abcmt-online-v2'
   and artifact->'operational_branches' is distinct from
       (select jsonb_agg(branch order by branch collate "C") from pg_temp.oo_branches))
 then raise exception 'Local model operational roster changed. Retrain before rebuilding.'; end if;
 if exists(select 1 from online_overview_private.models where id='abcmt-online-v2'
   and artifact->>'a_quantity_rule' is distinct from 'quantity_without_spread_gate')
 then raise exception 'Local model quantity rule changed. Retrain before rebuilding.'; end if;
 select jsonb_agg(jsonb_build_object('name',branch,'group',branch_group) order by branch)
 into roster from pg_temp.oo_branches;
 select (max(created_at) at time zone 'Asia/Dubai')::date into stock_day from public.stk_ledger;
 create temp table oo_catalog on commit drop as
 with purchase as (
  select btrim(item_code) item_code,string_agg(distinct nullif(btrim(status_name),''),' · '
    order by nullif(btrim(status_name),'')) status_name
  from public.availability_kpi_purchase_status group by btrim(item_code)
 ) select c.item_code,(c.payload-array['branches','branch_stock','branch_demand','monthly_sales',
   'daily_sales_45d','distribution_orders','current_month_branch_sales']::text[]) ||
   jsonb_build_object('purchase_status_items',coalesce(p.status_name,'Not assigned'),
    'other_branch_stock',coalesce(o.qty,0),
    'sales_orientation',coalesce(nullif(btrim(c.payload->>'sales_orientation'),''),btrim(c.payload->>'item_priority'))) item,
   greatest(coalesce(nullif(c.payload->>'retail','')::numeric,0),0) retail
 from public.stock_catalog_snapshot c left join purchase p using(item_code)
 left join online_overview_private.other_branch_stock(stock_day) o using(item_code)
 where c.payload->>'item_status' ~* '^\s*(1\s*#\s*)?normal\s+purchase\s*$';
 create unique index on pg_temp.oo_catalog(item_code);
 select count(*) into item_count from pg_temp.oo_catalog;
 if item_count=0 then raise exception 'Eligible catalog is empty; previous result retained'; end if;

 -- Monthly source rows are facts to aggregate, not unique register identities.
 create temp table oo_monthly on commit drop as
 select branch,item_code,month_start,sum(online) online,sum(total) total from (
  select b.branch,c.item_code,to_date(h.month,'MM/YYYY') month_start,
    coalesce(h.online,0) online,coalesce(h.online,0)+coalesce(h.cash,0)+coalesce(h.insurance,0) total
  from public.sales_history_2025 h join pg_temp.oo_branches b on h.branch_name=b.branch
    join pg_temp.oo_catalog c on btrim(h.item_code)=c.item_code
  where h.month ~ '^(0[1-9]|1[0-2])/2025$'
  union all
  select b.branch,c.item_code,to_date(h.month,'MM/YYYY'),
    coalesce(h.online,0),coalesce(h.online,0)+coalesce(h.cash,0)+coalesce(h.insurance,0)
  from public.sales_history h join pg_temp.oo_branches b on h.branch_name=b.branch
    join pg_temp.oo_catalog c on btrim(h.item_code)=c.item_code
  where h.month ~ '^(0[1-9]|1[0-2])/2026$' and to_date(h.month,'MM/YYYY')<=today
 ) s group by branch,item_code,month_start;
 create index on pg_temp.oo_monthly(item_code,month_start,branch);
 analyze pg_temp.oo_monthly;
 analyze pg_temp.oo_catalog;
 select max(month_start) filter(where extract(year from month_start)=2026) into last_month from pg_temp.oo_monthly;
 completed_end:=least(date_trunc('month',today)::date,(last_month+interval '1 month')::date);
 through_day:=least(stock_day,today-1,coalesce((last_month+interval '1 month -1 day')::date,date '2026-01-01'));

 -- Reconstruct only authoritative online branches. Missing/contradictory data
 -- stays unknown. No final allocations are treated as physical stock.
 create temp table oo_pairs on commit drop as
 with progress as (
  select company,min(from_date) first_day,max(to_date) last_day,
    bool_and(complete and committed_rows=expected_rows) and
      sum(to_date-from_date+1)=max(to_date)-min(from_date)+1 complete
  from public.stk_statement_history_load_progress group by company
 ), current_stock as (
  select b.branch,btrim(l.item_code) item_code,count(*) n,
    bool_and(l.actual_qty is not null and (l.created_at at time zone 'Asia/Dubai')::date=stock_day
      and (l.company=b.company or (b.company='APG' and l.company='Al Ain Pharmacy Group (APG)'))) valid,
    sum(l.actual_qty) qty from public.stk_ledger l join pg_temp.oo_branches b
    on l.branch_name=b.branch
  group by b.branch,btrim(l.item_code)
 ), openings as (
  select b.branch,btrim(o.item_code) item_code,count(*) n,
    bool_and(o.report_from_date=o.stock_date and o.report_to_date=o.stock_date
      and not o.source_branch_missing and o.actual_qty is not null and
      (o.company=b.company or (b.company='APG' and o.company='Al Ain Pharmacy Group (APG)'))) valid,
    sum(o.actual_qty) qty from public.stk_ledger_history o join pg_temp.oo_branches b
    on o.branch_name=b.branch where o.stock_date='2026-01-01' group by b.branch,btrim(o.item_code)
 ), reports as (
  select b.*,
   exists(select 1 from public.stk_ledger l where l.branch_name=b.branch
     and (l.created_at at time zone 'Asia/Dubai')::date=stock_day
     and (l.company=b.company or (b.company='APG' and l.company='Al Ain Pharmacy Group (APG)'))) current_report,
   exists(select 1 from public.stk_ledger_history o where o.branch_name=b.branch and o.stock_date='2026-01-01'
     and o.report_from_date=o.stock_date and o.report_to_date=o.stock_date and not o.source_branch_missing
     and (o.company=b.company or (b.company='APG' and o.company='Al Ain Pharmacy Group (APG)'))) opening_report,
   (select min(trans_date) from public.stk_statement r where r.branch_name=b.branch and coalesce(r.company,'APG')=b.company) rolling_first,
   (select max(trans_date) from public.stk_statement r where r.branch_name=b.branch and coalesce(r.company,'APG')=b.company) rolling_last
  from pg_temp.oo_branches b
 ) select b.branch,b.branch_key,b.company,c.item_code,p.last_day archive_through,
   case when l.n=1 and l.valid then l.qty when l.n is null and b.current_report then 0 end current_qty,
   case when o.n=1 and o.valid then o.qty when o.n is null and b.opening_report then 0 end opening_qty,
   (o.n is null or l.n is null) estimated,
   coalesce(p.complete and p.first_day='2026-01-01' and
     (p.last_day>=stock_day or (b.rolling_first<=p.last_day+1 and b.rolling_last>=stock_day)),false) covered
 from pg_temp.oo_catalog c cross join reports b left join progress p on p.company=b.company
 left join current_stock l on l.branch=b.branch and l.item_code=c.item_code
 left join openings o on o.branch=b.branch and o.item_code=c.item_code;
 create unique index on pg_temp.oo_pairs(branch,item_code);
 create temp table oo_movement on commit drop as
 select branch,item_code,movement_day,sum(net) net,sum(incoming) incoming,sum(outgoing) outgoing,
   bool_or(bad) bad,bool_or(adjustment) adjustment from (
  select p.branch,p.item_code,h.trans_date movement_day,sum(h.qty) net,sum(greatest(h.qty,0)) incoming,
    sum(-least(h.qty,0)) outgoing,bool_or(h.qty is null or (upper(h.mode)='IN' and h.qty<0)
      or (upper(h.mode)='OUT' and h.qty>0)) bad,bool_or(h.trans_type ilike '%adjust%') adjustment
  from public.stk_statement_history_2026 h join pg_temp.oo_pairs p on h.branch_name=p.branch
    and h.item_code=p.item_code and h.company=p.company
  where h.trans_date>'2026-01-01' and h.trans_date<=least(p.archive_through,stock_day)
  group by p.branch,p.item_code,h.trans_date
  union all
  select p.branch,p.item_code,h.trans_date,sum(h.qty),sum(greatest(h.qty,0)),sum(-least(h.qty,0)),
    bool_or(h.qty is null or (upper(h.mode)='IN' and h.qty<0) or (upper(h.mode)='OUT' and h.qty>0)),false
  from public.stk_statement h join pg_temp.oo_pairs p on h.branch_name=p.branch
    and h.item_code=p.item_code and coalesce(h.company,'APG')=p.company
  where h.trans_date>p.archive_through and h.trans_date<=stock_day
  group by p.branch,p.item_code,h.trans_date
 ) x group by branch,item_code,movement_day;
 create temp table oo_evidence on commit drop as
 with events as (
  select p.branch,p.item_code,date '2026-01-01' movement_day,0::numeric net,0::numeric incoming,
    0::numeric outgoing,false bad,false adjustment from pg_temp.oo_pairs p
  union all select * from pg_temp.oo_movement
 ), balances as (
  select e.*,p.opening_qty+sum(e.net) over(partition by e.branch,e.item_code order by e.movement_day) closing,
   lead(e.movement_day) over(partition by e.branch,e.item_code order by e.movement_day) next_day
  from events e join pg_temp.oo_pairs p using(branch,item_code)
 ), exposure as (
  select branch,item_code,bool_or(bad) bad,min(closing) minimum,
    (array_agg(closing order by movement_day desc))[1] ending,
    sum(case when closing>0 then greatest(least(coalesce(next_day-1,through_day),through_day)-movement_day,0) else 0 end
      +case when movement_day>'2026-01-01' and movement_day<=through_day and not adjustment
         and closing-net-outgoing>0 and closing>0 then 1 else 0 end) stocked_days,
    sum(case when closing=0 then greatest(least(coalesce(next_day-1,through_day),through_day)-movement_day,0) else 0 end
      +case when movement_day>'2026-01-01' and movement_day<=through_day and not adjustment
         and closing=0 and closing-net=0 and incoming=0 and outgoing=0 then 1 else 0 end) empty_days,
    sum(case when closing>0 then greatest(least(coalesce(next_day-1,through_day),through_day)-
       greatest(movement_day+1,(completed_end-interval '6 months')::date)+1,0) else 0 end
      +case when movement_day>='2026-01-02' and movement_day>=(completed_end-interval '6 months')::date
         and movement_day<=through_day and not adjustment and closing-net-outgoing>0 and closing>0 then 1 else 0 end) recent_stocked_days
  from balances group by branch,item_code
 ) select p.*,e.stocked_days,e.empty_days,e.recent_stocked_days,
   coalesce(p.covered and p.opening_qty>=0 and p.current_qty is not null and not e.bad
     and e.minimum>=0 and abs(e.ending-p.current_qty)<0.000001,false) verified
 from pg_temp.oo_pairs p join exposure e using(branch,item_code);
 create index on pg_temp.oo_evidence(item_code);
 analyze pg_temp.oo_evidence;

 create temp table oo_demand on commit drop as
 with quantities as (
  select m.branch,m.item_code,m.month_start,s.scope,s.qty from pg_temp.oo_monthly m
   cross join lateral (values ('onlineOnly',m.online),('allChannels',m.total)) s(scope,qty)
 ), totals as (
  select case when grouping(branch)=1 then '' else branch end branch,item_code,scope,
   coalesce(sum(qty) filter(where extract(year from month_start)=2025),0) sales25,
   coalesce(sum(qty) filter(where extract(year from month_start)=2025 and extract(month from month_start)<=
      case when extract(year from completed_end)>2026 then 12 else extract(month from completed_end)-1 end),0) comparable25,
   coalesce(sum(qty) filter(where extract(year from month_start)=2026),0) sales26,
   coalesce(sum(qty) filter(where extract(year from month_start)=2026 and month_start<completed_end),0) comparable26,
   coalesce(sum(qty) filter(where month_start>=completed_end-interval '3 months' and month_start<completed_end),0) recent_qty
  from quantities group by grouping sets((branch,item_code,scope),(item_code,scope))
 ), selling as (
  select branch,item_code,scope,count(*) filter(where qty>0 and extract(year from month_start)=2026) selling_months
  from (select case when grouping(branch)=1 then '' else branch end branch,item_code,scope,month_start,sum(qty) qty
    from quantities group by grouping sets((branch,item_code,scope,month_start),(item_code,scope,month_start)))x
  group by branch,item_code,scope
 ), exposure as (
  select case when grouping(branch)=1 then '' else branch end branch,item_code,
    case when bool_and(current_qty is not null) then sum(current_qty) end online_stock,
    case when bool_and(verified) then min(stocked_days) end stocked_days,
    bool_or(verified and empty_days>=30) constrained
  from pg_temp.oo_evidence group by grouping sets((branch,item_code),(item_code))
 ) select b.branch,c.item_code,s.scope,c.retail,c.item,
   coalesce(t.sales25,0) sales25,coalesce(t.comparable25,0) comparable25,
   coalesce(t.sales26,0) sales26,coalesce(t.comparable26,0) comparable26,
   coalesce(t.recent_qty,0) recent_qty,coalesce(m.selling_months,0) selling_months,
   e.online_stock,e.stocked_days,coalesce(e.constrained,false) constrained
 from pg_temp.oo_catalog c cross join (select branch from pg_temp.oo_branches union all select '')b
 cross join (values('onlineOnly'),('allChannels'))s(scope)
 left join totals t on t.item_code=c.item_code and t.branch=b.branch and t.scope=s.scope
 left join selling m on m.item_code=c.item_code and m.branch=b.branch and m.scope=s.scope
 left join exposure e on e.item_code=c.item_code and e.branch=b.branch;
 perform online_overview_private.prepare_abcmt(token,completed_end,stock_day,through_day);
 forecast_meta:=online_overview_private.apply_six_month_forecast(token,completed_end);
 insert into online_overview_private.items select token,item_code,online_overview_private.display_item(item) from pg_temp.oo_catalog;
 insert into online_overview_private.results(generation,branch,scope,item_code,ordinal,payload)
 select token,branch,scope,item_code,row_number() over(partition by branch,scope order by
   case cls.payload->>'rank' when 'a' then 0 when 'b' then 1 when 'c' then 2 when 'n' then 3 when 'm' then 4 when 't' then 5 when 's' then 6 else 7 end,
   recent_qty desc,sales26 desc,item->>'item_name',item_code),
  jsonb_build_object('code',item_code,'sales25',sales25,'comparable25',comparable25,'sales26',sales26,
   'recent_qty',recent_qty,'selling_months',selling_months,'retail',retail,'price_known',retail>0,
   'top_quantity',false,'top_value',false,'online_stock',online_stock,'stocked_days',stocked_days,
   'supply',case when item->>'stock_unavailable'='true' or not item ? 'store_stock' then 'STORE stock unknown'
    when (item->>'store_stock')::numeric>0 then 'Stock in STORE' else 'Confirm supply with Purchase' end,
   'purchase_status',item->>'purchase_status_items',
   'action',case when upper(item->>'purchase_status_items') like '%DISCONTINUED%' then 'Review replacement; no automatic replenishment'
    when upper(item->>'purchase_status_items') like '%N.E%' or upper(item->>'purchase_status_items') like '%LIQUIDATION%' then 'Review expiry / suitability before distribution'
    when upper(item->>'purchase_status_items') ~ 'OOS|NOT AVAILABLE|OUT OF STOCK|PENDING AGREEMENT' then 'Purchase follow-up; retain demand class'
    when online_stock is null then 'Review missing branch stock reports'
    when online_stock<=0 and coalesce((item->>'store_stock')::numeric,0)>0 then 'Review distribution to online'
    else 'Set quantities according to branch demand and supply lead time' end)
 from pg_temp.oo_demand join online_overview_private.classification cls using(item_code) where cls.generation=token;
 get diagnostics record_count=row_count;
 if record_count<>item_count*(jsonb_array_length(roster)+1)*2 then raise exception 'Incomplete online result matrix'; end if;
 if (select count(*) from online_overview_private.classification where generation=token)<>item_count
 then raise exception 'Incomplete ABCMT classification';end if;
 if version<>online_overview_private.source_version() then raise exception 'Sources changed during preparation. Retry.'; end if;
 update online_overview_private.state set status='complete',generation=token,completed_at=clock_timestamp(),error=null,
  meta=jsonb_build_object('branches',roster,'items',item_count,'result_rows',record_count,'source_version',version,
    'refreshed_at',clock_timestamp(),'sales_through',last_month,'history_through',through_day,
    'catalog_updated_at',(select max(updated_at) from public.stock_catalog_snapshot),
    'stock_day',stock_day,'classification_version','abcmt-online-v2',
    'rules_version',case when forecast_meta->>'status'='ready' then 'abcmt-forecast6-mrn-n-store-v3' else 'abcmt-mrn-n-store-v3' end,
    'other_branch_stock_version','retail-total-v1',
    'forecast',forecast_meta,
    'excluded_branches',(select coalesce(jsonb_agg(jsonb_build_object('name',branch_name,'reason',reason,'confirmed_on',confirmed_on) order by branch_name),'[]')
       from online_overview_private.branch_exclusions where enabled),
    'classification_through',completed_end-1,
    'thresholds',(select payload#>'{classification,thresholds}' from online_overview_private.classification where generation=token limit 1),
    'model',(select artifact->'report' from online_overview_private.models where id='abcmt-online-v2')) where singleton;
 delete from online_overview_private.results where generation<>token;
 delete from online_overview_private.items where generation<>token;
 delete from online_overview_private.classification where generation<>token;
end $$;

create or replace function online_overview_private.run_job()
returns void language plpgsql security definer set search_path='' as $$
begin
 begin perform online_overview_private.build();
 exception when others then
  update online_overview_private.state set status='failed',error=sqlerrm,completed_at=clock_timestamp() where singleton;
 end;
 if exists(select 1 from cron.job where jobname='local-online-overview-once') then
  perform cron.unschedule('local-online-overview-once');
 end if;
end $$;

create or replace function online_overview_private.read_state()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 perform online_overview_private.assert_access();
 select jsonb_build_object('status',status,'generation',generation,'requested_at',requested_at,
  'completed_at',completed_at,'error',error,'meta',meta) into result from online_overview_private.state where singleton;
 if result->>'generation' is not null and not online_overview_private.roster_is_allowed(result->'meta') then
  return jsonb_build_object('status',case when result->>'status'='queued' then 'queued' else 'empty' end);
 end if;
 return result;
end $$;
create or replace function online_overview_private.read_batch(p_generation text,p_branch text,p_scope text,p_offset integer,p_limit integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 perform online_overview_private.assert_access();
 if p_scope is distinct from 'onlineOnly' or p_generation is null or p_branch is null then
  raise insufficient_privilege using message='Only online sales are available';
 end if;
 if not exists(select 1 from online_overview_private.state where singleton and generation=p_generation
   and online_overview_private.roster_is_allowed(meta))
 then raise exception 'Online snapshot changed. Reload.' using errcode='PT409'; end if;
 if p_branch<>'' and not exists(select 1 from online_overview_private.operational_branches() where branch_name=p_branch)
 then raise insufficient_privilege using message='Branch is outside Online Overview'; end if;
 select jsonb_build_object('generation',p_generation,'total',(select count(*) from online_overview_private.results
   where generation=p_generation and branch=p_branch and scope=p_scope),
  'rows',coalesce((select jsonb_agg(r.payload||coalesce(c.payload,'{}'::jsonb)||
    case when p_branch<>'' then jsonb_build_object(
     'known_online_stock',r.payload->'online_stock','reported_branches',case when r.payload->>'online_stock' is null then 0 else 1 end,
     'stocked_branches',case when (r.payload->>'online_stock')::numeric>0 then 1 else 0 end,
     'missing_branches',case when r.payload->>'online_stock' is null then jsonb_build_array(p_branch) else '[]'::jsonb end) else '{}'::jsonb end||
    jsonb_build_object('item',online_overview_private.display_item(i.payload)) order by r.ordinal)
   from (select * from online_overview_private.results where generation=p_generation and branch=p_branch and scope=p_scope
    order by ordinal limit least(greatest(p_limit,1),5000) offset greatest(p_offset,0)) r
   join online_overview_private.items i on i.generation=r.generation and i.item_code=r.item_code
   left join online_overview_private.classification c on c.generation=r.generation and c.item_code=r.item_code),'[]'::jsonb)) into result;
 return result;
end $$;
create or replace function online_overview_private.request_refresh()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform online_overview_private.assert_access();
 perform pg_advisory_xact_lock(hashtext('local_online_overview_enqueue'));
 if exists(select 1 from online_overview_private.state where singleton and status='queued' and requested_at>now()-interval '15 minutes')
 then return jsonb_build_object('status','queued'); end if;
 update online_overview_private.state set status='queued',requested_at=clock_timestamp(),error=null where singleton;
 perform cron.schedule('local-online-overview-once','* * * * *',
   'set statement_timeout=''600s''; select online_overview_private.run_job();');
 return jsonb_build_object('status','queued');
end $$;

revoke all on all functions in schema online_overview_private from public,anon,authenticated,service_role;
grant execute on function online_overview_private.assert_access() to authenticated;
grant execute on function online_overview_private.read_state(),online_overview_private.read_batch(text,text,text,integer,integer),
 online_overview_private.request_refresh() to authenticated;
create or replace function public.get_local_online_overview_state()
returns jsonb language sql stable security invoker set search_path='' as $$ select online_overview_private.read_state() $$;
create or replace function public.get_local_online_overview_batch(p_generation text,p_branch text default '',
 p_scope text default 'onlineOnly',p_offset integer default 0,p_limit integer default 5000)
returns jsonb language sql stable security invoker set search_path='' as $$
 select online_overview_private.read_batch(p_generation,p_branch,p_scope,p_offset,p_limit) $$;
create or replace function public.refresh_local_online_overview()
returns jsonb language sql security invoker set search_path='' as $$ select online_overview_private.request_refresh() $$;
revoke all on function public.get_local_online_overview_state(),public.get_local_online_overview_batch(text,text,text,integer,integer),
 public.refresh_local_online_overview() from public,anon;
grant execute on function public.get_local_online_overview_state(),public.get_local_online_overview_batch(text,text,text,integer,integer),
 public.refresh_local_online_overview() to authenticated;
notify pgrst,'reload schema';
