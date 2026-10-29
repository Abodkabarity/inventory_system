-- An omitted item in an available, snapshot-aligned STORE report means zero.
-- A historical return is a separate fact from stock remaining at STORE today.
-- Keep all source receipts/movements unchanged; endpoint differences stay visible
-- as inferred metadata rather than fabricated transfers or receipt quantities.
create function stock_management_private.resolve_receipt_return(p jsonb,evidence jsonb)
returns jsonb language plpgsql immutable security invoker set search_path='' as $function$
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
  result:=stock_management_private.enrich_supply(p,jsonb_build_object('summary',s,'detail',detail));
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
revoke all on function stock_management_private.resolve_receipt_return(jsonb,jsonb) from public,anon,authenticated;
grant execute on function stock_management_private.resolve_receipt_return(jsonb,jsonb) to service_role;

do $migration$
declare body text; needle text;
begin
  body:=replace(pg_get_functiondef('stock_management_private.analyze_supply(jsonb)'::regprocedure),chr(13),'');
  needle:='return stock_management_private.enrich_supply(p,jsonb_build_object(''summary'',summary,''detail'',result));';
  if position(needle in body)=0 then raise exception 'Expected supply analysis return was not found'; end if;
  body:=replace(body,needle,'return stock_management_private.resolve_receipt_return(p,stock_management_private.enrich_supply(p,jsonb_build_object(''summary'',summary,''detail'',result)));');
  execute body;

  body:=replace(pg_get_functiondef('stock_management_private.refresh_supply_insights(boolean)'::regprocedure),chr(13),'');
  needle:='v_stock_day date;';
  if position(needle in body)=0 then raise exception 'Expected supply refresh declarations were not found'; end if;
  body:=replace(body,needle,'v_stock_day date; v_ledger_loaded_at timestamptz; v_current_report_present boolean;');
  needle:='select (max(created_at) at time zone ''Asia/Dubai'')::date into v_stock_day from public.stk_ledger;';
  if position(needle in body)=0 then raise exception 'Expected STORE report cutoff was not found'; end if;
  body:=replace(body,needle,$replacement$
  select max(created_at) into v_ledger_loaded_at from public.stk_ledger;
  v_stock_day:=(v_ledger_loaded_at at time zone 'Asia/Dubai')::date;
  -- Snapshot alignment rejects the empty/mid-load state of a report import.
  v_current_report_present:=exists(select 1 from public.stk_ledger where branch_name='STORE'
      and (created_at at time zone 'Asia/Dubai')::date=v_stock_day)
    and exists(select 1 from public.stock_management_snapshot
      where nullif(payload->'meta'->>'stock_updated_at','')::timestamptz=v_ledger_loaded_at);
  $replacement$);
  needle:='''current_count'',coalesce(s.n,0),''current_qty'',s.qty,''stock_day'',v_stock_day,';
  if position(needle in body)=0 then raise exception 'Expected current STORE parameters were not found'; end if;
  body:=replace(body,needle,needle||E'\n      ''current_report_present'',v_current_report_present,''branches_qty'',t.payload->''branches_stock'',');
  execute body;

  body:=replace(pg_get_functiondef('stock_management_private.supply_source_version()'::regprocedure),chr(13),'');
  needle:='select md5(jsonb_build_array(';
  if position(needle in body)=0 then raise exception 'Expected supply source version was not found'; end if;
  execute replace(body,needle,needle||'''receipt-return-zero-v1'',');
end;
$migration$;
