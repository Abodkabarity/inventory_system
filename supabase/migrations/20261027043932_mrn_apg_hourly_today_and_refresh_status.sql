-- Hourly imports replace only today's complete APG receipt snapshot.
create table public.mrn_apg_2026_hourly_state (
  singleton boolean primary key default true check (singleton),
  run_id uuid,
  report_date date,
  status text not null default 'idle'
    check (status in ('idle','downloading','refreshing','complete','failed')),
  attempt_started_at timestamptz,
  archive_updated_at timestamptz,
  last_rows integer,
  last_success_at timestamptz,
  last_success_report_date date,
  last_success_rows integer,
  last_error text
);
insert into public.mrn_apg_2026_hourly_state(singleton) values(true);
alter table public.mrn_apg_2026_hourly_state enable row level security;
revoke all on public.mrn_apg_2026_hourly_state from public,anon,authenticated;
grant select on public.mrn_apg_2026_hourly_state to authenticated;
grant all on public.mrn_apg_2026_hourly_state to service_role;
create policy mrn_hourly_inventory_read on public.mrn_apg_2026_hourly_state
  for select to authenticated using (
    (select public.item_tracker_my_role())='inventory'
    or (select stock_management_private.is_view_user())
  );

create function public.get_mrn_apg_2026_hourly_status()
returns jsonb language sql stable security invoker set search_path='' as $function$
  select to_jsonb(s) - 'singleton' - 'run_id' - 'last_error'
    || jsonb_build_object('has_error',s.last_error is not null)
  from public.mrn_apg_2026_hourly_state s where singleton;
$function$;
revoke all on function public.get_mrn_apg_2026_hourly_status() from public,anon;
grant execute on function public.get_mrn_apg_2026_hourly_status() to authenticated,service_role;

create function public.begin_mrn_apg_2026_hourly(p_run_id uuid,p_report_date date)
returns jsonb language plpgsql security invoker set search_path='' as $function$
declare s public.mrn_apg_2026_hourly_state;
begin
  if p_run_id is null or p_report_date is distinct from (now() at time zone 'Asia/Dubai')::date
     or extract(year from p_report_date) <> 2026 then
    raise exception 'Only today in Dubai can be imported into the 2026 archive';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(2026,9170);
  select * into strict s from public.mrn_apg_2026_hourly_state where singleton for update;
  if s.run_id=p_run_id then return to_jsonb(s); end if;
  if s.status in ('downloading','refreshing') and s.attempt_started_at > now()-interval '45 minutes' then
    raise exception 'An hourly MRN import is already running';
  end if;
  update public.mrn_apg_2026_hourly_state set run_id=p_run_id,report_date=p_report_date,
    status='downloading',attempt_started_at=clock_timestamp(),archive_updated_at=null,
    last_rows=null,last_error=null where singleton returning * into s;
  return to_jsonb(s);
end;
$function$;

create function public.replace_mrn_apg_2026_today(p_run_id uuid,p_report_date date,p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $function$
declare s public.mrn_apg_2026_hourly_state; v_base integer; v_written integer;
begin
  if p_report_date is distinct from (now() at time zone 'Asia/Dubai')::date
     or extract(year from p_report_date) <> 2026 then
    raise exception 'Hourly MRN cannot replace another day';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)>10000 then
    raise exception 'Expected an MRN array with at most 10000 rows';
  end if;
  if exists (
    select 1 from pg_catalog.jsonb_array_elements(p_rows) e(value)
    where (e.value->>'mrn_date')::date is distinct from p_report_date
       or e.value->>'status' is distinct from 'approved'
       or coalesce(e.value->>'warehouse','') not in ('store','main virtual','new virtual')
       or nullif(btrim(e.value->>'item_code'),'') is null
  ) then raise exception 'Invalid hourly MRN date, status, warehouse or product'; end if;
  perform pg_catalog.pg_advisory_xact_lock(2026,9170);
  select * into strict s from public.mrn_apg_2026_hourly_state where singleton for update;
  if s.run_id is distinct from p_run_id or s.report_date is distinct from p_report_date then
    raise exception 'Stale hourly MRN run';
  end if;
  -- A network retry must not repeat deletion or enqueue another rebuild.
  if s.archive_updated_at is not null then return to_jsonb(s); end if;
  if s.status <> 'downloading' then raise exception 'Hourly MRN run is not active'; end if;
  delete from public.mrn_apg_2026 where mrn_date=p_report_date;
  select coalesce(max(source_row_number),0) into v_base
  from public.mrn_apg_2026 where source_month=date_trunc('month',p_report_date)::date;
  insert into public.mrn_apg_2026 (
    warehouse,status,item_code,item_name,mrn_no,mrn_date,vendor,reference,
    ordered_quantity,received_quantity,expiry_date,category_1,supplier,company,
    source_month,source_row_number
  )
  select r.*,date_trunc('month',p_report_date)::date,v_base+e.n::integer
  from pg_catalog.jsonb_array_elements(p_rows) with ordinality e(value,n)
  cross join lateral pg_catalog.jsonb_to_record(e.value) r(
    warehouse text,status text,item_code text,item_name text,mrn_no text,mrn_date date,
    vendor text,reference text,ordered_quantity numeric,received_quantity numeric,
    expiry_date date,category_1 text,supplier text,company text
  );
  get diagnostics v_written=row_count;
  if v_written<>jsonb_array_length(p_rows) or (select count(*) from public.mrn_apg_2026 where mrn_date=p_report_date)<>v_written then
    raise exception 'Hourly MRN row verification failed';
  end if;
  update public.mrn_apg_2026_hourly_state set status='refreshing',last_rows=v_written,
    archive_updated_at=clock_timestamp() where singleton;
  -- The existing background queue builds Overview after this transaction commits.
  perform public.refresh_stock_management_snapshot();
  select * into s from public.mrn_apg_2026_hourly_state where singleton;
  return to_jsonb(s);
end;
$function$;

create function public.complete_mrn_apg_2026_hourly(p_run_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $function$
declare s public.mrn_apg_2026_hourly_state; r public.stock_management_refresh_state; v_snapshot timestamptz;
begin
  select * into strict s from public.mrn_apg_2026_hourly_state where singleton for update;
  if s.run_id is distinct from p_run_id then raise exception 'Stale hourly MRN completion'; end if;
  if s.status='complete' then return to_jsonb(s)||jsonb_build_object('ready',true); end if;
  if s.status<>'refreshing' then raise exception 'Hourly MRN archive is not ready'; end if;
  select * into r from public.stock_management_refresh_state where singleton;
  select max(updated_at) into v_snapshot from public.stock_management_snapshot;
  if r.status is distinct from 'complete' or v_snapshot is null or v_snapshot<s.archive_updated_at then
    return jsonb_build_object('ready',false,'refresh_failed',r.status='failed',
      'needs_refresh',r.status='complete','status',r.status);
  end if;
  -- Last success is written only after BOTH views have their refreshed sources.
  perform public.refresh_stock_expiry_watch();
  update public.mrn_apg_2026_hourly_state set status='complete',last_error=null,
    last_success_at=clock_timestamp(),last_success_report_date=report_date,
    last_success_rows=last_rows where singleton returning * into s;
  return to_jsonb(s)||jsonb_build_object('ready',true);
end;
$function$;

create function public.fail_mrn_apg_2026_hourly(p_run_id uuid,p_error text)
returns void language sql security invoker set search_path='' as $function$
  update public.mrn_apg_2026_hourly_state set status='failed',last_error=left(p_error,500)
  where singleton and run_id=p_run_id and status<>'complete';
$function$;

revoke all on function public.begin_mrn_apg_2026_hourly(uuid,date),
  public.replace_mrn_apg_2026_today(uuid,date,jsonb),public.complete_mrn_apg_2026_hourly(uuid),
  public.fail_mrn_apg_2026_hourly(uuid,text) from public,anon,authenticated;
grant execute on function public.begin_mrn_apg_2026_hourly(uuid,date),
  public.replace_mrn_apg_2026_today(uuid,date,jsonb),public.complete_mrn_apg_2026_hourly(uuid),
  public.fail_mrn_apg_2026_hourly(uuid,text) to service_role;
-- Include same-day receipts after hourly imports, retaining historical alerts.
CREATE OR REPLACE FUNCTION stock_management_private.discover_expiry_receipts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_start date; v_count integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('stock-expiry-discovery', 0));
  select receipt_start into strict v_start
  from public.stock_expiry_watch_state where singleton;
  -- Today's report is a mutable snapshot. Remove withdrawn/changed alert keys
  -- for today only; saved historical alerts and review notes remain durable.
  delete from public.stock_expiry_alert_receipts a
  where a.mrn_date=v_today and not exists (
    select 1 from public.mrn_apg_2026 m
    where m.mrn_date=v_today and btrim(m.item_code)=a.item_code
      and m.expiry_date=a.expiry_date and coalesce(m.mrn_no,'')=a.mrn_no
      and lower(btrim(m.warehouse))=a.warehouse
      and lower(btrim(m.status))='approved'
      and lower(btrim(m.warehouse)) in ('store','main virtual','new virtual')
      and m.expiry_date<(v_today+interval '6 months')::date
    group by btrim(m.item_code),m.expiry_date,coalesce(m.mrn_no,''),lower(btrim(m.warehouse))
    having sum(coalesce(m.received_quantity,0))>0
  );
  with receipts as (
    select btrim(m.item_code) item_code, m.expiry_date, m.mrn_date,
      coalesce(m.mrn_no, '') mrn_no, lower(btrim(m.warehouse)) warehouse,
      sum(m.ordered_quantity) ordered_qty,
      sum(coalesce(m.received_quantity, 0)) received_qty,
      max(m.item_name) item_name, max(m.supplier) supplier,
      max(m.company) company, max(m.category_1) category,
      min(nullif(btrim(m.vendor),'')) vendor
    from public.mrn_apg_2026 m
    where m.mrn_date between v_start and v_today
      and lower(btrim(m.status)) = 'approved'
      and lower(btrim(m.warehouse)) in ('store', 'main virtual', 'new virtual')
      and nullif(btrim(m.item_code), '') is not null
      and m.expiry_date < (least(v_today, m.mrn_date + 7) + interval '6 months')::date
    group by btrim(m.item_code), m.expiry_date, m.mrn_date,
      coalesce(m.mrn_no, ''), lower(btrim(m.warehouse))
    having sum(coalesce(m.received_quantity, 0)) > 0
  )
  insert into public.stock_expiry_alert_receipts as saved
    (item_code, expiry_date, mrn_date, mrn_no, warehouse,
     ordered_qty, received_qty, vendor, product_data)
  select r.item_code, r.expiry_date, r.mrn_date, r.mrn_no, r.warehouse,
    r.ordered_qty, r.received_qty, r.vendor,
    coalesce(s.payload, jsonb_build_object(
      'item_code', r.item_code, 'item_name', r.item_name,
      'supplier', coalesce(r.supplier, ''), 'company', coalesce(r.company, ''),
      'category', coalesce(r.category, ''), 'stock_unavailable', true,
      'last_mrn_date', r.mrn_date, 'last_mrn_no', r.mrn_no,
      'last_mrn_qty', r.received_qty))
  from receipts r
  left join public.stock_management_snapshot s on s.item_code = r.item_code
  on conflict (item_code, expiry_date, mrn_date, mrn_no, warehouse) do update
    set vendor = excluded.vendor,
        ordered_qty = excluded.ordered_qty,
        received_qty = excluded.received_qty,
        last_changed_at = clock_timestamp()
    where saved.ordered_qty is distinct from excluded.ordered_qty
       or saved.received_qty is distinct from excluded.received_qty
       or saved.vendor is distinct from excluded.vendor;
  get diagnostics v_count = row_count;
  update public.stock_expiry_watch_state
  set last_scanned_at = clock_timestamp(), scanned_through = v_today
  where singleton;
  return jsonb_build_object('changed_receipts', v_count, 'receipt_start', v_start,
    'window_from', v_today - 7, 'window_through', v_today);
end;
$function$;

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
    from public.stock_expiry_candidates c left join public.stock_expiry_receipt_reviews r
      on r.item_code=c.item_code and r.expiry_date=c.expiry_date and r.mrn_date=c.last_receipt_date
  ), filtered as materialized (
    select * from candidates c where
      (coalesce(btrim(p_search),'')='' or strpos(lower(c.item_code||' '||c.item_name||' '||c.supplier||' '||c.company),lower(btrim(p_search)))>0)
      and (p_review_state='all' or (p_review_state='reviewed' and c.is_reviewed)
        or (coalesce(p_review_state,'pending')='pending' and not c.is_reviewed))
      and (coalesce(p_urgency,'')='' or (p_urgency='near' and days_left>=0)
        or (p_urgency='expired' and days_left<0) or (p_urgency='urgent' and days_left between 0 and 30)
        or (p_urgency='soon' and days_left between 31 and 90) or (p_urgency='later' and days_left>90))
  ), paged as (
    select * from filtered order by last_receipt_date desc,expiry_date,item_name,item_code
    limit least(greatest(coalesce(p_limit,30),1),5000) offset greatest(coalesce(p_offset,0),0)
  ) select jsonb_build_object(
    'rows',coalesce((select jsonb_agg((to_jsonb(p)-'receipts') || jsonb_build_object('vendor',stock_management_private.expiry_vendor(p.item_code,p.expiry_date,p.last_receipt_date),'product_data',
        coalesce(p.product_data,'{}'::jsonb) || jsonb_build_object('added_date_time',i.added_date_time)) order by last_receipt_date desc,expiry_date,item_name,item_code) from paged p left join lateral (
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
      'window_through',(now() at time zone 'Asia/Dubai')::date,
      'receipt_start',(select receipt_start from public.stock_expiry_watch_state where singleton),
      'last_scanned_at',(select last_scanned_at from public.stock_expiry_watch_state where singleton),
      'stock_updated_at',(select max(stock_updated_at) from candidates),
      'source','mrn_apg_2026','persistent',true,'grouping','item_expiry_mrn_date','batch_stock_available',false)
  )
)q(value);
$function$;
