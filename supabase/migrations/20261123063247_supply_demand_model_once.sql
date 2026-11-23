-- Reuse only the immutable demand model for the exact same product input.
-- All existing JSON expressions, ordering, guards, precision and privileges remain.
-- Fail closed if a business function changed since this refactor was reviewed.
set local lock_timeout='2s';
do $guard$
declare expected record; actual text;
begin
  if to_regtype('stock_management_private.supply_enrichment_result') is not null then
    raise exception 'Supply result type already exists; review required';
  end if;
  if to_regprocedure('stock_management_private.enrich_supply_cached(jsonb,jsonb,jsonb)') is not null
    or to_regprocedure('stock_management_private.enrich_supply_reconciled_cached(jsonb,jsonb,jsonb)') is not null
    or to_regprocedure('stock_management_private.resolve_receipt_return_cached(jsonb,jsonb,jsonb)') is not null then
    raise exception 'Supply cached helper already exists; review required';
  end if;
  for expected in select * from (values
    ('stock_management_private.enrich_supply_reconciled(jsonb,jsonb)','1b189b9df47095217415daf883888c01'),
    ('stock_management_private.enrich_supply(jsonb,jsonb)','0107953d52f477ca344b8be10b913825'),
    ('stock_management_private.resolve_receipt_return(jsonb,jsonb)','076045101a29bfdba0259ef3aa3c29bc'),
    ('stock_management_private.analyze_supply(jsonb)','7827de3223387926e87dfea53ecabf8c'),
    ('stock_management_private.fit_supply_demand(jsonb)','b4f9ca9cffedb7a632172edc4291c82e')) as v(signature,body_hash) loop
    select md5(replace(prosrc,E'\r\n',E'\n')) into actual
    from pg_proc where oid=to_regprocedure(expected.signature);
    if actual is distinct from expected.body_hash then
      raise exception 'Supply definition changed; review required: %',expected.signature;
    end if;
  end loop;
end;
$guard$;

create type stock_management_private.supply_enrichment_result as (payload jsonb,demand_model jsonb);

CREATE OR REPLACE FUNCTION stock_management_private.enrich_supply_reconciled_cached(p jsonb, evidence jsonb, p_model jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare detail jsonb:=evidence->'detail'; summary jsonb:=evidence->'summary'; model jsonb;
  periods jsonb:='[]'; limited_counts jsonb:='{}'; month_rows jsonb:='[]'; r jsonb; entry jsonb; latest jsonb;
  through_day date:=(detail->>'through')::date; start_day date:=date '2026-01-02';
  d date; shortage_from date; until_day date; recovery_day date; last_day date:=date '2026-01-01';
  balance numeric:=(detail->>'opening_qty')::numeric; next_balance numeric; incoming numeric;
  entry_qty numeric; recovery_qty numeric; lower_bound boolean:=false; gap_age interval; days integer;
  small_count integer:=0; small_qty numeric:=0; adjusted boolean:=false; effective jsonb; thin jsonb;
begin
  if coalesce(summary->>'confidence','unavailable') not in ('verified','inferred') then
    effective:=jsonb_build_object('status','history_required');
    return jsonb_build_object('summary',summary||jsonb_build_object('effective_supply',effective),
      'detail',detail||jsonb_build_object('effective_supply',effective)); end if;
  model:=coalesce(p_model,stock_management_private.fit_supply_demand(p));
  if model->>'status'<>'ready' then
    effective:=jsonb_build_object('status','insufficient_history','model',model);
    return jsonb_build_object('summary',summary||jsonb_build_object('effective_supply',jsonb_build_object('status','insufficient_history')),
      'detail',detail||jsonb_build_object('effective_supply',effective)); end if;
  entry_qty:=(model->>'entry_qty')::numeric;recovery_qty:=(model->>'recovery_qty')::numeric;
  if balance<entry_qty then shortage_from:=start_day;lower_bound:=true; end if;
  for r in select value from jsonb_array_elements(coalesce(p->'days','[]')) order by value->>'date' loop
    d:=(r->>'date')::date;
    if d<start_day or d>through_day then continue; end if;
    incoming:=coalesce((r->>'incoming')::numeric,0);next_balance:=balance+coalesce((r->>'net')::numeric,0);
    -- A small incoming quantity never resets a shortage spell. Restore only
    -- with enough recorded closing stock for the learned recovery cover.
    if shortage_from is not null then
      adjusted:=adjusted or coalesce((r->>'adjustment')::boolean,false);
      if next_balance>=recovery_qty and incoming>0 and not coalesce((r->>'adjustment')::boolean,false)
        and (not adjusted or incoming>=recovery_qty) then
        gap_age:=age(d::timestamp,shortage_from::timestamp);days:=d-shortage_from;
        periods:=periods||jsonb_build_array(jsonb_build_object('from',shortage_from,'through',d-1,'returned_at',d,
          'days',days,'months',extract(year from gap_age)::integer*12+extract(month from gap_age)::integer,
          'remaining_days',extract(day from gap_age)::integer,'at_least',lower_bound,
          'received_qty',incoming,'closing_qty',next_balance,'small_arrivals',small_count,'small_arrival_qty',small_qty,
          'adjusted',adjusted));
        shortage_from:=null;lower_bound:=false;small_count:=0;small_qty:=0;adjusted:=false;
      elsif incoming>0 and incoming<recovery_qty then small_count:=small_count+1;small_qty:=small_qty+incoming;
      end if;
    end if;
    if shortage_from is null and next_balance<entry_qty then
      shortage_from:=d+1;lower_bound:=false;small_count:=0;small_qty:=0;
      adjusted:=coalesce((r->>'adjustment')::boolean,false);
    end if;
    balance:=next_balance;last_day:=d;
  end loop;
  if shortage_from is not null and shortage_from<=through_day then
    gap_age:=age((through_day+1)::timestamp,shortage_from::timestamp);
    periods:=periods||jsonb_build_array(jsonb_build_object('from',shortage_from,'through',through_day,'returned_at',null,
      'days',through_day-shortage_from+1,'months',extract(year from gap_age)::integer*12+extract(month from gap_age)::integer,
      'remaining_days',extract(day from gap_age)::integer,'at_least',lower_bound,'received_qty',null,
      'small_arrivals',small_count,'small_arrival_qty',small_qty,'adjusted',adjusted));
  end if;
  for entry in select value from jsonb_array_elements(periods) loop
    limited_counts:=stock_management_private.add_supply_days(limited_counts,(entry->>'from')::date,(entry->>'through')::date,'limited');
  end loop;
  for r in select value from jsonb_array_elements(coalesce(detail->'monthly','[]')) loop
    month_rows:=month_rows||jsonb_build_array(r||jsonb_build_object('limited_days',coalesce((limited_counts->(r->>'month')->>'limited')::integer,0)));
  end loop;
  select value into latest from jsonb_array_elements(periods) where (value->>'days')::integer>=30 or value->>'returned_at' is null order by value->>'from' desc limit 1;
  effective:=jsonb_build_object('status',case
      when shortage_from is not null and shortage_from<=through_day then 'limited_supply'
      when latest is not null and (latest->>'returned_at')::date>=coalesce((p->>'today')::date,through_day)-30 then 'supply_restored'
      else 'adequate_supply' end,
    'confidence','estimated','scope','STORE supply capacity; branch availability is not confirmed',
    'model',model,'latest_period',latest,'periods',periods);
  thin:=(effective-'periods'-'model')||jsonb_build_object('daily_qty',model->'daily_qty','recovery_qty',recovery_qty);
  return jsonb_build_object('summary',summary||jsonb_build_object('effective_supply',thin),
    'detail',detail||jsonb_build_object('effective_supply',effective,'monthly',month_rows));
end $function$;

CREATE OR REPLACE FUNCTION stock_management_private.enrich_supply_cached(p jsonb, evidence jsonb, p_model jsonb)
 RETURNS stock_management_private.supply_enrichment_result
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare result jsonb; cached_model jsonb:=p_model; chart_result jsonb; effective jsonb; timeline jsonb;
  review_required boolean:=false; arrivals jsonb:='[]'; receipt jsonb; movement jsonb; period jsonb;
  restored boolean; d date; qty numeric; recovery numeric;
begin
  result:=stock_management_private.enrich_supply_reconciled_cached(p,evidence,cached_model);
  cached_model:=coalesce(cached_model,result#>'{detail,effective_supply,model}');
  chart_result:=result;
  if coalesce(evidence->'summary'->>'confidence','unavailable') not in ('verified','inferred') then
    if evidence->'detail'->'issues' is null
      or evidence->'detail'->'issues'='[]'::jsonb
      or not (evidence->'detail'->'issues' <@ '["balance_mismatch","current_stock_missing"]'::jsonb)
      or (evidence->'detail'->'issues' ? 'current_stock_missing' and
        (coalesce((p->>'current_count')::integer,-1)<>0 or p->>'stock_day' is null))
      then return (result, cached_model)::stock_management_private.supply_enrichment_result; end if;
    review_required:=true;
    chart_result:=stock_management_private.enrich_supply_reconciled_cached(p,
      jsonb_set(evidence,'{summary,confidence}','"inferred"'),cached_model);
    cached_model:=coalesce(cached_model,chart_result#>'{detail,effective_supply,model}');
  end if;
  effective:=chart_result->'detail'->'effective_supply';
  if effective->>'status' not in ('limited_supply','supply_restored','adequate_supply') then return (result, cached_model)::stock_management_private.supply_enrichment_result; end if;
  recovery:=(effective->'model'->>'recovery_qty')::numeric;
  -- p.mrns is already grouped by physical STORE receipt date. Require matching
  -- movement evidence too: virtual or unposted receipts are not replenishment.
  for receipt in select value from jsonb_array_elements(coalesce(p->'mrns','[]')) order by value->>'date' loop
    d:=(receipt->>'date')::date; qty:=coalesce((receipt->>'qty')::numeric,0);
    if qty<=0 or d>(evidence->'detail'->>'through')::date then continue; end if;
    select value into movement from jsonb_array_elements(coalesce(p->'days','[]')) where value->>'date'=d::text limit 1;
    if movement is null or coalesce((movement->>'adjustment')::boolean,false)
      or abs(coalesce((movement->>'mrn_qty')::numeric,0)-qty)>0.000001 then continue; end if;
    select value into period from jsonb_array_elements(effective->'periods')
      where d>=(value->>'from')::date
        and d<=coalesce((value->>'returned_at')::date,(value->>'through')::date)
        and (value->>'days')::integer>=30
      order by value->>'from' desc limit 1;
    if period is null then continue; end if;
    restored:=period->>'returned_at'=d::text;
    arrivals:=arrivals||jsonb_build_array(jsonb_build_object('date',d,'qty',qty,
      'kind',case when restored then 'restored' else 'limited' end,
      'mrn_numbers',receipt->'numbers','recovery_qty',recovery));
  end loop;
  timeline:=jsonb_build_object('confidence','estimated','review_required',review_required,
    'scope','STORE supply; branch availability is separate',
    'periods',effective->'periods','arrivals',arrivals);
  return (jsonb_set(result,'{detail,chart_timeline}',timeline), cached_model)::stock_management_private.supply_enrichment_result;
end $function$;

CREATE OR REPLACE FUNCTION stock_management_private.resolve_receipt_return_cached(p jsonb, evidence jsonb, p_model jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  s jsonb:=evidence->'summary'; detail jsonb:=evidence->'detail'; result jsonb;
  omitted boolean:=coalesce((p->>'current_count')::integer,-1)=0 and p->>'current_qty' is null;
  explicit_zero boolean:=coalesce((p->>'current_count')::integer,-1)=1 and (p->>'current_qty')::numeric=0;
  through_day date:=(p->>'through')::date; stock_day date:=(p->>'stock_day')::date;
  today date:=coalesce((p->>'today')::date,stock_day,through_day);
  endpoint jsonb; receipt jsonb; movement jsonb; period jsonb; raw_event jsonb;
  receipt_day date; gap_from date; gap_days integer; qty numeric; daily numeric; recovery numeric;
  coverage text; assessment jsonb; effective jsonb; model jsonb; periods jsonb; revised jsonb;
  age_gap interval; known boolean;
begin
  if not (omitted or coalesce(explicit_zero,false)) then return evidence; end if;
  if omitted and not coalesce((p->>'current_report_present')::boolean,false) then return evidence; end if;
  if stock_day is null or through_day is null or stock_day<through_day
    or (stock_day>through_day and (coalesce((p->>'bridge_through')::date,date '1900-01-01')<stock_day
      or coalesce((p->>'bridge_bad')::boolean,false))) then return evidence; end if;
  if detail->'issues' is null or not (detail->'issues' <@ '["current_stock_missing","balance_mismatch"]'::jsonb)
    then return evidence; end if;

  endpoint:=jsonb_build_object('current_qty_basis',case when omitted then 'omitted_means_zero' else 'recorded' end,
    'current_report_present',true,'endpoint_inferred',true,'current_qty',0,'stock_day',stock_day);
  s:=s||endpoint||jsonb_build_object('status','store_empty','confidence','inferred',
    'gap_days',null,'returned_at',null,'received_qty',null);
  detail:=detail||s||jsonb_build_object('issues','[]'::jsonb,'daily_precision',false,
    'endpoint_difference',coalesce((detail->>'history_qty')::numeric,0)
      +coalesce((p->>'bridge_net')::numeric,0));
  -- Reuse the existing bounded, per-product demand model and historical chart.
  result:=(stock_management_private.enrich_supply_cached(
    p,jsonb_build_object('summary',s,'detail',detail),p_model)).payload;
  effective:=result->'detail'->'effective_supply'; model:=effective->'model';
  if model->>'status'='ready' then
    daily:=(model->>'daily_qty')::numeric; recovery:=(model->>'recovery_qty')::numeric;
  end if;

  for receipt in select value from jsonb_array_elements(coalesce(p->'mrns','[]'::jsonb))
    where (value->>'date')::date between today-30 and least(stock_day,through_day)
      and coalesce((value->>'qty')::numeric,0)>0 order by value->>'date' desc loop
    receipt_day:=(receipt->>'date')::date; qty:=(receipt->>'qty')::numeric;
    known:=coalesce((p->>'prior_sales')::numeric,0)>0 or coalesce((p->>'opening_qty')::numeric,0)>0
      or exists(select 1 from jsonb_array_elements(coalesce(p->'monthly_sales','[]'::jsonb)) m
        where m->>'month' ~ '^(0[1-9]|1[0-2])/[0-9]{4}$'
          and to_date(m->>'month','MM/YYYY')<date_trunc('month',receipt_day)::date
          and coalesce((m->>'total')::numeric,0)>0);
    if not known then continue; end if;
    select value into movement from jsonb_array_elements(coalesce(p->'days','[]'::jsonb))
      where value->>'date'=receipt_day::text limit 1;
    if movement is null or coalesce((movement->>'adjustment')::boolean,false)
      or abs(coalesce((movement->>'mrn_qty')::numeric,0)-qty)>0.000001 then continue; end if;
    select value into period from jsonb_array_elements(coalesce(effective->'periods','[]'::jsonb))
      where receipt_day>=(value->>'from')::date
        and receipt_day<=coalesce((value->>'returned_at')::date,(value->>'through')::date)
        and receipt_day-(value->>'from')::date>=30
      order by value->>'from' desc limit 1;
    select value into raw_event from jsonb_array_elements(coalesce(detail->'events','[]'::jsonb))
      where value->>'returned_at'=receipt_day::text and (value->>'days')::integer>=30
        and coalesce((value->>'established')::boolean,false) and coalesce((value->>'mrn_linked')::boolean,false)
      limit 1;
    gap_from:=coalesce((period->>'from')::date,(raw_event->>'from')::date);
    if gap_from is null then continue; end if;
    gap_days:=receipt_day-gap_from;
    age_gap:=age(receipt_day::timestamp,gap_from::timestamp);
    coverage:=case when daily>0 and recovery>0 then case when qty>=recovery then 'enough' else 'limited' end else 'unknown' end;
    assessment:=jsonb_build_object('returned_at',receipt_day,'received_qty',qty,'from',gap_from,
      'gap_days',gap_days,'days',gap_days,
      'months',extract(year from age_gap)::integer*12+extract(month from age_gap)::integer,
      'remaining_days',extract(day from age_gap)::integer,
      'at_least',coalesce((period->>'at_least')::boolean,(raw_event->>'at_least')::boolean,false),
      'coverage',coverage,'daily_qty',daily,'recovery_qty',recovery,
      'receipt_cover_days',case when daily>0 then round(qty/daily,2) end,
      'branches_qty',p->'branches_qty','basis','MRN and prior product history; arrival capacity is separate from current STORE stock');
    exit;
  end loop;

  if assessment is not null then
    -- Same-day distribution must not erase a meaningful arrival or extend the
    -- old supply gap past a sufficient receipt. Its date remains estimated.
    if coverage='enough' and period is not null and period->>'returned_at' is null then
      age_gap:=age(receipt_day::timestamp,gap_from::timestamp);
      revised:=period||jsonb_build_object('through',receipt_day-1,'returned_at',receipt_day,
        'days',gap_days,'months',extract(year from age_gap)::integer*12+extract(month from age_gap)::integer,
        'remaining_days',extract(day from age_gap)::integer,'received_qty',qty,'arrival_capacity_basis',true);
      select coalesce(jsonb_agg(case when value->>'from'=period->>'from' then revised else value end order by value->>'from'),'[]'::jsonb)
        into periods from jsonb_array_elements(effective->'periods');
      effective:=effective||jsonb_build_object('periods',periods,'latest_period',revised);
      result:=jsonb_set(result,'{detail,effective_supply}',effective);
      if result->'detail'->'chart_timeline' is not null then
        result:=jsonb_set(result,'{detail,chart_timeline,periods}',periods);
        select coalesce(jsonb_agg(case when value->>'date'=receipt_day::text then value||'{"kind":"restored"}'::jsonb else value end order by value->>'date'),'[]'::jsonb)
          into periods from jsonb_array_elements(result->'detail'->'chart_timeline'->'arrivals');
        result:=jsonb_set(result,'{detail,chart_timeline,arrivals}',periods);
      end if;
    end if;
    s:=(result->'summary')||jsonb_build_object('status','back_in_store','confidence','inferred',
      'returned_at',receipt_day,'received_qty',qty,'gap_days',gap_days,'at_least',assessment->'at_least',
      'return_assessment',assessment);
  else
    s:=(result->'summary')||jsonb_build_object('status','store_empty','confidence','inferred');
  end if;
  -- The model still carries historical periods/demand. Current STORE zero is
  -- not labelled healthy or limited solely because stock was once received.
  effective:=coalesce(result->'detail'->'effective_supply','{}'::jsonb)
    ||jsonb_build_object('status','current_store_empty');
  result:=jsonb_set(result,'{summary}',s||jsonb_build_object('effective_supply',
    (coalesce(s->'effective_supply','{}'::jsonb)-'latest_period')||'{"status":"current_store_empty"}'::jsonb));
  result:=jsonb_set(result,'{detail}',(result->'detail')||(result->'summary')
    ||jsonb_build_object('effective_supply',effective));
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION stock_management_private.enrich_supply_reconciled(p jsonb, evidence jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
  return stock_management_private.enrich_supply_reconciled_cached(p,evidence,null);
end;
$function$;

CREATE OR REPLACE FUNCTION stock_management_private.enrich_supply(p jsonb, evidence jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
  return (stock_management_private.enrich_supply_cached(p,evidence,null)).payload;
end;
$function$;

CREATE OR REPLACE FUNCTION stock_management_private.resolve_receipt_return(p jsonb, evidence jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
  return stock_management_private.resolve_receipt_return_cached(p,evidence,null);
end;
$function$;

CREATE OR REPLACE FUNCTION stock_management_private.analyze_supply(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  enriched stock_management_private.supply_enrichment_result;
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
    'gap_days',case when state='back_in_store' then latest->'days' when state='store_empty' and established then to_jsonb(greatest(through_day-zero_from+1,0)) end,
    'at_least',case when state='back_in_store' then (latest->>'at_least')::boolean else lower_bound end,
    'returned_at',case when state='back_in_store' then latest->'returned_at' end,
    'received_qty',case when state='back_in_store' then latest->'received_qty' end);
  result:=summary||jsonb_build_object('opening_date',baseline_day,'opening_qty',case when assumed then '0'::jsonb else p->'opening_qty' end,
    'current_qty',current_qty,'stock_day',stock_day,'history_qty',end_qty,
    'issues',to_jsonb(issues),'established_from',established_from,'monthly',months,'events',events,
    'source','stock_statement_and_ledger','daily_precision',not provisional,
    'sales_scope','All source branches; STORE availability is a separate scope',
    'forecast_status','branch_availability_required','sales_through',p->'sales_through');
  enriched:=stock_management_private.enrich_supply_cached(
    p,jsonb_build_object('summary',summary,'detail',result),null);
  return stock_management_private.resolve_receipt_return_cached(p,enriched.payload,enriched.demand_model);
end $function$;

revoke all on function stock_management_private.enrich_supply_reconciled_cached(jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function stock_management_private.enrich_supply_reconciled_cached(jsonb,jsonb,jsonb) to service_role;
revoke all on function stock_management_private.enrich_supply_cached(jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function stock_management_private.enrich_supply_cached(jsonb,jsonb,jsonb) to service_role;
revoke all on function stock_management_private.resolve_receipt_return_cached(jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function stock_management_private.resolve_receipt_return_cached(jsonb,jsonb,jsonb) to service_role;
revoke all on type stock_management_private.supply_enrichment_result from public,anon,authenticated;
grant usage on type stock_management_private.supply_enrichment_result to service_role;
