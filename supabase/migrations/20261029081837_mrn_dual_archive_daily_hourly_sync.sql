-- Install before deploying the updated Python importers. No receipt backfill is
-- performed: missing totals must come from a fresh, complete ERP export.
begin;
set local lock_timeout = '15s';

alter table public.mrn_apg_2026_hourly_state
  add column last_cd_rows integer,
  add column last_success_cd_rows integer;

create or replace function public.begin_mrn_apg_2026_hourly(p_run_id uuid,p_report_date date)
returns jsonb language plpgsql security invoker set search_path='' as $function$
declare s public.mrn_apg_2026_hourly_state;
begin
  if p_report_date is distinct from (now() at time zone 'Asia/Dubai')::date
     or extract(year from p_report_date)<>2026 then
    raise exception 'Only today in Dubai can be imported into the 2026 archive'; end if;
  perform pg_advisory_xact_lock(2026,9170);
  select * into strict s from public.mrn_apg_2026_hourly_state where singleton for update;
  if s.run_id=p_run_id then return to_jsonb(s); end if;
  if s.status in ('downloading','refreshing') and s.attempt_started_at>now()-interval '45 minutes' then
    raise exception 'An hourly MRN import is already running'; end if;
  update public.mrn_apg_2026_hourly_state set run_id=p_run_id,report_date=p_report_date,
    status='downloading',attempt_started_at=clock_timestamp(),archive_updated_at=null,
    last_rows=null,last_cd_rows=null,last_error=null where singleton returning * into s;
  return to_jsonb(s);
end;
$function$;

create or replace function stock_management_private.validate_mrn_import_rows(
  p_rows jsonb, p_start date, p_end date, p_allow_empty boolean
) returns void language plpgsql security invoker set search_path='' as $function$
begin
  if jsonb_typeof(p_rows) is distinct from 'array'
     or jsonb_array_length(p_rows)>10000
     or (not p_allow_empty and jsonb_array_length(p_rows)=0) then
    raise exception 'Expected a complete MRN array of at most 10000 rows';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_rows) e(value)
    where jsonb_typeof(value) is distinct from 'object'
      or nullif(btrim(value->>'item_code'),'') is null
      or nullif(btrim(value->>'warehouse'),'') is null
      or value->>'warehouse' is distinct from lower(btrim(value->>'warehouse'))
      or value->>'status' is distinct from 'approved'
      or (value->>'mrn_date') is null
      or (value->>'mrn_date')::date not between p_start and p_end
      or (value->>'mrn_date')::date not between date '2026-01-01' and date '2026-12-31'
      or jsonb_typeof(value->'total_qty') is distinct from 'number'
      or not (value ? 'bonus' and value ? 'prepared_by')
      or jsonb_typeof(value->'bonus') not in ('number','null')
  ) then
    raise exception 'Invalid MRN date, identity, status or extended ERP columns; both archives unchanged';
  end if;
end;
$function$;

-- The caller serializes both archives with the existing importer advisory lock.
-- Table names are allowlisted; all rows/dates remain bound SQL parameters.
create or replace function stock_management_private.replace_mrn_archive_days(
  p_table text, p_rows jsonb, p_days date[]
) returns jsonb language plpgsql security invoker set search_path='' as $function$
declare
  v_deleted integer; v_inserted integer; v_expected integer; v_valid boolean;
begin
  if p_table not in ('mrn_apg_2026','mrn_cd_apg_2026') then
    raise exception 'Unsupported MRN archive';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_rows) e(value)
    where ((value->>'warehouse') in ('store','main virtual','new virtual'))
      is distinct from (p_table='mrn_apg_2026')
  ) then raise exception 'MRN warehouse routed to the wrong archive'; end if;

  select count(*) into v_expected from jsonb_populate_recordset(null::public.mrn_apg_2026,p_rows) r
    where mrn_date=any(p_days);
  execute format('delete from public.%I where mrn_date=any($1)',p_table) using p_days;
  get diagnostics v_deleted=row_count;
  execute format($sql$
    with incoming as (
      select r.*, e.ordinality from jsonb_array_elements($1) with ordinality e(value,ordinality)
      cross join lateral jsonb_populate_record(null::public.mrn_apg_2026,e.value) r
      where r.mrn_date=any($2)
    ), numbered as (
      select incoming.*,date_trunc('month',mrn_date)::date month_start,
        row_number() over(partition by date_trunc('month',mrn_date) order by ordinality)::integer row_in_month
      from incoming
    ), bases as (
      select source_month,max(source_row_number) n from public.%I
      where source_month in (select distinct month_start from numbered) group by source_month
    )
    insert into public.%I(warehouse,status,item_code,item_name,mrn_no,mrn_date,vendor,reference,
      ordered_quantity,received_quantity,expiry_date,category_1,supplier,company,total_qty,bonus,prepared_by,
      source_month,source_row_number)
    select warehouse,status,item_code,item_name,mrn_no,mrn_date,vendor,reference,
      ordered_quantity,received_quantity,expiry_date,category_1,supplier,company,total_qty,bonus,prepared_by,
      month_start,coalesce(bases.n,0)+row_in_month
    from numbered left join bases on bases.source_month=numbered.month_start
  $sql$,p_table,p_table) using p_rows,p_days;
  get diagnostics v_inserted=row_count;
  if v_expected<>v_inserted then raise exception 'MRN insert count mismatch; both archives rolled back'; end if;

  -- Compare complete multisets so genuine identical ERP lines stay duplicated.
  -- This also checks exact totals, bonus and preparer, rather than counts alone.
  execute format($sql$
    with expected as (
      select jsonb_build_array(warehouse,status,item_code,item_name,mrn_no,mrn_date,vendor,reference,
        ordered_quantity,received_quantity,expiry_date,category_1,supplier,company,total_qty,bonus,prepared_by) signature
      from jsonb_populate_recordset(null::public.mrn_apg_2026,$1) r where mrn_date=any($2)
    ), actual as (
      select jsonb_build_array(warehouse,status,item_code,item_name,mrn_no,mrn_date,vendor,reference,
        ordered_quantity,received_quantity,expiry_date,category_1,supplier,company,total_qty,bonus,prepared_by) signature
      from public.%I where mrn_date=any($2)
    ) select not exists((select * from expected except all select * from actual)
      union all (select * from actual except all select * from expected))
  $sql$,p_table) into v_valid using p_rows,p_days;
  if not v_valid then raise exception 'MRN content/duplicate mismatch; both archives rolled back'; end if;
  return jsonb_build_object('replaced_rows',v_deleted,'inserted_rows',v_inserted,'refreshed_days',p_days);
end;
$function$;

create or replace function public.sync_mrn_apg_2026_archives(p_rows jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $function$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_yesterday date := v_today-1;
  v_latest_store date; v_latest_cd date; v_latest_after date;
  v_days date[]; v_refresh_days date[]; v_source_days date[];
  v_table text; v_rows jsonb; v_counts jsonb := '{}'::jsonb; v_archives jsonb := '{}'::jsonb;
  v_result jsonb; v_inserted integer := 0; v_deleted integer := 0;
  v_inserted_days date[] := array[]::date[];
begin
  perform stock_management_private.validate_mrn_import_rows(
    p_rows,greatest(date '2026-01-01',v_today-6),v_today,false);
  perform pg_advisory_xact_lock(2026,9170);
  select max(mrn_date) into v_latest_store from public.mrn_apg_2026;
  select max(mrn_date) into v_latest_cd from public.mrn_cd_apg_2026;
  select array_agg(distinct (value->>'mrn_date')::date) into v_source_days from jsonb_array_elements(p_rows);
  if not v_yesterday=any(v_source_days) and (
    exists(select 1 from public.mrn_apg_2026 where mrn_date=v_yesterday) or
    exists(select 1 from public.mrn_cd_apg_2026 where mrn_date=v_yesterday)
  ) then raise exception 'ERP report is missing yesterday (%); both archives unchanged',v_yesterday; end if;

  -- A latest-day snapshot is replaced completely, including corrected totals
  -- and withdrawn lines. Existing older days remain untouched.
  select coalesce(array_agg(day order by day),array[]::date[]) into v_refresh_days
    from unnest(v_source_days) day where day in (v_yesterday,v_latest_store,v_latest_cd);
  foreach v_table in array array['mrn_apg_2026','mrn_cd_apg_2026'] loop
    select coalesce(jsonb_agg(value),'[]'::jsonb) into v_rows from jsonb_array_elements(p_rows)
      where ((value->>'warehouse') in ('store','main virtual','new virtual'))=(v_table='mrn_apg_2026');
    v_counts := v_counts || jsonb_build_object(v_table,jsonb_array_length(v_rows));
    execute format('select coalesce(array_agg(day order by day),array[]::date[]) from unnest($1) day
      where day=any($2) or not exists(select 1 from public.%I a where a.mrn_date=day)',v_table)
      into v_days using v_source_days,v_refresh_days;
    v_result := stock_management_private.replace_mrn_archive_days(v_table,v_rows,v_days);
    v_archives := v_archives || jsonb_build_object(v_table,v_result);
    v_inserted := v_inserted+(v_result->>'inserted_rows')::integer;
    v_deleted := v_deleted+(v_result->>'replaced_rows')::integer;
    v_inserted_days := v_inserted_days || v_days;
  end loop;
  select greatest((select max(mrn_date) from public.mrn_apg_2026),
    (select max(mrn_date) from public.mrn_cd_apg_2026)) into v_latest_after;
  select coalesce(array_agg(distinct day order by day),array[]::date[]) into v_inserted_days from unnest(v_inserted_days) day;
  perform public.refresh_stock_management_snapshot();
  return jsonb_build_object('sync_policy','dual_archive_snapshot_v2','source_rows',jsonb_array_length(p_rows),
    'source_counts',v_counts,'archives',v_archives,'refreshed_days',v_refresh_days,
    'inserted_rows',v_inserted,'replaced_rows',v_deleted,
    'refreshed_rows',(select count(*) from jsonb_array_elements(p_rows) where (value->>'mrn_date')::date=any(v_refresh_days)),
    'inserted_days',v_inserted_days,'latest_before',greatest(v_latest_store,v_latest_cd),'latest_after',v_latest_after);
end;
$function$;

create or replace function public.replace_mrn_apg_2026_archives_today(
  p_run_id uuid,p_report_date date,p_rows jsonb
) returns jsonb language plpgsql security invoker set search_path='' as $function$
declare
  s public.mrn_apg_2026_hourly_state; v_table text; v_rows jsonb;
  v_counts jsonb := '{}'::jsonb; v_archives jsonb := '{}'::jsonb;
begin
  if p_report_date is distinct from (now() at time zone 'Asia/Dubai')::date
    or extract(year from p_report_date)<>2026 then raise exception 'Hourly MRN cannot replace another day'; end if;
  perform stock_management_private.validate_mrn_import_rows(p_rows,p_report_date,p_report_date,true);
  perform pg_advisory_xact_lock(2026,9170);
  select * into strict s from public.mrn_apg_2026_hourly_state where singleton for update;
  if s.run_id is distinct from p_run_id or s.report_date is distinct from p_report_date then
    raise exception 'Stale hourly MRN run'; end if;
  if s.archive_updated_at is not null then
    if s.last_cd_rows is null then raise exception 'Existing hourly run used the legacy STORE-only contract'; end if;
    return to_jsonb(s)||jsonb_build_object('source_rows',s.last_rows+s.last_cd_rows,
      'source_counts',jsonb_build_object('mrn_apg_2026',s.last_rows,'mrn_cd_apg_2026',s.last_cd_rows));
  end if;
  if s.status<>'downloading' then raise exception 'Hourly MRN run is not active'; end if;
  foreach v_table in array array['mrn_apg_2026','mrn_cd_apg_2026'] loop
    select coalesce(jsonb_agg(value),'[]'::jsonb) into v_rows from jsonb_array_elements(p_rows)
      where ((value->>'warehouse') in ('store','main virtual','new virtual'))=(v_table='mrn_apg_2026');
    v_counts := v_counts || jsonb_build_object(v_table,jsonb_array_length(v_rows));
    v_archives := v_archives || jsonb_build_object(v_table,
      stock_management_private.replace_mrn_archive_days(v_table,v_rows,array[p_report_date]));
  end loop;
  update public.mrn_apg_2026_hourly_state set status='refreshing',
    last_rows=(v_counts->>'mrn_apg_2026')::integer,last_cd_rows=(v_counts->>'mrn_cd_apg_2026')::integer,
    archive_updated_at=clock_timestamp() where singleton returning * into s;
  perform public.refresh_stock_management_snapshot();
  return to_jsonb(s)||jsonb_build_object('source_rows',jsonb_array_length(p_rows),
    'source_counts',v_counts,'archives',v_archives);
end;
$function$;

-- Keep STORE counters compatible with the existing update card; CD has its own
-- receipt revision and a separate successful row counter.
create or replace function public.complete_mrn_apg_2026_hourly(p_run_id uuid)
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
  perform public.refresh_stock_expiry_watch();
  update public.mrn_apg_2026_hourly_state set status='complete',last_error=null,
    last_success_at=clock_timestamp(),last_success_report_date=report_date,
    last_success_rows=last_rows,last_success_cd_rows=last_cd_rows where singleton returning * into s;
  return to_jsonb(s)||jsonb_build_object('ready',true);
end;
$function$;

revoke all on function stock_management_private.validate_mrn_import_rows(jsonb,date,date,boolean),
  stock_management_private.replace_mrn_archive_days(text,jsonb,date[]),
  public.sync_mrn_apg_2026_archives(jsonb),
  public.begin_mrn_apg_2026_hourly(uuid,date),
  public.replace_mrn_apg_2026_archives_today(uuid,date,jsonb),
  public.complete_mrn_apg_2026_hourly(uuid) from public,anon,authenticated;
grant usage on schema stock_management_private to service_role;
grant execute on function stock_management_private.validate_mrn_import_rows(jsonb,date,date,boolean),
  stock_management_private.replace_mrn_archive_days(text,jsonb,date[]),
  public.sync_mrn_apg_2026_archives(jsonb),
  public.begin_mrn_apg_2026_hourly(uuid,date),
  public.replace_mrn_apg_2026_archives_today(uuid,date,jsonb),
  public.complete_mrn_apg_2026_hourly(uuid) to service_role;
notify pgrst,'reload schema';
commit;
