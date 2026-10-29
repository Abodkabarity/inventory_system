-- A current zero balance is factual; a pre-introduction interval is not a stockout.
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
  return jsonb_build_object('summary',summary,'detail',result);
end $$;
revoke all on function stock_management_private.analyze_supply(jsonb) from public,anon,authenticated;
grant execute on function stock_management_private.analyze_supply(jsonb) to service_role;


