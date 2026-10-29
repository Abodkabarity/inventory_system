create or replace function stock_management_private.enrich_supply_reconciled(p jsonb,evidence jsonb)
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
revoke all on function stock_management_private.enrich_supply_reconciled(jsonb,jsonb) from public,anon,authenticated;
grant execute on function stock_management_private.enrich_supply_reconciled(jsonb,jsonb) to service_role;

-- Keep verified summaries unchanged. A sole endpoint balance mismatch may keep
-- its reconstructed historical timeline, explicitly marked as needing review.
-- Missing openings, negative balances and ambiguous movements remain excluded.
create or replace function stock_management_private.enrich_supply(p jsonb,evidence jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb; chart_result jsonb; effective jsonb; timeline jsonb;
  review_required boolean:=false; arrivals jsonb:='[]'; receipt jsonb; movement jsonb; period jsonb;
  restored boolean; d date; qty numeric; recovery numeric;
begin
  result:=stock_management_private.enrich_supply_reconciled(p,evidence);
  chart_result:=result;
  if coalesce(evidence->'summary'->>'confidence','unavailable') not in ('verified','inferred') then
    if evidence->'detail'->'issues'<>'["balance_mismatch"]'::jsonb
      or evidence->'detail'->'issues' is null then return result; end if;
    review_required:=true;
    chart_result:=stock_management_private.enrich_supply_reconciled(p,
      jsonb_set(evidence,'{summary,confidence}','"inferred"'));
  end if;
  effective:=chart_result->'detail'->'effective_supply';
  if effective->>'status' not in ('limited_supply','supply_restored','adequate_supply') then return result; end if;
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
  return jsonb_set(result,'{detail,chart_timeline}',timeline);
end $$;
revoke all on function stock_management_private.enrich_supply(jsonb,jsonb) from public,anon,authenticated;
grant execute on function stock_management_private.enrich_supply(jsonb,jsonb) to service_role;


