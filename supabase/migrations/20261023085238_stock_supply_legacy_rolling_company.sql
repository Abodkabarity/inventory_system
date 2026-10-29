-- The ordinary APG rolling-statement uploader omits company (NULL).
-- See automation/main.py upload_stk_statement_to_supabase and
-- automation/append_statement_day.py. Archive company remains mandatory.
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
    from public.stk_statement where company='APG' or company is null;
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
      bool_or(coalesce(h.company,'APG')<>'APG') bad_company,false receipt_pending
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
        or coalesce(company,'APG')<>'APG') bad
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
