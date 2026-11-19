-- LOCAL ONLY. Prepared six-month experiments for Online Overview.
create table if not exists online_overview_private.forecast_runs (
 run_id text primary key, input_version text not null, through_date date not null,
 metadata jsonb not null, created_at timestamptz not null default now()
);
create table if not exists online_overview_private.forecast_rows (
 run_id text not null references online_overview_private.forecast_runs(run_id),
 item_code text not null, payload jsonb not null, primary key(run_id,item_code)
);
alter table online_overview_private.forecast_runs enable row level security;
alter table online_overview_private.forecast_rows enable row level security;
revoke all on online_overview_private.forecast_runs,online_overview_private.forecast_rows
 from public,anon,authenticated,service_role;

create or replace function online_overview_private.first_mrn_receipts(p_through date)
returns table(item_code text,first_mrn date)
language sql stable security definer set search_path='' as $$
 select btrim(m.item_code),min(m.mrn_date)
 from public.mrn_apg_2026 m
 where lower(btrim(m.status))='approved'
   and coalesce(m.total_qty,m.received_quantity,0)>0 and m.mrn_date<=p_through
 group by btrim(m.item_code)
$$;
revoke all on function online_overview_private.first_mrn_receipts(date)
 from public,anon,authenticated,service_role;

create or replace function online_overview_private.forecast_input_version()
returns text language sql stable security definer set search_path='' as $$
 with eligible as (
  select item_code,payload from public.stock_catalog_snapshot
  where payload->>'item_status' ~* '^\s*(1\s*#\s*)?normal\s+purchase\s*$'
 ), branches as (select * from online_overview_private.operational_branches()),
 sales as (
  select h.branch_name,btrim(h.item_code) item_code,h.month,coalesce(h.online,0) qty
  from public.sales_history_2025 h join branches b using(branch_name)
  join eligible i on i.item_code=btrim(h.item_code) where h.month ~ '^(0[1-9]|1[0-2])/2025$'
  union all
  select h.branch_name,btrim(h.item_code),h.month,coalesce(h.online,0)
  from public.sales_history h join branches b using(branch_name)
  join eligible i on i.item_code=btrim(h.item_code)
  where h.month ~ '^(0[1-9]|1[0-2])/2026$'
   and to_date(h.month,'MM/YYYY')<date_trunc('month',now() at time zone 'Asia/Dubai')
 ) select md5(jsonb_build_array(
  (select jsonb_agg(jsonb_build_array(item_code,payload->'retail',
     coalesce(nullif(btrim(payload->>'sales_orientation'),''),btrim(payload->>'item_priority'))) order by item_code) from eligible),
  (select jsonb_build_array(count(*),sum(qty),
     sum(hashtextextended(jsonb_build_array(branch_name,item_code,month,qty)::text,71)::numeric)) from sales),
  (select jsonb_agg(to_jsonb(b) order by branch_name) from branches b),
  (select jsonb_agg(jsonb_build_array(m.item_code,m.first_mrn) order by m.item_code)
   from online_overview_private.first_mrn_receipts(
     date_trunc('month',now() at time zone 'Asia/Dubai')::date-1) m
   join eligible e using(item_code)),
  'first-mrn-six-calendar-months-v1'
 )::text)
$$;

create or replace function online_overview_private.apply_mrn_age(p_generation text,age_day date)
returns void language plpgsql security definer set search_path='' as $$
begin
 -- Current product age and the N stock rule use today's MRN history. Forecast
 -- training/evidence is independently pinned to its completed-sales cutoff.
 with sales as (
  select item_code,min(month_start) first_sale from (
   select item_code,month_start,sum(online) qty from pg_temp.oo_monthly group by item_code,month_start
  ) s where qty>0 group by item_code
 ), ages as (
  select c.item_code,coalesce(c.payload#>'{classification,forecast,product_age}','{}'::jsonb) ||
   jsonb_build_object('status',case when m.first_mrn is not null and age_day<(m.first_mrn+interval '6 months')::date
     then 'new' else 'existing' end,'first_mrn',m.first_mrn,'as_of',age_day,
    'new_until',(m.first_mrn+interval '6 months')::date,
    'months_since_mrn',case when m.first_mrn is not null then
      (extract(year from age(age_day,m.first_mrn))*12+extract(month from age(age_day,m.first_mrn)))::integer end,
    'days_since_mrn',case when m.first_mrn is not null then age_day-m.first_mrn+1 end,
    'first_online_sale_month',s.first_sale,
    'months_to_first_sale',case when m.first_mrn is not null and s.first_sale is not null then
      greatest(0,(extract(year from s.first_sale)::integer-extract(year from m.first_mrn)::integer)*12+
        extract(month from s.first_sale)::integer-extract(month from m.first_mrn)::integer) end,
    'sales_before_first_mrn',coalesce(s.first_sale<date_trunc('month',m.first_mrn)::date,false)) product_age
  from online_overview_private.classification c
  left join online_overview_private.first_mrn_receipts(age_day) m using(item_code)
  left join sales s using(item_code)
  where c.generation=p_generation
 ) update online_overview_private.classification c set payload=jsonb_set(c.payload,
   '{classification,product_age}',a.product_age)
 from ages a where c.generation=p_generation and c.item_code=a.item_code;

 update online_overview_private.classification c set payload=c.payload ||
  jsonb_build_object('rank','n',
   'reason','New product. First MRN ' || (c.payload#>>'{classification,product_age,first_mrn}') ||
     '. Stock is 0 Qty in all ' || (c.payload#>>'{classification,total_branches}') ||
     ' online branches. Stock is available in STORE.') ||
  jsonb_build_object('classification',c.payload->'classification' || jsonb_build_object(
   'basis','First MRN within 6 months, zero online stock and positive STORE stock',
   'rules_version','abcmt-forecast6-mrn-n-store-v3',
   'previous_rank',coalesce(c.payload#>'{classification,previous_rank}',c.payload->'rank'),
   'reason','New product with STORE stock and no current online stock.',
   'priority_route','new_no_online_stock','priority_branches','[]'::jsonb,
   'evidence_status','supported','evidence_note','New by first approved MRN; every online branch reports 0 Qty and STORE stock is positive.',
   'price_affects_abc',false,'ml',jsonb_build_object('use','business_rule'), 'ml_disagrees',false))
 from pg_temp.oo_catalog catalog
 where c.generation=p_generation and c.payload->>'rank'<>'s' and catalog.item_code=c.item_code
  and coalesce((catalog.item->>'store_stock')::numeric,0)>0
  and coalesce(catalog.item->>'stock_unavailable','false')<>'true'
  and c.payload#>>'{classification,product_age,status}'='new'
  and (c.payload->>'reported_branches')::integer=(c.payload#>>'{classification,total_branches}')::integer
  and (c.payload->>'stocked_branches')::integer=0 and (c.payload->>'known_online_stock')::numeric=0;
end $$;
revoke all on function online_overview_private.apply_mrn_age(text,date)
 from public,anon,authenticated,service_role;

create or replace function online_overview_private.apply_six_month_forecast(p_generation text,p_end date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare run online_overview_private.forecast_runs; active_id text; total integer;
 age_day date:=(now() at time zone 'Asia/Dubai')::date;
begin
 select artifact->>'run_id' into active_id from online_overview_private.models where id='online-six-month-v1';
 select * into run from online_overview_private.forecast_runs where run_id=active_id;
 if run.run_id is null then
  perform online_overview_private.apply_mrn_age(p_generation,age_day);
  return jsonb_build_object('status','unavailable');end if;
 if run.input_version<>online_overview_private.forecast_input_version() or run.through_date<>p_end-1
 then
  perform online_overview_private.apply_mrn_age(p_generation,age_day);
  return jsonb_build_object('status','needs_update');end if;
 select count(*) into total from online_overview_private.forecast_rows where run_id=active_id;
 if total<>(select count(*) from pg_temp.oo_catalog) or exists(
  select 1 from pg_temp.oo_catalog c where not exists(select 1 from online_overview_private.forecast_rows f
   where f.run_id=active_id and f.item_code=c.item_code)
 ) then raise exception 'Incomplete six-month forecast';end if;
 if exists(select 1 from online_overview_private.forecast_rows f where f.run_id=active_id and (
  f.payload->>'run_id' is distinct from active_id or f.payload->>'suggested_rank' not in ('a','b','c')
  or exists(select 1 from jsonb_array_elements(f.payload->'branches') b
   where not exists(select 1 from pg_temp.oo_branches allowed where allowed.branch=b->>'branch'))
  or exists(select 1 from jsonb_array_elements_text(f.payload->'suggested_branches') b(branch)
   where not exists(select 1 from pg_temp.oo_branches allowed where allowed.branch=b.branch))
 )) then raise exception 'Invalid or unscoped six-month forecast';end if;
 update online_overview_private.classification c set payload=c.payload ||
  case when c.payload->>'rank' in ('a','b','c') then
   jsonb_build_object('rank',f.payload->'suggested_rank','reason',f.payload->'reason') else '{}'::jsonb end ||
  jsonb_build_object('classification',c.payload->'classification' ||
   jsonb_build_object('forecast',f.payload-'branches','previous_rank',c.payload->'rank',
    'rules_version','abcmt-forecast6-mrn-n-store-v3') ||
   case when c.payload->>'rank' in ('a','b','c') then jsonb_build_object(
    'basis','Expected online sales for the next 6 months','reason',f.payload->'reason',
    'priority_route',f.payload->'qualification','priority_branches','[]'::jsonb,
    'price_affects_abc',f.payload->>'qualification' in ('forecast_value','premium_repeat'),
    'ml',jsonb_build_object('use','six_month_forecast','model_version','online-six-month-v1',
     'horizon_months',6),'ml_disagrees',false) else '{}'::jsonb end)
 from online_overview_private.forecast_rows f
 where c.generation=p_generation and f.run_id=active_id and f.item_code=c.item_code;

 perform online_overview_private.apply_mrn_age(p_generation,age_day);
 return run.metadata || jsonb_build_object('status','ready','run_id',active_id);
end $$;

create or replace function online_overview_private.forecast_details(p_generation text,p_item_code text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare snapshot_meta jsonb; forecast_id text; result jsonb;
begin
 perform online_overview_private.assert_access();
 select meta into snapshot_meta from online_overview_private.state where singleton and generation=p_generation;
 if snapshot_meta is null or not online_overview_private.roster_is_allowed(snapshot_meta)
 then raise exception 'Online snapshot changed. Reload.' using errcode='40001';end if;
 select payload#>>'{classification,forecast,run_id}' into forecast_id
 from online_overview_private.classification where generation=p_generation and item_code=p_item_code;
 select payload into result from online_overview_private.forecast_rows where run_id=forecast_id and item_code=p_item_code;
 if exists(select 1 from jsonb_array_elements(result->'branches') b where not exists(
  select 1 from jsonb_array_elements(snapshot_meta->'branches') allowed where allowed->>'name'=b->>'branch'))
 then raise insufficient_privilege using message='Forecast contains an unapproved branch';end if;
 return coalesce(result,'{}'::jsonb);
end $$;
revoke all on function online_overview_private.forecast_input_version(),
 online_overview_private.apply_six_month_forecast(text,date),
 online_overview_private.forecast_details(text,text) from public,anon,authenticated,service_role;
grant execute on function online_overview_private.forecast_details(text,text) to authenticated;
create or replace function public.get_local_online_overview_forecast(p_generation text,p_item_code text)
returns jsonb language sql stable security invoker set search_path='' as $$
 select online_overview_private.forecast_details(p_generation,p_item_code)
$$;
revoke all on function public.get_local_online_overview_forecast(text,text) from public,anon,service_role;
grant execute on function public.get_local_online_overview_forecast(text,text) to authenticated;
notify pgrst,'reload schema';
