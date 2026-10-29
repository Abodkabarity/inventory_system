-- Daily SYSTEM-stock evidence. Missing opening rows never mean zero. This
-- first evidence layer is STORE-scoped; retail demand is not inferred from
-- STORE availability. Existing stock, sales, expiry and order facts stay intact.
create table public.stock_supply_insights (
  item_code text primary key,
  summary jsonb not null,
  detail jsonb not null,
  source_version text not null,
  updated_at timestamptz not null default now()
);
alter table public.stock_supply_insights enable row level security;
revoke all on public.stock_supply_insights from public,anon,authenticated;
grant select on public.stock_supply_insights to authenticated;
grant all on public.stock_supply_insights to service_role;
create policy stock_supply_insights_read on public.stock_supply_insights
  for select to authenticated using ((select public.item_tracker_my_role())='inventory'
    or (select stock_management_private.is_view_user()));

create table public.stock_supply_insight_state (
  singleton boolean primary key default true check(singleton),
  generation uuid,source_version text,completed_at timestamptz,
  item_count integer not null default 0,history_through date,last_error text,last_attempt_at timestamptz
);
insert into public.stock_supply_insight_state(singleton) values(true);
alter table public.stock_supply_insight_state enable row level security;
revoke all on public.stock_supply_insight_state from public,anon,authenticated;
grant select on public.stock_supply_insight_state to authenticated;
grant all on public.stock_supply_insight_state to service_role;
create policy stock_supply_insight_state_read on public.stock_supply_insight_state
  for select to authenticated using ((select public.item_tracker_my_role())='inventory'
    or (select stock_management_private.is_view_user()));

create function stock_management_private.supply_version()
returns text language sql stable security invoker set search_path='' as $$
 select coalesce((select generation::text from public.stock_supply_insight_state where singleton),'pending');
$$;
revoke all on function stock_management_private.supply_version() from public,anon;
grant execute on function stock_management_private.supply_version() to authenticated,service_role;

create function stock_management_private.add_supply_days(p_counts jsonb,p_from date,p_to date,p_kind text)
returns jsonb language plpgsql immutable set search_path='' as $$
declare d date:=p_from; stop date; k text; n integer; counts jsonb:=p_counts;
begin
  if p_from is null or p_to is null or p_from>p_to then return counts; end if;
  while d<=p_to loop
    stop:=least(p_to,(date_trunc('month',d)+interval '1 month'-interval '1 day')::date);
    k:=to_char(d,'MM/YYYY'); n:=stop-d+1;
    counts:=jsonb_set(counts,array[k],coalesce(counts->k,'{}'::jsonb)||
      jsonb_build_object(p_kind,coalesce((counts->k->>p_kind)::integer,0)+n));
    d:=stop+1;
  end loop;
  return counts;
end $$;
revoke all on function stock_management_private.add_supply_days(jsonb,date,date,text) from public,anon,authenticated;
grant execute on function stock_management_private.add_supply_days(jsonb,date,date,text) to service_role;

create function stock_management_private.analyze_supply(p jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare
  through_day date:=(p->>'through')::date; baseline_day date:=date '2026-01-01';
  last_day date:=baseline_day; d date; balance numeric; next_balance numeric;
  zero_from date; lower_bound boolean:=false; established boolean:=false;
  issues text[]:='{}'; counts jsonb:='{}'; events jsonb:='[]'; row jsonb; receipt jsonb;
  latest jsonb; result jsonb; summary jsonb; months jsonb:='[]'; key text; m date;
  stock_day date:=(p->>'stock_day')::date; current_qty numeric:=(p->>'current_qty')::numeric;
  valid boolean:=true; linked boolean; gap_adjusted boolean:=false;
  state text:='in_store'; confidence text:='verified'; gap integer; end_qty numeric;
  eps constant numeric:=0.000001;
begin
  if through_day is null or through_day<=baseline_day then issues:=array_append(issues,'history_missing'); end if;
  if coalesce((p->>'baseline_count')::integer,0)<>1 then issues:=array_append(issues,'opening_missing');
  else
    balance:=(p->>'opening_qty')::numeric;
    if balance is null then issues:=array_append(issues,'opening_missing'); end if;
  end if;
  if coalesce((p->>'bad_company')::boolean,false) then issues:=array_append(issues,'company_mismatch'); end if;
  if coalesce((p->>'opening_movements')::integer,0)>0 then issues:=array_append(issues,'opening_boundary'); end if;
  valid:=cardinality(issues)=0;
  if valid then
    established:=balance>eps or coalesce((p->>'prior_sales')::numeric,0)>0;
    if abs(balance)<=eps then balance:=0; zero_from:=baseline_day+1; lower_bound:=true; end if;
    if balance<0 then issues:=array_append(issues,'negative_balance'); end if;
    for row in select value from jsonb_array_elements(coalesce(p->'days','[]')) order by value->>'date' loop
      d:=(row->>'date')::date;
      if d<=baseline_day or d>through_day then continue; end if;
      if d<=last_day then raise exception 'Supply movement days must be unique and ordered'; end if;
      counts:=stock_management_private.add_supply_days(counts,last_day+1,d-1,
        case when balance>eps then 'available' when abs(balance)<=eps then 'empty' else 'unknown' end);
      if coalesce((row->>'bad_sign')::boolean,false) then issues:=array_append(issues,'movement_sign'); end if;
      if coalesce((row->>'bad_company')::boolean,false) then issues:=array_append(issues,'company_mismatch'); end if;
      next_balance:=balance+coalesce((row->>'net')::numeric,0);
      if abs(next_balance)<=eps then next_balance:=0; end if;
      if next_balance<0 then issues:=array_append(issues,'negative_balance'); end if;
      counts:=stock_management_private.add_supply_days(counts,d,d,
        case when balance>eps and next_balance>eps and not coalesce((row->>'adjustment')::boolean,false) then 'available'
          when balance=0 and next_balance=0 and coalesce((row->>'incoming')::numeric,0)=0
            and not coalesce((row->>'adjustment')::boolean,false) then 'empty' else 'partial' end);
      if zero_from is not null and coalesce((row->>'adjustment')::boolean,false) then gap_adjusted:=true; end if;
      if balance=0 and next_balance>eps and zero_from is not null then
        gap:=greatest(d-zero_from,0);
        select value into receipt from jsonb_array_elements(coalesce(p->'mrns','[]')) where value->>'date'=d::text limit 1;
        linked:=receipt is not null and coalesce((receipt->>'qty')::numeric,0)>0
          and coalesce((row->>'mrn_qty')::numeric,0)>0
          and abs((receipt->>'qty')::numeric-(row->>'mrn_qty')::numeric)<=eps
          and not gap_adjusted;
        events:=events||jsonb_build_array(jsonb_build_object('from',zero_from,'returned_at',d,
          'days',gap,'at_least',lower_bound,'established',established,'mrn_linked',linked,
          'received_qty',receipt->'qty','mrn_numbers',receipt->'numbers','adjusted',gap_adjusted));
        zero_from:=null; lower_bound:=false; gap_adjusted:=false;
      end if;
      -- A zero closing balance with same-day receipts is not continuous absence.
      if next_balance=0 and (balance<>0 or coalesce((row->>'incoming')::numeric,0)>0) then
        zero_from:=d+1; lower_bound:=false; gap_adjusted:=coalesce((row->>'adjustment')::boolean,false);
      end if;
      established:=established or next_balance>eps;
      balance:=next_balance; last_day:=d;
    end loop;
    counts:=stock_management_private.add_supply_days(counts,last_day+1,through_day,
      case when balance>eps then 'available' when balance=0 then 'empty' else 'unknown' end);
    end_qty:=balance;
    if coalesce((p->>'current_count')::integer,0)<>1 or stock_day is null or current_qty is null then
      issues:=array_append(issues,'current_stock_missing');
    elsif stock_day<through_day or (stock_day>through_day and
      (coalesce((p->>'bridge_through')::date,date '1900-01-01')<stock_day or coalesce((p->>'bridge_bad')::boolean,false))) then
      issues:=array_append(issues,'current_stock_not_comparable');
    elsif abs(balance+coalesce((p->>'bridge_net')::numeric,0)-current_qty)>eps then
      issues:=array_append(issues,'balance_mismatch');
    end if;
    m:=date '2026-01-01';
    while m<=through_day loop
      key:=to_char(m,'MM/YYYY');
      months:=months||jsonb_build_array(jsonb_build_object('month',key,
        'available_days',coalesce((counts->key->>'available')::integer,0),
        'empty_days',coalesce((counts->key->>'empty')::integer,0),
        'partial_days',coalesce((counts->key->>'partial')::integer,0),
        'unknown_days',coalesce((counts->key->>'unknown')::integer,0),
        'sales_qty',(select value->'total' from jsonb_array_elements(coalesce(p->'monthly_sales','[]')) where value->>'month'=key limit 1),
        'prior_year_sales_qty',(select value->'total' from jsonb_array_elements(coalesce(p->'monthly_sales','[]')) where value->>'month'=to_char(m-interval '1 year','MM/YYYY') limit 1)));
      m:=(m+interval '1 month')::date;
    end loop;
  end if;
  select coalesce(array_agg(distinct x),'{}') into issues from unnest(issues)x;
  if cardinality(issues)>0 then state:='history_needed'; confidence:='unavailable';
  else
    select value into latest from jsonb_array_elements(events) order by value->>'returned_at' desc limit 1;
    if latest is not null and (latest->>'days')::integer>=30 and (latest->>'established')::boolean
      and (latest->>'mrn_linked')::boolean
      and (latest->>'returned_at')::date>=coalesce((p->>'today')::date,stock_day,through_day)-30
      and current_qty>eps then state:='back_in_store';
    elsif balance=0 and current_qty>eps then state:='receipt_pending'; confidence:='limited';
    elsif balance=0 and current_qty=0 then state:='store_empty';
    else state:='in_store'; end if;
  end if;
  summary:=jsonb_build_object('status',state,'confidence',confidence,'scope','STORE','through',through_day,
    'gap_days',case when state='back_in_store' then latest->'days' when state='store_empty' then to_jsonb(greatest(through_day-zero_from+1,0)) end,
    'at_least',case when state='back_in_store' then (latest->>'at_least')::boolean else lower_bound end,
    'returned_at',case when state='back_in_store' then latest->'returned_at' end,
    'received_qty',case when state='back_in_store' then latest->'received_qty' end);
  result:=summary||jsonb_build_object('opening_date',baseline_day,'opening_qty',p->'opening_qty',
    'current_qty',current_qty,'stock_day',stock_day,'history_qty',end_qty,
    'issues',to_jsonb(issues),'monthly',months,'events',events,
    'source','stock_statement_and_ledger','daily_precision',true,
    'sales_scope','All source branches; STORE availability is a separate scope',
    'forecast_status','branch_availability_required','sales_through',p->'sales_through');
  return jsonb_build_object('summary',summary,'detail',result);
end $$;
revoke all on function stock_management_private.analyze_supply(jsonb) from public,anon,authenticated;
grant execute on function stock_management_private.analyze_supply(jsonb) to service_role;

create function stock_management_private.supply_source_version() returns text
language sql stable security invoker set search_path='' as $source$
select md5(jsonb_build_array(
    (select jsonb_agg(to_jsonb(p) order by company,from_date) from public.stk_statement_history_load_progress p),
    (select max(imported_at) from public.stk_ledger_history),
    (select max(created_at) from public.stk_ledger),
    (select max(created_at) from public.stk_statement),
    (select jsonb_agg(to_jsonb(r) order by source) from public.stock_catalog_cache_revisions r),
    (select jsonb_agg(to_jsonb(r) order by source) from public.stock_workspace_cache_revisions r where source in ('mrn_receipts','mrn_snapshot')),
    (now() at time zone 'Asia/Dubai')::date)::text);
$source$;
revoke all on function stock_management_private.supply_source_version() from public,anon,authenticated;
grant execute on function stock_management_private.supply_source_version() to service_role;

create function stock_management_private.refresh_supply_insights(p_force boolean default false)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='240s' set enable_nestloop='off' as $$
declare v_through date:=date '2025-12-31'; period record; version text; n integer;
  v_stock_day date; v_bridge_through date; expected integer;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('stock-supply-insights',0)) then
    return jsonb_build_object('status','already_running'); end if;
  for period in select * from public.stk_statement_history_load_progress where company='APG' order by from_date loop
    if period.complete and period.committed_rows=period.expected_rows and period.from_date<=v_through+1 then
      v_through:=greatest(v_through,period.to_date); end if;
  end loop;
  v_through:=least(v_through,(now() at time zone 'Asia/Dubai')::date-1);
  select (max(created_at) at time zone 'Asia/Dubai')::date into v_stock_day from public.stk_ledger;
  select max(trans_date) into v_bridge_through from public.stk_statement;
  version:=stock_management_private.supply_source_version();
  if not p_force and exists(select 1 from public.stock_supply_insight_state where singleton and source_version=version) then
    return jsonb_build_object('status','unchanged'); end if;
  delete from public.stock_supply_insights;
  insert into public.stock_supply_insights(item_code,summary,detail,source_version)
  with tracked as materialized (
    select item_code,payload from public.stock_catalog_snapshot
    union all select item_code,payload from public.stock_management_snapshot s
      where not exists(select 1 from public.stock_catalog_snapshot c where c.item_code=s.item_code)
    union all select distinct on(e.item_code) e.item_code,e.product_data from public.stock_expiry_alert_receipts e
      where not exists(select 1 from public.stock_catalog_snapshot c where c.item_code=e.item_code)
        and not exists(select 1 from public.stock_management_snapshot s where s.item_code=e.item_code)
    order by 1
  ), opening as materialized (
    select b.item_code,count(*) n,min(b.actual_qty) qty,
      bool_or(b.company not in ('APG','Al Ain Pharmacy Group (APG)')) bad_company
    from public.stk_ledger_history b join tracked t using(item_code)
    where b.stock_date='2026-01-01' and b.report_from_date=b.stock_date and b.report_to_date=b.stock_date
      and b.branch_name='STORE' and not b.source_branch_missing group by b.item_code
  ), days as materialized (
    select h.item_code,h.trans_date,
      sum(h.qty) net,sum(greatest(h.qty,0)) incoming,
      sum(h.qty) filter(where lower(btrim(h.trans_type))='mrn') mrn_qty,
      bool_or(lower(btrim(h.trans_type))='invadjustment') adjustment,
      bool_or(lower(btrim(h.mode)) not in ('in','out') or h.mode is null or h.qty is null
        or (lower(btrim(h.mode))='in' and h.qty<0) or (lower(btrim(h.mode))='out' and h.qty>0)) bad_sign,
      bool_or(h.company<>'APG' or h.company is null) bad_company
    from public.stk_statement_history_2026 h join opening o on o.item_code=h.item_code and o.n=1
    where h.branch_name='STORE' and h.trans_date between date '2026-01-01' and v_through
      and (h.qty<>0 or h.qty is null)
    group by h.item_code,h.trans_date
  ), moves as materialized (
    select item_code,jsonb_agg(jsonb_build_object('date',trans_date,'net',net,'incoming',incoming,
      'mrn_qty',coalesce(mrn_qty,0),'adjustment',adjustment,'bad_sign',bad_sign,'bad_company',bad_company) order by trans_date)
      filter(where trans_date>date '2026-01-01') days,
      count(*) filter(where trans_date=date '2026-01-01') opening_movements
    from days group by item_code
  ), current_stock as materialized (
    select item_code,count(*) n,min(actual_qty) qty from public.stk_ledger
    where branch_name='STORE' group by item_code
  ), bridge as materialized (
    select item_code,sum(qty) net,
      bool_or(qty is null or lower(btrim(mode)) not in ('in','out') or mode is null
        or (lower(btrim(mode))='in' and qty<0) or (lower(btrim(mode))='out' and qty>0)
        or company<>'APG' or company is null) bad
    from public.stk_statement where branch_name='STORE' and trans_date>v_through and trans_date<=v_stock_day
    group by item_code
  ), receipts as materialized (
    select btrim(item_code) item_code,mrn_date,sum(coalesce(received_quantity,0)) qty,
      jsonb_agg(distinct coalesce(mrn_no,'')) numbers
    from public.mrn_apg_2026 where lower(btrim(status))='approved' and lower(btrim(warehouse))='store'
      and mrn_date>date '2026-01-01' and mrn_date<=v_through group by btrim(item_code),mrn_date
  ), mrns as materialized (
    select item_code,jsonb_agg(jsonb_build_object('date',mrn_date,'qty',qty,'numbers',numbers) order by mrn_date) mrns
    from receipts group by item_code
  ), analyzed as materialized (
    select t.item_code,stock_management_private.analyze_supply(jsonb_build_object(
      'through',case when v_through>=date '2026-01-01' then v_through end,
      'today',(now() at time zone 'Asia/Dubai')::date,
      'baseline_count',coalesce(o.n,0),'opening_qty',o.qty,'bad_company',coalesce(o.bad_company,false),
      'opening_movements',coalesce(m.opening_movements,0),'days',coalesce(m.days,'[]'::jsonb),
      'current_count',coalesce(s.n,0),'current_qty',s.qty,'stock_day',v_stock_day,
      'bridge_through',v_bridge_through,'bridge_net',coalesce(b.net,0),'bridge_bad',coalesce(b.bad,false),
      'mrns',coalesce(r.mrns,'[]'::jsonb),'monthly_sales',case when jsonb_typeof(t.payload->'monthly_sales')='array' then t.payload->'monthly_sales' else '[]'::jsonb end,
      'sales_through',t.payload->'meta'->'demand_through',
      'prior_sales',coalesce(t.payload->'years'->'2025'->'total','0'::jsonb))) result
    from tracked t left join opening o using(item_code) left join moves m using(item_code)
      left join current_stock s using(item_code) left join bridge b using(item_code) left join mrns r using(item_code)
  ) select item_code,result->'summary',result->'detail',version from analyzed;
  get diagnostics n=row_count;
  select count(*) into expected from (select item_code from public.stock_catalog_snapshot union
    select item_code from public.stock_management_snapshot union select item_code from public.stock_expiry_alert_receipts)x;
  if n=0 or n<>expected then raise exception 'Supply analysis incomplete: % / %',n,expected; end if;
  if stock_management_private.supply_source_version() is distinct from version then
    raise exception 'Supply sources changed during analysis; previous complete analysis preserved.' using errcode='40001'; end if;
  update public.stock_supply_insight_state set generation=gen_random_uuid(),source_version=version,
    completed_at=clock_timestamp(),item_count=n,history_through=v_through,last_error=null,last_attempt_at=clock_timestamp() where singleton;
  return jsonb_build_object('items',n,'through',v_through,'status','complete');
end $$;
revoke all on function stock_management_private.refresh_supply_insights(boolean) from public,anon,authenticated;
grant execute on function stock_management_private.refresh_supply_insights(boolean) to service_role;

-- Cached evidence is joined at presentation boundaries.
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
    limit least(greatest(coalesce(p_limit,30),1),5000) offset greatest(coalesce(p_offset,0),0)
  ) select jsonb_build_object(
    'rows',coalesce((select jsonb_agg((to_jsonb(p)-'receipts') || jsonb_build_object('vendor',stock_management_private.expiry_vendor(p.item_code,p.expiry_date),'product_data',
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
  )
)q(value);
$function$;

-- Cached evidence is joined at presentation boundaries.
CREATE OR REPLACE FUNCTION public.get_stock_catalog_page(p_search text DEFAULT ''::text, p_signal text DEFAULT ''::text, p_category text DEFAULT ''::text, p_supplier text DEFAULT ''::text, p_sort text DEFAULT 'name'::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 50)
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
      item_name,item_code limit least(greatest(p_limit,1),5000) offset greatest(p_offset,0)
  ) select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(payload-'distribution_orders'-'branch_stock'-'branch_demand'-'monthly_sales'-'current_month_branch_sales'-'daily_sales_45d'-'daily_sales_45d_available'-'meta') from page),'[]'::jsonb),
    'summary',(select jsonb_build_object('items',count(*),'surge',count(*) filter(where demand_surge or (payload->>'new_demand')::boolean),
      'shortage',count(*) filter(where (payload->>'recent_sales')::numeric>total_stock),
      'low_cover',count(*) filter(where payload->>'stock_status'='low_cover'),
      'no_stock',count(*) filter(where total_stock<=0),'total_stock',coalesce(sum(total_stock),0)) from filtered),
    'meta',coalesce((select payload->'meta' from public.stock_catalog_snapshot limit 1),'{}'::jsonb) || jsonb_build_object('catalog_cache_version',stock_management_private.catalog_cache_version(false)),
    'categories',coalesce((select jsonb_agg(category order by category) from (select distinct category from public.stock_catalog_snapshot where category<>'') c),'[]'::jsonb),
    'suppliers',coalesce((select jsonb_agg(supplier order by supplier) from (select distinct supplier from public.stock_catalog_snapshot where supplier<>'') c),'[]'::jsonb)
  )
)q(value);
$function$;

-- Cached evidence is joined at presentation boundaries.
CREATE OR REPLACE FUNCTION public.get_stock_catalog_register_batch(p_offset integer DEFAULT 0, p_limit integer DEFAULT 5000)
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
select jsonb_build_object(
    'rows',coalesce((select jsonb_agg(payload-'distribution_orders'-'branch_stock'-'branch_demand'-'monthly_sales'-'current_month_branch_sales'-'daily_sales_45d'-'daily_sales_45d_available'-'meta' order by item_code)
      from (select item_code,payload from public.stock_catalog_snapshot order by item_code
        limit least(greatest(p_limit,1),5000) offset greatest(p_offset,0)) p),'[]'::jsonb),
    'total',(select count(*) from public.stock_catalog_snapshot),
    'snapshot_at',coalesce((select payload->'meta'->>'refreshed_at' from public.stock_catalog_snapshot limit 1),'')
  )
)q(value);
$function$;

-- Cached evidence is joined at presentation boundaries.
CREATE OR REPLACE FUNCTION public.get_stock_management_item(p_item_code text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
select q.value||jsonb_build_object('supply_insight',
    coalesce(i.detail,'{"status":"pending","scope":"STORE","confidence":"unavailable"}'::jsonb)
    ||jsonb_build_object('generated_at',i.updated_at))
 from (
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
  where snapshot.item_code = p_item_code
)q(value) left join public.stock_supply_insights i on i.item_code=p_item_code;
$function$;

-- Cached evidence is joined at presentation boundaries.
CREATE OR REPLACE FUNCTION public.get_stock_expiry_item(p_item_code text, p_expiry_date date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
select q.value||jsonb_build_object('product_data',q.value->'product_data'||jsonb_build_object('supply_insight',coalesce(i.detail,'{}'::jsonb)), 'supply_insight',
    coalesce(i.detail,'{"status":"pending","scope":"STORE","confidence":"unavailable"}'::jsonb)
    ||jsonb_build_object('generated_at',i.updated_at))
 from (
select to_jsonb(c)||jsonb_build_object('vendor',stock_management_private.expiry_vendor(c.item_code,c.expiry_date),'note',coalesce(r.note,''),
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
  where c.item_code=p_item_code and c.expiry_date=p_expiry_date
)q(value) left join public.stock_supply_insights i on i.item_code=p_item_code;
$function$;

-- Cached evidence is joined at presentation boundaries.
CREATE OR REPLACE FUNCTION stock_management_private.catalog_cache_version(p_details boolean)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
select q.value||':supply:'||stock_management_private.supply_version() from (
select case when count(*)=case when p_details then 4 else 1 end
    then 'v1:'||string_agg(source||':'||revision::text,',' order by source) end
  from public.stock_catalog_cache_revisions
  where p_details or source='snapshot'
)q(value);
$function$;

-- Cached evidence is joined at presentation boundaries.
CREATE OR REPLACE FUNCTION public.get_stock_management_page(p_search text DEFAULT ''::text, p_status text DEFAULT ''::text, p_category text DEFAULT ''::text, p_supplier text DEFAULT ''::text, p_received_from date DEFAULT NULL::date, p_received_to date DEFAULT NULL::date, p_sort text DEFAULT 'latest_mrn'::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 50)
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
  )
)q(value);
$function$;

-- Cached evidence is joined at presentation boundaries.
CREATE OR REPLACE FUNCTION public.get_stock_management_register_batch(p_offset integer DEFAULT 0, p_limit integer DEFAULT 5000)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
 SET enable_nestloop TO 'off'
AS $function$
select q.value||jsonb_build_object('rows',coalesce((
    select jsonb_agg(r.row||jsonb_build_object('supply_insight',
      coalesce(i.summary,'{"status":"pending","scope":"STORE","confidence":"unavailable"}'::jsonb)
      ||jsonb_build_object('generated_at',i.updated_at)) order by r.ordinal)
    from jsonb_array_elements(q.value->'rows') with ordinality r(row,ordinal)
    left join public.stock_supply_insights i on i.item_code=r.row->>'item_code'),'[]'::jsonb))
 from (
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
    'snapshot_at',(select max(updated_at) from public.stock_management_snapshot))
)q(value);
$function$;

-- Cached evidence is joined at presentation boundaries.
CREATE OR REPLACE FUNCTION public.get_stock_catalog_item(p_item_code text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
select q.value||jsonb_build_object('supply_insight',
    coalesce(i.detail,'{"status":"pending","scope":"STORE","confidence":"unavailable"}'::jsonb)
    ||jsonb_build_object('generated_at',i.updated_at))
 from (
with snapshot as materialized (
    select payload from public.stock_catalog_snapshot where item_code=p_item_code
  ), active_branches as materialized (
    select branch_name branch,branch_group,public._norm_text(branch_name) branch_key
    from public.branches where is_active is true and public._norm_text(branch_name) not in
      ('store','main virtual','new virtual','store - expired item','store-ws')
  ), sales_2025 as (
    select branch_key,sum(total) total from (
      select public._norm_text(branch_name) branch_key,
        sum(coalesce(cash,0)+coalesce(insurance,0)+coalesce(online,0)) total
      from public.sales_history_2025
      where btrim(item_code)=p_item_code and month ~ '^(0[1-9]|1[0-2])/2025$'
        and to_date(month,'MM/YYYY')<coalesce(
          (select nullif(payload->'meta'->>'monthly_current_month','')::date from snapshot),'infinity'::date)
      group by public._norm_text(branch_name)
      union all
      select e.key,e.value::numeric from snapshot s
      cross join lateral jsonb_each_text(coalesce(s.payload->'current_month_branch_sales','{}'::jsonb)) e
      where extract(year from nullif(s.payload->'meta'->>'monthly_current_month','')::date)=2025
    ) totals group by branch_key
  ), sales_2026 as (
    select branch_key,sum(total) total from (
      select public._norm_text(branch_name) branch_key,
        sum(coalesce(cash,0)+coalesce(insurance,0)+coalesce(online,0)) total
      from public.sales_history
      where btrim(item_code)=p_item_code and month ~ '^(0[1-9]|1[0-2])/2026$'
        and to_date(month,'MM/YYYY')<coalesce(
          (select nullif(payload->'meta'->>'monthly_current_month','')::date from snapshot),'infinity'::date)
      group by public._norm_text(branch_name)
      union all
      select e.key,e.value::numeric from snapshot s
      cross join lateral jsonb_each_text(coalesce(s.payload->'current_month_branch_sales','{}'::jsonb)) e
      where extract(year from nullif(s.payload->'meta'->>'monthly_current_month','')::date)=2026
    ) totals group by branch_key
  ), branches as (
    select b.branch,b.branch_group,
      (s.payload->'distribution_orders'->b.branch_key->>'eligible')::boolean distribution_eligible,
      (s.payload->'distribution_orders'->b.branch_key->>'reorder_qty')::numeric reorder_qty,
      (s.payload->'distribution_orders'->b.branch_key->>'final_qty')::numeric final_qty,
      coalesce((s.payload->'branch_stock'->b.branch_key->>'stock')::numeric,0) stock,
      coalesce((s.payload->'branch_demand'->b.branch_key->>'recent_sales')::numeric,0) recent_sales,
      coalesce((s.payload->'branch_demand'->b.branch_key->>'last_3_sales')::numeric,0) last_3_sales,
      coalesce((s.payload->'branch_demand'->b.branch_key->>'baseline_sales')::numeric,0) baseline_sales,
      coalesce(y25.total,0) sales_2025,coalesce(y26.total,0) sales_2026
    from snapshot s cross join active_branches b
    left join sales_2025 y25 using(branch_key)
    left join sales_2026 y26 using(branch_key)
  ) select payload-'branch_stock'-'branch_demand'-'distribution_orders'-'current_month_branch_sales' || jsonb_build_object(
    'branches',coalesce((select jsonb_agg(to_jsonb(b)-'branch_key' order by recent_sales desc,branch)
      from branches b),'[]'::jsonb),
    '_cache_version',stock_management_private.catalog_cache_version(true)) from snapshot
)q(value) left join public.stock_supply_insights i on i.item_code=p_item_code;
$function$;

-- Cached evidence is joined at presentation boundaries.
CREATE OR REPLACE FUNCTION public.get_stock_workspace_cache_state()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
select case when q.value is null then null else q.value||jsonb_build_object(
   'mrn',(q.value->>'mrn')||':supply:'||stock_management_private.supply_version(),
   'expiry',(q.value->>'expiry')||':supply:'||stock_management_private.supply_version(),
   'details',(q.value->>'details')||':supply:'||stock_management_private.supply_version()) end
 from (
with revisions as materialized (
    select source,revision::text revision from public.stock_workspace_cache_revisions
  ), versions as (
    select string_agg(source||':'||revision,',' order by source) all_versions,
      string_agg(source||':'||revision,',' order by source)
        filter(where source in ('mrn_snapshot','mrn_receipts')) mrn_version
    from revisions having count(*)=6
  ), day as (select (now() at time zone 'Asia/Dubai')::date::text today)
  select jsonb_build_object(
    'mrn','w2:'||today||':'||mrn_version,
    'discovery','w2:'||today||':'||mrn_version,
    'expiry','w2:'||today||':'||all_versions,
    'details','w2:'||today||':'||mrn_version||':'||stock_management_private.catalog_cache_version(true))
  from versions cross join day
  where (public.item_tracker_my_role()='inventory' or stock_management_private.is_view_user() or current_user='service_role')
    and has_table_privilege(current_user,'public.stock_management_snapshot','SELECT')
    and has_table_privilege(current_user,'public.mrn_apg_2026','SELECT')
    and has_table_privilege(current_user,'public.stock_catalog_snapshot','SELECT')
    and has_table_privilege(current_user,'public.sales_history','SELECT')
    and has_table_privilege(current_user,'public.sales_history_2025','SELECT')
    and has_table_privilege(current_user,'public.branches','SELECT')
    and has_table_privilege(current_user,'public.stock_expiry_alert_receipts','SELECT')
    and has_table_privilege(current_user,'public.stock_expiry_reviews','SELECT')
    and has_table_privilege(current_user,'public.stock_expiry_watch_state','SELECT')
    and has_table_privilege(current_user,'public.item_report','SELECT')
)q(value);
$function$;

create function stock_management_private.run_supply_job() returns void
language plpgsql security definer set search_path='' as $$
begin
  perform stock_management_private.refresh_supply_insights();
exception when others then
  update public.stock_supply_insight_state set last_error=sqlstate||': '||sqlerrm,last_attempt_at=clock_timestamp() where singleton;
end $$;
revoke all on function stock_management_private.run_supply_job() from public,anon,authenticated;
grant execute on function stock_management_private.run_supply_job() to service_role;
select cron.schedule('stock-supply-insights-refresh','7,22,37,52 * * * *',
  'select stock_management_private.run_supply_job();');
notify pgrst,'reload schema';
