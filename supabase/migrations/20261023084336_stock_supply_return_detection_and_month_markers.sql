-- STORE availability v2: explicit business assumption, recent receipt evidence,
-- and monthly context. Raw ledgers and movements remain unchanged.
create or replace function stock_management_private.analyze_supply(p jsonb)
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
  assumed boolean:=false; provisional boolean:=coalesce((p->>'provisional')::boolean,false);
  established_from date;
  eps constant numeric:=0.000001;
begin
  if through_day is null or through_day<=baseline_day then issues:=array_append(issues,'history_missing'); end if;
  if coalesce((p->>'baseline_count')::integer,0)=0
    and coalesce((p->>'raw_opening_count')::integer,0)=0
    and coalesce((p->>'assume_missing_opening')::boolean,false) then
    -- Business rule: an omitted item in a validated opening report is assumed
    -- zero for analysis only. Never alter the raw opening or call it verified.
    balance:=0; assumed:=true;
  elsif coalesce((p->>'baseline_count')::integer,0)<>1 then issues:=array_append(issues,'opening_missing');
  else
    balance:=(p->>'opening_qty')::numeric;
    if balance is null then issues:=array_append(issues,'opening_missing'); end if;
  end if;
  if coalesce((p->>'bad_company')::boolean,false) then issues:=array_append(issues,'company_mismatch'); end if;
  if coalesce((p->>'opening_movements')::integer,0)>0 then issues:=array_append(issues,'opening_boundary'); end if;
  valid:=cardinality(issues)=0;
  if valid then
    established:=balance>eps or coalesce((p->>'prior_sales')::numeric,0)>0;
    if established then established_from:=baseline_day+1; end if;
    if abs(balance)<=eps then balance:=0; zero_from:=baseline_day+1; lower_bound:=true; end if;
    if balance<0 then issues:=array_append(issues,'negative_balance'); end if;
    for row in select value from jsonb_array_elements(coalesce(p->'days','[]')) order by value->>'date' loop
      d:=(row->>'date')::date;
      if d<=baseline_day or d>through_day then continue; end if;
      if d<=last_day then raise exception 'Supply movement days must be unique and ordered'; end if;
      counts:=stock_management_private.add_supply_days(counts,last_day+1,d-1,
        case when balance>eps then 'available' when abs(balance)<=eps and established then 'empty' else 'unknown' end);
      if coalesce((row->>'bad_sign')::boolean,false) then issues:=array_append(issues,'movement_sign'); end if;
      if coalesce((row->>'bad_company')::boolean,false) then issues:=array_append(issues,'company_mismatch'); end if;
      next_balance:=balance+coalesce((row->>'net')::numeric,0);
      if abs(next_balance)<=eps then next_balance:=0; end if;
      if next_balance<0 then issues:=array_append(issues,'negative_balance'); end if;
      counts:=stock_management_private.add_supply_days(counts,d,d,
        case when balance>eps and next_balance>eps and not coalesce((row->>'adjustment')::boolean,false) then 'available'
          when balance=0 and next_balance=0 and coalesce((row->>'incoming')::numeric,0)=0
            and not coalesce((row->>'adjustment')::boolean,false) and established then 'empty' else 'partial' end);
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
      if not established and next_balance>eps then established_from:=d; end if;
      established:=established or next_balance>eps;
      balance:=next_balance; last_day:=d;
    end loop;
    counts:=stock_management_private.add_supply_days(counts,last_day+1,through_day,
      case when balance>eps then 'available' when balance=0 and established then 'empty' else 'unknown' end);
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
  if confidence='verified' and (assumed or provisional) then confidence:='inferred'; end if;
  summary:=jsonb_build_object('status',state,'confidence',confidence,'scope','STORE','through',through_day,
    'opening_basis',case when assumed then 'assumed_zero' else 'recorded' end,
    'provisional',provisional,'archived_through',p->'archived_through',
    'gap_days',case when state='back_in_store' then latest->'days' when state='store_empty' then to_jsonb(greatest(through_day-zero_from+1,0)) end,
    'at_least',case when state='back_in_store' then (latest->>'at_least')::boolean else lower_bound end,
    'returned_at',case when state='back_in_store' then latest->'returned_at' end,
    'received_qty',case when state='back_in_store' then latest->'received_qty' end);
  result:=summary||jsonb_build_object('opening_date',baseline_day,'opening_qty',case when assumed then '0'::jsonb else p->'opening_qty' end,
    'current_qty',current_qty,'stock_day',stock_day,'history_qty',end_qty,
    'issues',to_jsonb(issues),'established_from',established_from,'monthly',months,'events',events,
    'source','stock_statement_and_ledger','daily_precision',not provisional,
    'sales_scope','All source branches; STORE availability is a separate scope',
    'forecast_status','branch_availability_required','sales_through',p->'sales_through');
  return jsonb_build_object('summary',summary,'detail',result);
end $$;
revoke all on function stock_management_private.analyze_supply(jsonb) from public,anon,authenticated;
grant execute on function stock_management_private.analyze_supply(jsonb) to service_role;


create or replace function stock_management_private.refresh_supply_insights(p_force boolean default false)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='240s' set enable_nestloop='off' as $$
declare v_archive date:=date '2025-12-31'; v_through date; period record; version text; n integer;
  v_stock_day date; v_bridge_through date; v_rolling_from date; expected integer; v_opening_report boolean;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('stock-supply-insights',0)) then
    return jsonb_build_object('status','already_running'); end if;
  for period in select * from public.stk_statement_history_load_progress where company='APG' order by from_date loop
    if period.complete and period.committed_rows=period.expected_rows and period.from_date<=v_archive+1 then
      v_archive:=greatest(v_archive,period.to_date); end if;
  end loop;
  v_archive:=least(v_archive,(now() at time zone 'Asia/Dubai')::date-1);
  select (max(created_at) at time zone 'Asia/Dubai')::date into v_stock_day from public.stk_ledger;
  select min(trans_date),max(trans_date) into v_rolling_from,v_bridge_through
    from public.stk_statement where company='APG';
  v_through:=v_archive;
  -- No date overlap: archive wins through its validated cutoff. Rolling evidence
  -- is provisional, bounded by the ledger day and never includes today's part-day.
  if v_archive>=date '2026-01-01' and v_rolling_from<=v_archive+1 and v_bridge_through>v_archive then
    v_through:=greatest(v_archive,least(v_stock_day,v_bridge_through,(now() at time zone 'Asia/Dubai')::date-1));
  end if;
  select exists(select 1 from public.stk_ledger_history where stock_date='2026-01-01'
    and report_from_date=stock_date and report_to_date=stock_date and branch_name='STORE'
    and not source_branch_missing and company in ('APG','Al Ain Pharmacy Group (APG)')) into v_opening_report;
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
      bool_or(b.company not in ('APG','Al Ain Pharmacy Group (APG)') or b.company is null) bad_company
    from public.stk_ledger_history b join tracked t using(item_code)
    where b.stock_date='2026-01-01' and b.report_from_date=b.stock_date and b.report_to_date=b.stock_date
      and b.branch_name='STORE' and not b.source_branch_missing group by b.item_code
  ), raw_opening as materialized (
    select b.item_code,count(*) n from public.stk_ledger_history b join tracked t using(item_code)
    where b.stock_date='2026-01-01' and b.branch_name='STORE' group by b.item_code
  ), receipts as materialized (
    select btrim(item_code) item_code,mrn_date,sum(coalesce(received_quantity,0)) qty,
      jsonb_agg(distinct coalesce(mrn_no,'')) numbers
    from public.mrn_apg_2026 where lower(btrim(status))='approved' and lower(btrim(warehouse))='store'
      and mrn_date>date '2026-01-01' and mrn_date<=v_through group by btrim(item_code),mrn_date
  ), archive_days as materialized (
    select h.item_code,h.trans_date,sum(h.qty) net,sum(greatest(h.qty,0)) incoming,
      sum(h.qty) filter(where lower(btrim(h.trans_type))='mrn') mrn_qty,
      bool_or(lower(btrim(h.trans_type))='invadjustment') adjustment,
      bool_or(lower(btrim(h.mode)) not in ('in','out') or h.mode is null or h.qty is null
        or (lower(btrim(h.mode))='in' and h.qty<0) or (lower(btrim(h.mode))='out' and h.qty>0)) bad_sign,
      bool_or(h.company<>'APG' or h.company is null) bad_company,false receipt_pending
    from public.stk_statement_history_2026 h join tracked t using(item_code)
    where h.branch_name='STORE' and h.trans_date between date '2026-01-01' and v_archive
      and (h.qty<>0 or h.qty is null) group by h.item_code,h.trans_date
  ), rolling_days as materialized (
    select h.item_code,h.trans_date,sum(h.qty) net,sum(greatest(h.qty,0)) incoming,
      -- Rolling rows have no transaction type. Correlate a receipt only when
      -- all positive movement equals the full approved physical-STORE MRN sum.
      case when abs(sum(greatest(h.qty,0))-coalesce(max(r.qty),0))<=0.000001 then max(r.qty) else 0 end mrn_qty,
      false adjustment,
      bool_or(lower(btrim(h.mode)) not in ('in','out') or h.mode is null or h.qty is null
        or (lower(btrim(h.mode))='in' and h.qty<0) or (lower(btrim(h.mode))='out' and h.qty>0)) bad_sign,
      bool_or(h.company<>'APG' or h.company is null) bad_company,false receipt_pending
    from public.stk_statement h join tracked t using(item_code)
    left join receipts r on r.item_code=h.item_code and r.mrn_date=h.trans_date
    where h.branch_name='STORE' and h.trans_date>v_archive and h.trans_date<=v_through
    group by h.item_code,h.trans_date
  ), pending_receipts as materialized (
    -- MRN can arrive before the rolling statement. Use it provisionally only
    -- outside the archive, with NO same-day statement row for this item.
    -- Endpoint reconciliation below must independently match today's raw ledger.
    select r.item_code,r.mrn_date trans_date,r.qty net,r.qty incoming,r.qty mrn_qty,
      false adjustment,false bad_sign,false bad_company,true receipt_pending
    from receipts r join tracked t using(item_code)
    where r.mrn_date>v_archive and r.qty>0
      and not exists(select 1 from rolling_days d where d.item_code=r.item_code and d.trans_date=r.mrn_date)
  ), days as materialized (
    select * from archive_days union all select * from rolling_days union all select * from pending_receipts
  ), moves as materialized (
    select item_code,jsonb_agg(jsonb_build_object('date',trans_date,'net',net,'incoming',incoming,
      'mrn_qty',coalesce(mrn_qty,0),'adjustment',adjustment,'bad_sign',bad_sign,'bad_company',bad_company,
      'receipt_pending',receipt_pending) order by trans_date) filter(where trans_date>date '2026-01-01') days,
      count(*) filter(where trans_date=date '2026-01-01') opening_movements,
      bool_or(receipt_pending) receipt_pending
    from days group by item_code
  ), current_stock as materialized (
    select item_code,count(*) n,min(actual_qty) qty from public.stk_ledger where branch_name='STORE' group by item_code
  ), bridge as materialized (
    select item_code,sum(qty) net,
      bool_or(qty is null or lower(btrim(mode)) not in ('in','out') or mode is null
        or (lower(btrim(mode))='in' and qty<0) or (lower(btrim(mode))='out' and qty>0)
        or company<>'APG' or company is null) bad
    from public.stk_statement where branch_name='STORE' and trans_date>v_through and trans_date<=v_stock_day
    group by item_code
  ), mrns as materialized (
    select item_code,jsonb_agg(jsonb_build_object('date',mrn_date,'qty',qty,'numbers',numbers) order by mrn_date) mrns
    from receipts group by item_code
  ), analyzed as materialized (
    select t.item_code,stock_management_private.analyze_supply(jsonb_build_object(
      'through',case when v_through>=date '2026-01-01' then v_through end,'archived_through',v_archive,
      'today',(now() at time zone 'Asia/Dubai')::date,
      'baseline_count',coalesce(o.n,0),'raw_opening_count',coalesce(ro.n,0),'assume_missing_opening',v_opening_report,
      'opening_qty',o.qty,'bad_company',coalesce(o.bad_company,false),
      'provisional',v_through>v_archive or coalesce(m.receipt_pending,false),
      'opening_movements',coalesce(m.opening_movements,0),'days',coalesce(m.days,'[]'::jsonb),
      'current_count',coalesce(s.n,0),'current_qty',s.qty,'stock_day',v_stock_day,
      'bridge_through',v_bridge_through,'bridge_net',coalesce(b.net,0),'bridge_bad',coalesce(b.bad,false),
      'mrns',coalesce(r.mrns,'[]'::jsonb),
      'monthly_sales',case when jsonb_typeof(t.payload->'monthly_sales')='array' then t.payload->'monthly_sales' else '[]'::jsonb end,
      'sales_through',t.payload->'meta'->'demand_through',
      'prior_sales',coalesce(t.payload->'years'->'2025'->'total','0'::jsonb))) result
    from tracked t left join opening o using(item_code) left join raw_opening ro using(item_code) left join moves m using(item_code)
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
