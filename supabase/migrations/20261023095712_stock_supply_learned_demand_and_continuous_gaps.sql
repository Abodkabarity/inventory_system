-- Learned per-product demand baseline with chronological validation. Factual
-- zero-stock evidence remains intact; effective supply gaps are always estimates.
create or replace function stock_management_private.fit_supply_demand(p jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare qs numeric[]; ds integer[]; stamps date[]; n integer; positives integer; i integer;
  mean_rate numeric; recent_rate numeric; median_rate numeric; actual numeric;
  mean_error numeric:=0; recent_error numeric:=0; median_error numeric:=0;
  best_error numeric; holdout_error numeric:=0; holdout_benchmark numeric:=0; predicted numeric; best text:='historical_mean'; rate numeric; train_end date:=date '2026-01-01';
begin
  with rows as (
    select to_date(r->>'month','MM/YYYY') d,greatest((r->>'total')::numeric,0) qty
    from jsonb_array_elements(coalesce(p->'monthly_sales','[]'))r
    where r->>'month' ~ '^(0[1-9]|1[0-2])/[0-9]{4}$' and r->>'total' is not null
  ), training as (
    select *,(d+interval '1 month')::date-d num_days from rows
    where d>=train_end-interval '1 year' and d<train_end
  ) select array_agg(qty order by d),array_agg(num_days order by d),array_agg(d order by d),count(*),count(*) filter(where qty>0)
    into qs,ds,stamps,n,positives from training;
  if n<6 or positives<3 then
    return jsonb_build_object('status','insufficient_history','months',n,'positive_months',positives); end if;
  if (select count(distinct x) from unnest(stamps)x)<>n then
    return jsonb_build_object('status','ambiguous_history'); end if;
  -- Each validation prediction sees only earlier months. Current-year low sales
  -- during a suspected shortage cannot train the old demand baseline downwards.
  for i in 4..(n-2) loop
    select sum(qs[j])/sum(ds[j]) into mean_rate from generate_series(1,i-1)j;
    select sum(qs[j])/sum(ds[j]) into recent_rate from generate_series(i-3,i-1)j;
    select percentile_cont(.5) within group(order by (qs[j]/ds[j])::double precision)::numeric
      into median_rate from generate_series(1,i-1)j;
    actual:=qs[i];
    mean_error:=mean_error+abs(mean_rate*ds[i]-actual);
    recent_error:=recent_error+abs(recent_rate*ds[i]-actual);
    median_error:=median_error+abs(median_rate*ds[i]-actual);
  end loop;
  mean_error:=mean_error/(n-5);recent_error:=recent_error/(n-5);median_error:=median_error/(n-5);
  best_error:=mean_error;
  if recent_error<best_error*.98 then best:='recent_3_month_mean';best_error:=recent_error; end if;
  if median_error<best_error*.98 then best:='historical_median';best_error:=median_error; end if;
  -- Two final historical months are reserved from method selection.
  -- Refit each fixed method only on the months before its held-out prediction.
  for i in (n-1)..n loop
    select sum(qs[j])/sum(ds[j]) into mean_rate from generate_series(1,i-1)j;
    if best='recent_3_month_mean' then
      select sum(qs[j])/sum(ds[j]) into predicted from generate_series(i-3,i-1)j;
    elsif best='historical_median' then
      select percentile_cont(.5) within group(order by (qs[j]/ds[j])::double precision)::numeric
        into predicted from generate_series(1,i-1)j;
    else predicted:=mean_rate; end if;
    holdout_error:=holdout_error+abs(predicted*ds[i]-qs[i]);
    holdout_benchmark:=holdout_benchmark+abs(mean_rate*ds[i]-qs[i]);
  end loop;
  holdout_error:=holdout_error/2;holdout_benchmark:=holdout_benchmark/2;
  if best='recent_3_month_mean' then
    select sum(qs[j])/sum(ds[j]) into rate from generate_series(n-2,n)j;
  elsif best='historical_median' then
    select percentile_cont(.5) within group(order by (qs[j]/ds[j])::double precision)::numeric
      into rate from generate_series(1,n)j;
  else select sum(qs[j])/sum(ds[j]) into rate from generate_series(1,n)j; end if;
  if rate is null or rate<=0 then return jsonb_build_object('status','no_positive_baseline','months',n); end if;
  return jsonb_build_object('status','ready','method',best,'daily_qty',round(rate,6),
    'training_from',stamps[1],'training_through',(stamps[n]+interval '1 month'-interval '1 day')::date,
    'months',n,'validation_months',n-5,'holdout_months',2,'holdout_mae_qty',round(holdout_error,3),'holdout_benchmark_mae_qty',round(holdout_benchmark,3),'validation_mae_qty',round(best_error,3),
    'benchmark_mae_qty',round(mean_error,3),'candidate_mae_qty',jsonb_build_object(
      'historical_mean',round(mean_error,3),'recent_3_month_mean',round(recent_error,3),'historical_median',round(median_error,3)),
    'entry_cover_days',7,'recovery_cover_days',14,'entry_qty',greatest(ceil(rate*7),1),
    'recovery_qty',greatest(ceil(rate*14),1),'scope','Historical retail sales proxy for STORE supply capacity',
    'version','validated-demand-v1');
end $$;
revoke all on function stock_management_private.fit_supply_demand(jsonb) from public,anon,authenticated;
grant execute on function stock_management_private.fit_supply_demand(jsonb) to service_role;

create or replace function stock_management_private.enrich_supply(p jsonb,evidence jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
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
  model:=stock_management_private.fit_supply_demand(p);
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
end $$;
revoke all on function stock_management_private.enrich_supply(jsonb,jsonb) from public,anon,authenticated;
grant execute on function stock_management_private.enrich_supply(jsonb,jsonb) to service_role;

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
  return stock_management_private.enrich_supply(p,jsonb_build_object('summary',summary,'detail',result));
end $$;
revoke all on function stock_management_private.analyze_supply(jsonb) from public,anon,authenticated;
grant execute on function stock_management_private.analyze_supply(jsonb) to service_role;
