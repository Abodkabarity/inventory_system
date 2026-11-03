-- Separate rolling daily export; monthly format/revisions remain unchanged.
alter table sales_report_private.jobs add column report_kind text not null default 'monthly'
  check(report_kind in ('monthly','daily45'));
alter table sales_report_private.jobs add column period_from date;
alter table sales_report_private.jobs add column period_through date;
alter table sales_report_private.jobs add constraint sales_report_kind_selection check(
  (report_kind='monthly' and cardinality(months)>0)
  or (report_kind='daily45' and cardinality(months)=0));
create table sales_report_private.daily_revision (
  singleton boolean primary key default true check(singleton),
  revision bigint not null default 0,
  changed_at timestamptz not null default '-infinity'
);
insert into sales_report_private.daily_revision(singleton) values(true);
create table sales_report_private.daily_metadata (
  scope_key text primary key,
  source_version text,
  period_from date,
  period_through date,
  days jsonb not null default '[]'
);
alter table sales_report_private.daily_revision enable row level security;
alter table sales_report_private.daily_metadata enable row level security;
revoke all on sales_report_private.daily_revision,sales_report_private.daily_metadata from public,anon,authenticated,service_role;

-- One counter update per source statement, independent of other refresh jobs.
create function sales_report_private.bump_daily_revision()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  update sales_report_private.daily_revision set revision=revision+1,changed_at=clock_timestamp() where singleton;
  return null;
end $$;
create trigger sales_report_daily_source_changed
  after insert or update or delete or truncate on public.sales_last_45_days
  for each statement execute function sales_report_private.bump_daily_revision();
-- Expected coverage follows the existing 08:00 UAE morning import. Before it,
-- the most recent completed scheduled load is the previous morning's load.
create function sales_report_private.daily_expected_day(p_at timestamptz default statement_timestamp())
returns date language sql stable security invoker set search_path='' as $$
  select (p_at at time zone 'Asia/Dubai')::date -
    case when (p_at at time zone 'Asia/Dubai')::time>=time '08:00' then 1 else 2 end;
$$;
create function sales_report_private.daily_version()
returns text language sql stable security invoker set search_path='' as $$
  select 'sales-daily45-v1:'||d.revision||':branches:'||b.revision||':date:'||
    (statement_timestamp() at time zone 'Asia/Dubai')::date::text||':expected:'||sales_report_private.daily_expected_day()::text
  from sales_report_private.daily_revision d cross join public.stock_catalog_cache_revisions b
  where d.singleton and b.source='branches';
$$;
-- Require the atomic two-company morning publication receipt even if nightly
-- data already contains that date. Partial nightly data cannot stand in for it.
-- This check is also enforced by Storage and the worker, not only the UI.
-- A one-minute quiet period protects against non-atomic bulk reload batches.
create function sales_report_private.daily_fresh()
returns boolean language sql stable security invoker set search_path='' as $$
  select coalesce((
    select d.changed_at<=statement_timestamp()-interval '60 seconds'
      and m.source_version=sales_report_private.daily_version()
      and m.period_through>=sales_report_private.daily_expected_day() and exists(
        select 1 from sales_ingest_private.daily_runs r
        where r.report_date=sales_report_private.daily_expected_day()
          and r.result->>'published'='true')
    from sales_report_private.daily_revision d
    join sales_report_private.daily_metadata m on m.scope_key='inventory'
    where d.singleton),false);
$$;
create function sales_report_private.job_version(p_kind text)
returns text language sql stable security invoker set search_path='' as $$
  select case when p_kind='daily45' then sales_report_private.daily_version()
    else sales_report_private.source_version() end;
$$;

create function sales_report_private.refresh_daily_metadata(p_key text,p_branches text[])
returns sales_report_private.daily_metadata language plpgsql security invoker set search_path='' as $$
declare m sales_report_private.daily_metadata; v_version text:=sales_report_private.daily_version();
begin
  if v_version is null then raise exception 'Daily source revision unavailable'; end if;
  insert into sales_report_private.daily_metadata(scope_key) values(p_key) on conflict do nothing;
  select * into m from sales_report_private.daily_metadata where scope_key=p_key;
  if m.source_version is distinct from v_version then
    with version as materialized(select sales_report_private.daily_version() v),
    cutoff as materialized (
      select max(inv_date) as through from public.sales_last_45_days
      where inv_date<=sales_report_private.daily_expected_day()
        and (p_branches is null or btrim(branch_name)=any(p_branches))
    ), dates as (
      select distinct inv_date from public.sales_last_45_days cross join cutoff
      where inv_date between cutoff.through-44 and cutoff.through
        and (p_branches is null or btrim(branch_name)=any(p_branches))
    )
    update sales_report_private.daily_metadata set source_version=(select v from version),
      period_from=(select through-44 from cutoff),period_through=(select through from cutoff),
      days=(select coalesce(jsonb_agg(inv_date order by inv_date),'[]') from dates)
      where scope_key=p_key returning * into m;
  end if;
  return m;
end $$;

-- The existing worker invokes this while holding its short queue lease lock.
create function sales_report_private.sync_daily()
returns void language plpgsql security invoker set search_path='' as $$
declare m sales_report_private.daily_metadata; previous text;
begin
  select source_version into previous from sales_report_private.daily_metadata where scope_key='inventory';
  m:=sales_report_private.refresh_daily_metadata('inventory',null);
  if previous is distinct from m.source_version then
    delete from sales_report_private.pieces p using sales_report_private.jobs j
      where j.id=p.job_id and j.report_kind='daily45' and j.source_version is distinct from m.source_version;
    update sales_report_private.jobs set status='queued',generation=gen_random_uuid(),source_version=null,
      prepared_at=null,finished_at=null,storage_path=null,upload_url=null,byte_size=null,row_count=null,
      period_from=null,period_through=null,uploaded_bytes=0,failures=0,last_error=null,next_attempt_at=now()
      where report_kind='daily45' and source_version is distinct from m.source_version
        and (source_version is not null or status='failed');
  end if;
  if m.period_through is not null then
    insert into sales_report_private.jobs(months,report_kind,priority)
      values(array[]::text[],'daily45',100) on conflict(scope_key,months) do nothing;
  end if;
end $$;

create function sales_report_private.daily_api(p_request boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare scope jsonb; names text[]; m sales_report_private.daily_metadata;
  j sales_report_private.jobs; version text;
begin
  scope:=sales_report_private.current_scope();
  if scope is null then raise exception 'Inventory or Zone Manager access required' using errcode='42501'; end if;
  if scope->>'kind'='zone' then
    select coalesce(array_agg(b),array[]::text[]) into names from jsonb_array_elements_text(scope->'branches') b;
  end if;
  -- Same lock order as the worker: state, metadata, job.
  perform 1 from sales_report_private.state where singleton for update;
  perform sales_report_private.sync_daily();
  m:=sales_report_private.refresh_daily_metadata(scope->>'key',names);
  version:=sales_report_private.daily_version();
  if m.period_through is not null then
    insert into sales_report_private.jobs(scope_key,scope_user_id,branch_names,months,report_kind,priority)
      values(scope->>'key',case when scope->>'kind'='zone' then auth.uid() end,names,array[]::text[],'daily45',
        case when p_request then 0 else 100 end)
      on conflict(scope_key,months) do nothing;
    select * into j from sales_report_private.jobs where scope_key=scope->>'key' and report_kind='daily45' for update;
    if (j.source_version is not null and j.source_version<>version) or (p_request and j.status='failed') then
      delete from sales_report_private.pieces where job_id=j.id;
      update sales_report_private.jobs set status='queued',generation=gen_random_uuid(),source_version=null,
        prepared_at=null,finished_at=null,storage_path=null,upload_url=null,byte_size=null,row_count=null,
        period_from=null,period_through=null,uploaded_bytes=0,failures=0,last_error=null,next_attempt_at=now()
        where id=j.id returning * into j;
    end if;
    if p_request then update sales_report_private.jobs set priority=0,requested_at=now() where id=j.id; end if;
    if j.status in ('queued','uploading') and sales_report_private.daily_fresh() then perform sales_report_private.dispatch(); end if;
  elsif p_request then raise exception 'No daily sales available in your scope' using errcode='22023'; end if;
  return jsonb_build_object('report_kind','daily45','scope_kind',scope->>'kind','scope_label',scope->>'label',
    'period_from',m.period_from,'period_through',m.period_through,'days',m.days,
    'awaiting_update',not sales_report_private.daily_fresh(),'expected_through',sales_report_private.daily_expected_day(),
    'update_time','08:00 UAE',
    'metadata_current',m.source_version=version,'source_version',version,
    'job',case when j.id is null then null else jsonb_build_object(
      'id',j.id,'generation',j.generation,'status',j.status,'is_current',j.source_version=version and sales_report_private.daily_fresh(),
      'row_count',j.row_count,'byte_size',j.byte_size,'uploaded_bytes',j.uploaded_bytes,
      'prepared_at',j.prepared_at,'finished_at',j.finished_at,'retrying',j.failures>0,
      'storage_path',case when j.status='ready' and j.source_version=version and sales_report_private.daily_fresh() then j.storage_path end) end);
end $$;
create function public.get_sales_45_report(p_request boolean default false)
returns jsonb language sql security invoker set search_path='' as $$
  select sales_report_private.daily_api(p_request);
$$;
revoke all on function public.get_sales_45_report(boolean) from public,anon,authenticated,service_role;
grant execute on function public.get_sales_45_report(boolean) to authenticated;

create function sales_report_private.prepare_daily(p_job uuid,p_lease uuid)
returns jsonb language plpgsql security invoker set search_path='' set work_mem='8MB' set enable_hashagg='off' as $$
declare j sales_report_private.jobs; result jsonb;
begin
  if not exists(select 1 from sales_report_private.state where singleton and lease=p_lease and lease_until>now()) then
    raise exception 'Worker lease expired'; end if;
  select * into strict j from sales_report_private.jobs where id=p_job and report_kind='daily45' for update;
  if j.status<>'queued' then return to_jsonb(j); end if;
  delete from sales_report_private.pieces where job_id=j.id;
  with version as materialized(select sales_report_private.daily_version() v),
  bounds as materialized (
    select max(inv_date) as through from public.sales_last_45_days h
    where inv_date<=sales_report_private.daily_expected_day() and
      ((j.scope_key='inventory' and j.scope_user_id is null) or
       (j.scope_user_id is not null and btrim(h.branch_name)=any(j.branch_names)))
  ), groups as materialized (
    select coalesce(jsonb_object_agg(upper(btrim(branch_name)),btrim(branch_group::text)),'{}') g from public.branches
  ), numbered as (
    select row_number() over(order by h.inv_date,h.branch_name,h.item_code,h.id) n,
      h.branch_name,h.inv_date,h.item_code,h.item_name,h.qty,h.sales_type,h.inv_type,h.customer_name
    from public.sales_last_45_days h cross join bounds
    where h.inv_date between bounds.through-44 and bounds.through and
      ((j.scope_key='inventory' and j.scope_user_id is null) or
       (j.scope_user_id is not null and btrim(h.branch_name)=any(j.branch_names)))
  ), lines as (
    select n,array_to_string(array[
      '"'||replace(coalesce(sales_report_private.display_branch(h.branch_name,g.g),''),'"','""')||'"',
      '"'||replace(coalesce(h.inv_date::text,''),'"','""')||'"',
      '"'||replace(coalesce(h.item_code,''),'"','""')||'"',
      '"'||replace(coalesce(h.item_name,''),'"','""')||'"',
      '"'||replace(coalesce(h.qty::text,''),'"','""')||'"',
      '"'||replace(coalesce(h.sales_type,''),'"','""')||'"',
      '"'||replace(coalesce(h.inv_type,''),'"','""')||'"',
      '"'||replace(coalesce(h.customer_name,''),'"','""')||'"'],',')||E'\r\n' as line
    from numbered h cross join groups g
  ), chunks as (
    select 1+(n-1)/5000 part,convert_to(string_agg(line,'' order by n),'UTF8') data,count(*) rows from lines group by (n-1)/5000
    union all select 0,convert_to(U&'\FEFF'||sales_report_private.csv_row(array[
      'branch_name','inv_date','item_code','item_name','qty','sales_type','inv_type','customer_name']),'UTF8'),0
  ), positioned as (
    select part,data,rows,sum(octet_length(data)) over(order by part)::bigint byte_end from chunks
  ), saved as (
    insert into sales_report_private.pieces(job_id,generation,part,byte_start,byte_end,data)
    select j.id,j.generation,part,byte_end-octet_length(data),byte_end,data from positioned returning byte_end
  )
  update sales_report_private.jobs set source_version=(select v from version),
    period_from=(select through-44 from bounds),period_through=(select through from bounds),
    row_count=(select sum(rows) from positioned),byte_size=(select max(byte_end) from saved),
    prepared_at=statement_timestamp(),storage_path=j.id::text||'/'||j.generation::text||'.csv',
    status='uploading',uploaded_bytes=0,upload_url=null where id=j.id returning to_jsonb(sales_report_private.jobs.*) into result;
  return result;
end $$;
revoke all on function sales_report_private.bump_daily_revision(),sales_report_private.daily_version(),
  sales_report_private.daily_expected_day(timestamptz),sales_report_private.daily_fresh(),sales_report_private.job_version(text),sales_report_private.refresh_daily_metadata(text,text[]),
  sales_report_private.sync_daily(),sales_report_private.daily_api(boolean),sales_report_private.prepare_daily(uuid,uuid)
  from public,anon,authenticated,service_role;
grant execute on function sales_report_private.daily_api(boolean) to authenticated;

create or replace function sales_report_private.worker(p_action text,p_args jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s sales_report_private.state; j sales_report_private.jobs; v_lease uuid;
  v_version text; v_months text[]; v_offset bigint; v_data bytea; v_size bigint; v_result jsonb;
begin
  if p_action='authorize' then
    return to_jsonb(exists(select 1 from vault.decrypted_secrets where name='sales_report_worker_token'
      and decrypted_secret=p_args->>'token'));
  end if;
  if p_action='claim' then
    v_lease:=gen_random_uuid();
    update sales_report_private.state set lease=v_lease,lease_until=now()+interval '180 seconds',heartbeat_at=now()
    where singleton and (lease_until is null or lease_until<now()) returning * into s;
    if not found then return null; end if;
    perform sales_report_private.sync_daily();
    v_version:=sales_report_private.source_version();
    if v_version is null then raise exception 'Sales source revision unavailable'; end if;
    if s.metadata_version is distinct from v_version then
      with version as materialized (select sales_report_private.source_version() v),
      months as (select month,count(*) rows from public.sales_history
        where month ~ '^(0[1-9]|1[0-2])/[0-9]{4}$' group by month)
      update sales_report_private.state set metadata_version=(select v from version),
        months=(select coalesce(jsonb_agg(jsonb_build_object('month',month,'row_count',rows)
          order by right(month,4),left(month,2)),'[]') from months) where singleton returning * into s;
      insert into sales_report_private.jobs(months,priority)
        select array[a->>'month'],100 from jsonb_array_elements(s.months) a on conflict(scope_key,months) do nothing;
      select array_agg(a->>'month' order by right(a->>'month',4),left(a->>'month',2)) into v_months
        from jsonb_array_elements(s.months) a;
      if cardinality(v_months)>1 then
        insert into sales_report_private.jobs(months,priority) values(v_months,200) on conflict(scope_key,months) do nothing;
      end if;
      delete from sales_report_private.pieces p using sales_report_private.jobs q
        where q.id=p.job_id and q.report_kind='monthly' and q.source_version is distinct from s.metadata_version;
      update sales_report_private.jobs set status='queued',generation=gen_random_uuid(),source_version=null,
        storage_path=null,upload_url=null,byte_size=null,row_count=null,prepared_at=null,finished_at=null,
        uploaded_bytes=0,failures=0,last_error=null,next_attempt_at=now()
        where report_kind='monthly' and source_version is not null and source_version<>s.metadata_version;
    end if;
    select * into j from sales_report_private.jobs where status in ('queued','uploading') and next_attempt_at<=now()
      and (report_kind='monthly' or sales_report_private.daily_fresh())
      order by priority,requested_at limit 1 for update skip locked;
    if j.id is null then
      update sales_report_private.state set lease=null,lease_until=null where singleton and lease=v_lease;
      return null;
    end if;
    return jsonb_build_object('lease',v_lease,'job',to_jsonb(j));
  end if;
  v_lease:=(p_args->>'lease')::uuid;
  -- Preparation holds only its job row, keeping other selections responsive.
  -- Its immutable generation and the 180-second lease fence the continuation.
  if p_action='prepare' then
    select * into strict j from sales_report_private.jobs where id=(p_args->>'id')::uuid
      and generation=(p_args->>'generation')::uuid for update;
    if j.report_kind='daily45' then return sales_report_private.prepare_daily(j.id,v_lease); end if;
    return sales_report_private.prepare(j.id,v_lease);
  end if;
  select * into s from sales_report_private.state where singleton and lease=v_lease and lease_until>now() for update;
  if not found then raise exception 'Worker lease expired'; end if;
  update sales_report_private.state set heartbeat_at=now(),lease_until=now()+interval '180 seconds' where singleton;
  if p_action='release' then
    update sales_report_private.state set lease=null,lease_until=null,dispatched_at=null where singleton;
    if exists(select 1 from sales_report_private.jobs where status in ('queued','uploading') and next_attempt_at<=now()
      and (report_kind='monthly' or sales_report_private.daily_fresh())) then
      perform sales_report_private.dispatch();
    end if;
    return 'true';
  end if;
  if p_action='garbage' then
    return coalesce((select jsonb_agg(name) from (
      select o.name from storage.objects o where bucket_id='sales-report-exports'
        and o.created_at<now()-interval '1 day'
        and not exists(select 1 from sales_report_private.jobs q where q.storage_path=o.name)
        limit 50) x),'[]');
  end if;
  select * into strict j from sales_report_private.jobs where id=(p_args->>'id')::uuid
    and generation=(p_args->>'generation')::uuid for update;
  if p_action='upload_url' then
    update sales_report_private.jobs set upload_url=p_args->>'url' where id=j.id;
    return 'true';
  end if;
  if p_action='bytes' then
    v_offset:=(p_args->>'offset')::bigint;
    if j.status<>'uploading' or v_offset<0 or v_offset>=j.byte_size then raise exception 'Invalid upload offset'; end if;
    select string_agg(substring(data from (greatest(v_offset,byte_start)-byte_start+1)::integer
      for (least(v_offset+6291456,byte_end)-greatest(v_offset,byte_start))::integer),''::bytea order by part)
      into v_data from sales_report_private.pieces where job_id=j.id and generation=j.generation
      and byte_start<v_offset+6291456 and byte_end>v_offset;
    if octet_length(v_data) is distinct from least(6291456,j.byte_size-v_offset) then raise exception 'Incomplete CSV pieces'; end if;
    return jsonb_build_object('base64',replace(encode(v_data,'base64'),E'\n',''),'length',octet_length(v_data));
  end if;
  if p_action='progress' then
    v_offset:=(p_args->>'offset')::bigint;
    if v_offset<0 or v_offset>j.byte_size then raise exception 'Invalid upload progress'; end if;
    update sales_report_private.jobs set uploaded_bytes=v_offset,failures=0,last_error=null where id=j.id;
    return 'true';
  end if;
  if p_action='complete' then
    select (metadata->>'size')::bigint into v_size from storage.objects
      where bucket_id='sales-report-exports' and name=j.storage_path;
    if v_size is distinct from j.byte_size or j.byte_size is null then return 'false'; end if;
    if j.source_version is distinct from sales_report_private.job_version(j.report_kind)
      or (j.report_kind='daily45' and not sales_report_private.daily_fresh()) then
      update sales_report_private.jobs set status='queued',generation=gen_random_uuid(),source_version=null,
        storage_path=null,upload_url=null,byte_size=null,row_count=null,uploaded_bytes=0,
        prepared_at=null,finished_at=null where id=j.id;
    else
      update sales_report_private.jobs set status='ready',uploaded_bytes=byte_size,
        finished_at=now(),upload_url=null,failures=0,last_error=null where id=j.id;
    end if;
    delete from sales_report_private.pieces where job_id=j.id;
    return 'true';
  end if;
  if p_action='error' then
    update sales_report_private.jobs set failures=failures+1,
      status=case when failures>=4 then 'failed' else status end,
      last_error=left(p_args->>'error',500),
      next_attempt_at=now()+make_interval(secs=>least(900,30*power(2,least(failures,5))::integer)) where id=j.id;
    return 'true';
  end if;
  raise exception 'Unknown worker action';
end $$;



create or replace function sales_report_private.can_download(p_path text)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare v_scope jsonb; v_branches text[];
begin
  v_scope:=sales_report_private.current_scope();
  if v_scope is null then return false; end if;
  if v_scope->>'kind'='zone' then
    select coalesce(array_agg(x),array[]::text[]) into v_branches from jsonb_array_elements_text(v_scope->'branches') x;
  end if;
  return exists(select 1 from sales_report_private.jobs where storage_path=p_path and status='ready'
    and source_version=sales_report_private.job_version(report_kind)
    and (report_kind='monthly' or sales_report_private.daily_fresh()) and scope_key=v_scope->>'key'
    and ((v_scope->>'kind'='inventory' and scope_user_id is null and branch_names is null)
      or (v_scope->>'kind'='zone' and scope_user_id=auth.uid() and branch_names=v_branches)));
end $$;


notify pgrst,'reload schema';
