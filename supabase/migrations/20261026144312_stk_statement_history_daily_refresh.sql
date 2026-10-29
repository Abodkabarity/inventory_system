-- Raw, all-movement daily archive replacement. This is independent of order
-- generation and does not change the existing statement/sales snapshot RPCs.
create schema stk_history_ingest_private;
revoke all on schema stk_history_ingest_private from public,anon,authenticated;
grant usage on schema stk_history_ingest_private to service_role;

create table stk_history_ingest_private.batches (
  run_id uuid not null, report_date date not null,
  company text not null check(company in ('APG','71 Pharmacy L.L.C.')),
  batch_no integer not null check(batch_no>=0),
  source_sha256 text not null check(source_sha256 ~ '^[0-9a-f]{64}$'),
  rows jsonb not null check(jsonb_typeof(rows)='array' and jsonb_array_length(rows)<=5000),
  created_at timestamptz not null default now(),
  primary key(run_id,report_date,company,batch_no)
);
create index stk_history_batch_age_idx on stk_history_ingest_private.batches(created_at);
create table stk_history_ingest_private.publications (
  run_id uuid not null,report_date date not null,
  expected jsonb not null,receipt jsonb not null,
  primary key(run_id,report_date)
);
create table stk_history_ingest_private.day_state (
  company text not null,report_date date not null,
  run_id uuid not null,source_sha256 text not null,
  row_count bigint not null,quantity_sum numeric not null,
  requested_at timestamptz not null,published_at timestamptz not null default now(),
  primary key(company,report_date)
);
alter table stk_history_ingest_private.batches enable row level security;
alter table stk_history_ingest_private.publications enable row level security;
alter table stk_history_ingest_private.day_state enable row level security;
revoke all on all tables in schema stk_history_ingest_private from public,anon,authenticated;
grant all on all tables in schema stk_history_ingest_private to service_role;
create policy stk_history_batch_service on stk_history_ingest_private.batches
  for all to service_role using(true) with check(true);
create policy stk_history_publication_service on stk_history_ingest_private.publications
  for all to service_role using(true) with check(true);
create policy stk_history_state_service on stk_history_ingest_private.day_state
  for all to service_role using(true) with check(true);

create function public.get_stk_history_daily_plan(p_today date)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare company_name text; latest_day date; next_day date;
  companies jsonb:='[]'; first_day date:=greatest(date '2026-01-01',p_today-1);
begin
  if p_today is null or p_today<date '2026-01-01'
    or p_today>(now() at time zone 'Asia/Dubai')::date then
    raise exception 'Invalid statement target date';
  end if;
  foreach company_name in array array['APG','71 Pharmacy L.L.C.'] loop
    -- The existing company/date index avoids a scan of the full archive.
    select greatest(
      (select trans_date from public.stk_statement_history_2026 where company=company_name and trans_date<=p_today
        order by trans_date desc limit 1),
      (select report_date from stk_history_ingest_private.day_state where company=company_name and report_date<=p_today
        order by report_date desc limit 1)) into latest_day;
    next_day:=greatest(date '2026-01-01',least(coalesce(latest_day+1,date '2026-01-01'),p_today-1));
    first_day:=least(first_day,next_day);
    companies:=companies||jsonb_build_array(jsonb_build_object('company',company_name,
      'latest_date',latest_day,'from_date',next_day));
  end loop;
  return jsonb_build_object('today',p_today,'from_date',first_day,'to_date',p_today,
    'started_at',statement_timestamp(),'companies',companies,'batch_size',5000);
end $$;

create function public.stage_stk_history_daily_batch(
  p_run_id uuid,p_report_date date,p_company text,p_batch_no integer,p_rows jsonb,p_sha256 text
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare previous stk_history_ingest_private.batches%rowtype;
begin
  if p_run_id is null or p_report_date is null or p_report_date<date '2026-01-01'
    or p_report_date>(now() at time zone 'Asia/Dubai')::date
    or p_company is null or p_company not in ('APG','71 Pharmacy L.L.C.')
    or p_batch_no is null or p_batch_no<0
    or p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$'
    or jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)>5000 then
    raise exception 'Invalid statement staging input (maximum 5000 rows)';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('stk-history-stage:'||p_run_id||':'||p_report_date,0));
  if exists(select 1 from stk_history_ingest_private.publications
    where run_id=p_run_id and report_date=p_report_date) then
    return jsonb_build_object('already_published',true);
  end if;
  if exists(select 1 from jsonb_to_recordset(p_rows) r(
    branch_name text,item_code text,qty numeric,trans_date date,mode text,
    trans_type text,trans_no text,company text,archive_fingerprint text)
    where branch_name is null or item_code is null or qty is null
      or qty::text in ('NaN','Infinity','-Infinity')
      or trans_date is distinct from p_report_date or company is distinct from p_company
      or archive_fingerprint is null or archive_fingerprint !~ '^[0-9a-f]{64}$') then
    raise exception 'Statement row has invalid identity, quantity, date, company or fingerprint';
  end if;
  insert into stk_history_ingest_private.batches(run_id,report_date,company,batch_no,source_sha256,rows)
  values(p_run_id,p_report_date,p_company,p_batch_no,p_sha256,p_rows) on conflict do nothing;
  select * into previous from stk_history_ingest_private.batches where run_id=p_run_id
    and report_date=p_report_date and company=p_company and batch_no=p_batch_no;
  if previous.rows is distinct from p_rows or previous.source_sha256<>p_sha256 then
    raise exception 'A retry cannot change a staged batch';
  end if;
  delete from stk_history_ingest_private.batches where created_at<now()-interval '7 days';
  return jsonb_build_object('staged',true,'rows',jsonb_array_length(p_rows));
end $$;

create function public.publish_stk_history_daily_day(
  p_run_id uuid,p_report_date date,p_expected jsonb,p_started_at timestamptz
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare company_name text; meta jsonb; previous jsonb; result jsonb;
  batch_n integer; rows_n bigint; sum_qty numeric; distinct_n bigint; expected_n bigint:=0;
  inserted_n bigint; month_start date; end_day date; old_rows bigint;
begin
  if p_run_id is null or p_report_date is null or p_report_date<date '2026-01-01'
    or p_report_date>(now() at time zone 'Asia/Dubai')::date or p_started_at is null
    or p_started_at>now()+interval '1 minute'
    or jsonb_typeof(p_expected) is distinct from 'object'
    or not (p_expected ?& array['APG','71 Pharmacy L.L.C.'])
    or (select count(*) from jsonb_object_keys(p_expected))<>2 then
    raise exception 'Both companies and a valid source request timestamp are required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('stk-history-stage:'||p_run_id||':'||p_report_date,0));
  select receipt into previous from stk_history_ingest_private.publications
    where run_id=p_run_id and report_date=p_report_date and expected=p_expected;
  if found then return previous; end if;
  if exists(select 1 from stk_history_ingest_private.publications
    where run_id=p_run_id and report_date=p_report_date) then
    raise exception 'Published run manifest cannot change';
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended('stk-history-day:'||p_report_date,0)) then
    raise exception 'Another statement refresh owns this date';
  end if;

  month_start:=date_trunc('month',p_report_date)::date;
  foreach company_name in array array['APG','71 Pharmacy L.L.C.'] loop
    -- Coordinate with every possible monthly backfill end date covering this
    -- day, including partial months. The legacy importer uses these same keys.
    for end_day in select d::date from generate_series(p_report_date::timestamp,
      (month_start+interval '1 month'-interval '1 day')::timestamp,interval '1 day') d loop
      if not pg_try_advisory_xact_lock(hashtext('full-statement:'||company_name||'|'||month_start||'|'||end_day)) then
        raise exception 'A monthly statement backfill owns this date';
      end if;
    end loop;
    meta:=p_expected->company_name;
    if jsonb_typeof(meta) is distinct from 'object' or not(meta ?& array['rows','quantity','batches','sha256'])
      or meta->>'rows' is null or meta->>'quantity' is null
      or meta->>'batches' is null or meta->>'sha256' is null
      or (meta->>'rows')::bigint<0 or (meta->>'batches')::integer<1
      or meta->>'sha256' !~ '^[0-9a-f]{64}$'
      or (meta->>'quantity')::numeric::text in ('NaN','Infinity','-Infinity') then
      raise exception 'Invalid expected company manifest';
    end if;
    select count(*),coalesce(sum(jsonb_array_length(rows)),0) into batch_n,rows_n
      from stk_history_ingest_private.batches where run_id=p_run_id
        and report_date=p_report_date and company=company_name;
    if batch_n<>(meta->>'batches')::integer or rows_n<>(meta->>'rows')::bigint
      or exists(select 1 from generate_series(0,batch_n-1) n where not exists(
        select 1 from stk_history_ingest_private.batches where run_id=p_run_id
          and report_date=p_report_date and company=company_name and batch_no=n))
      or exists(select 1 from stk_history_ingest_private.batches where run_id=p_run_id
        and report_date=p_report_date and company=company_name and source_sha256<>meta->>'sha256') then
      raise exception 'Incomplete statement staging for %',company_name;
    end if;
    select coalesce(sum(r.qty),0),count(distinct r.archive_fingerprint) into sum_qty,distinct_n
      from stk_history_ingest_private.batches b cross join lateral jsonb_to_recordset(b.rows)
        r(qty numeric,archive_fingerprint text)
      where b.run_id=p_run_id and b.report_date=p_report_date and b.company=company_name;
    if sum_qty<>(meta->>'quantity')::numeric or distinct_n<>rows_n then
      raise exception 'Statement quantity or duplicate-fingerprint check failed';
    end if;
    if exists(select 1 from stk_history_ingest_private.day_state where company=company_name
      and report_date=p_report_date and requested_at>p_started_at)
      or exists(select 1 from public.stk_statement_history_2026 where company=company_name
        and trans_date=p_report_date and created_at>p_started_at) then
      raise exception 'A newer archive snapshot exists; stale replacement refused';
    end if;
    expected_n:=expected_n+rows_n;
  end loop;

  -- No live rows are removed until BOTH exports and ALL batches are verified.
  delete from public.stk_statement_history_2026 where trans_date=p_report_date
    and company in ('APG','71 Pharmacy L.L.C.');
  get diagnostics old_rows=row_count;
  insert into public.stk_statement_history_2026(branch_name,item_code,qty,trans_date,mode,
    company,archive_fingerprint,trans_type,trans_no)
  select r.branch_name,r.item_code,r.qty,r.trans_date,r.mode,r.company,r.archive_fingerprint,r.trans_type,r.trans_no
    from stk_history_ingest_private.batches b cross join lateral jsonb_to_recordset(b.rows) r(
      branch_name text,item_code text,qty numeric,trans_date date,mode text,
      company text,archive_fingerprint text,trans_type text,trans_no text)
    where b.run_id=p_run_id and b.report_date=p_report_date;
  get diagnostics inserted_n=row_count;
  if inserted_n<>expected_n then raise exception 'Archive publication row count mismatch'; end if;
  foreach company_name in array array['APG','71 Pharmacy L.L.C.'] loop
    meta:=p_expected->company_name;
    select count(*),coalesce(sum(qty),0) into rows_n,sum_qty from public.stk_statement_history_2026
      where company=company_name and trans_date=p_report_date;
    if rows_n<>(meta->>'rows')::bigint or sum_qty<>(meta->>'quantity')::numeric then
      raise exception 'Archive publication reconciliation failed';
    end if;
    insert into stk_history_ingest_private.day_state(company,report_date,run_id,source_sha256,
      row_count,quantity_sum,requested_at) values(company_name,p_report_date,p_run_id,
        meta->>'sha256',rows_n,sum_qty,p_started_at)
    on conflict(company,report_date) do update set run_id=excluded.run_id,
      source_sha256=excluded.source_sha256,row_count=excluded.row_count,
      quantity_sum=excluded.quantity_sum,requested_at=excluded.requested_at,published_at=now();
  end loop;
  -- A replaced slice is no longer the immutable file used by the old monthly
  -- resume cursor. Keep that cursor, but invalidate its complete-file claim.
  update public.stk_statement_history_load_progress set complete=false,updated_at=now()
    where company in ('APG','71 Pharmacy L.L.C.') and p_report_date between from_date and to_date;
  result:=jsonb_build_object('published',true,'report_date',p_report_date,'rows',inserted_n,
    'replaced_rows',old_rows,'run_id',p_run_id);
  insert into stk_history_ingest_private.publications values(p_run_id,p_report_date,p_expected,result);
  delete from stk_history_ingest_private.batches where run_id=p_run_id and report_date=p_report_date;
  return result;
end $$;

revoke all on function public.get_stk_history_daily_plan(date) from public,anon,authenticated;
revoke all on function public.stage_stk_history_daily_batch(uuid,date,text,integer,jsonb,text) from public,anon,authenticated;
revoke all on function public.publish_stk_history_daily_day(uuid,date,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.get_stk_history_daily_plan(date) to service_role;
grant execute on function public.stage_stk_history_daily_batch(uuid,date,text,integer,jsonb,text) to service_role;
grant execute on function public.publish_stk_history_daily_day(uuid,date,jsonb,timestamptz) to service_role;
notify pgrst,'reload schema';
