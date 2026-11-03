-- Sales Report is independent of Online Overview and of all source refresh jobs.
-- Durable server-side CSV preparation; no workstation/ERP automation dependency.
create schema sales_report_private;
revoke all on schema sales_report_private from public,anon,authenticated;
grant usage on schema sales_report_private to authenticated,service_role;

create table sales_report_private.state (
  singleton boolean primary key default true check(singleton),
  metadata_version text,
  months jsonb not null default '[]',
  heartbeat_at timestamptz,
  lease uuid,
  lease_until timestamptz,
  dispatched_at timestamptz
);
insert into sales_report_private.state(singleton) values(true);
create table sales_report_private.jobs (
  id uuid primary key default gen_random_uuid(),
  months text[] not null unique,
  generation uuid not null default gen_random_uuid(),
  source_version text,
  status text not null default 'queued' check(status in ('queued','uploading','ready','failed')),
  priority integer not null default 100,
  requested_at timestamptz not null default now(),
  prepared_at timestamptz,
  finished_at timestamptz,
  row_count bigint,
  byte_size bigint,
  uploaded_bytes bigint not null default 0,
  storage_path text,
  upload_url text,
  failures integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  last_error text
);
create index sales_report_queue on sales_report_private.jobs(priority,requested_at)
  where status in ('queued','uploading');
-- Temporary CSV pieces, each containing exactly 5,000 source rows (except last).
-- Removed after a verified upload. Logged so a database restart can resume safely.
create table sales_report_private.pieces (
  job_id uuid not null references sales_report_private.jobs(id) on delete cascade,
  generation uuid not null,
  part bigint not null,
  byte_start bigint not null,
  byte_end bigint not null,
  data bytea not null,
  primary key(job_id,generation,part)
);
create index sales_report_piece_bytes on sales_report_private.pieces(job_id,generation,byte_start);
alter table sales_report_private.state enable row level security;
alter table sales_report_private.jobs enable row level security;
alter table sales_report_private.pieces enable row level security;
revoke all on all tables in schema sales_report_private from public,anon,authenticated,service_role;

create function sales_report_private.source_version()
returns text language sql stable security invoker set search_path='' as $$
  select case when count(*)=2 then 'sales-report-v1:'||string_agg(source||':'||revision,',' order by source) end
  from public.stock_catalog_cache_revisions where source in ('sales_2026','branches');
$$;

-- Server counterpart of StoreBranchIdentityRegistry.displayName. Raw source names
-- never change. Contract/parity is tested against the Dart registry.
create function sales_report_private.display_branch(p_raw text,p_groups jsonb)
returns text language sql immutable security invoker set search_path='' as $$
  select case when p_groups->>upper(btrim(coalesce(p_raw,'')))='71'
    and left(btrim(coalesce(p_raw,'')),3)<>'71 '
    then '71 '||btrim(p_raw) else btrim(coalesce(p_raw,'')) end;
$$;
create function sales_report_private.csv_row(p_cells text[])
returns text language sql immutable security invoker set search_path='' as $$
  select string_agg('"'||replace(coalesce(cell,''),'"','""')||'"',',' order by ord)||E'\r\n'
  from unnest(p_cells) with ordinality c(cell,ord);
$$;

-- pg_net calls are committed asynchronously. Throttle repeated page polls.
select vault.create_secret(gen_random_uuid()::text||gen_random_uuid()::text,'sales_report_worker_token');
create function sales_report_private.dispatch()
returns void language plpgsql security definer set search_path='' as $$
declare token text;
begin
  update sales_report_private.state set dispatched_at=now()
  where singleton and (dispatched_at is null or dispatched_at<now()-interval '3 seconds');
  if not found then return; end if;
  select decrypted_secret into strict token from vault.decrypted_secrets where name='sales_report_worker_token';
  perform net.http_post(
    url:='https://rzvxjkbraufqbfhvftcy.supabase.co/functions/v1/sales-report-worker',
    headers:=jsonb_build_object('Content-Type','application/json'),
    body:=jsonb_build_object('token',token), timeout_milliseconds:=10000);
end $$;

create function sales_report_private.api(p_months text[],p_request boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_version text; v_months text[]; v_job sales_report_private.jobs; v_state sales_report_private.state;
begin
  if auth.uid() is null or public.item_tracker_my_role() is distinct from 'inventory' then
    raise exception 'Inventory access required' using errcode='42501';
  end if;
  v_version:=sales_report_private.source_version();
  if v_version is null then raise exception 'Sales source revision unavailable'; end if;
  if p_request then
    select * into v_state from sales_report_private.state where singleton for update;
  else
    select * into v_state from sales_report_private.state where singleton;
  end if;
  if v_state.metadata_version is distinct from v_version then perform sales_report_private.dispatch(); end if;
  if coalesce(cardinality(p_months),0)>0 then
    if cardinality(p_months)>120 or exists(select 1 from unnest(p_months) m where m is null or m !~ '^(0[1-9]|1[0-2])/[0-9]{4}$') then
      raise exception 'Invalid month selection' using errcode='22023';
    end if;
    select array_agg(m order by right(m,4),left(m,2)) into v_months from (select distinct unnest(p_months) m) x;
    if exists(select 1 from unnest(v_months) m where not exists(
      select 1 from jsonb_array_elements(v_state.months) a where a->>'month'=m)) then
      raise exception 'Selected month is not available; refresh the month list' using errcode='22023';
    end if;
    if p_request then
      insert into sales_report_private.jobs(months,priority) values(v_months,0)
      on conflict(months) do update set priority=0,requested_at=now();
      select * into v_job from sales_report_private.jobs where months=v_months for update;
      if v_job.status='failed' or (v_job.source_version is not null and v_job.source_version<>v_version) then
        delete from sales_report_private.pieces where job_id=v_job.id;
        update sales_report_private.jobs set status='queued',generation=gen_random_uuid(),source_version=null,
          prepared_at=null,finished_at=null,storage_path=null,upload_url=null,byte_size=null,row_count=null,
          uploaded_bytes=0,failures=0,last_error=null,next_attempt_at=now() where id=v_job.id;
      end if;
      perform sales_report_private.dispatch();
    end if;
    select * into v_job from sales_report_private.jobs where months=v_months;
  elsif p_request then
    raise exception 'Select at least one month' using errcode='22023';
  end if;
  return jsonb_build_object('months',v_state.months,'metadata_current',v_state.metadata_version=v_version,
    'heartbeat_at',v_state.heartbeat_at,'source_version',v_version,
    'job',case when v_job.id is null then null else jsonb_build_object(
      'id',v_job.id,'generation',v_job.generation,'months',v_job.months,'status',v_job.status,
      'is_current',v_job.source_version=v_version,'row_count',v_job.row_count,'byte_size',v_job.byte_size,
      'uploaded_bytes',v_job.uploaded_bytes,'prepared_at',v_job.prepared_at,'finished_at',v_job.finished_at,
      'storage_path',case when v_job.status='ready' and v_job.source_version=v_version then v_job.storage_path end,
      'retrying',v_job.failures>0,'failed',v_job.status='failed') end);
end $$;
create function public.get_sales_report(p_months text[] default null,p_request boolean default false)
returns jsonb language sql security invoker set search_path='' as $$
  select sales_report_private.api(p_months,p_request);
$$;

-- Materialize one immutable snapshot into bounded pieces. The version, branch
-- metadata and source rows all use ONE SQL statement/MVCC snapshot. Duplicates
-- are preserved, no offset pagination or source writes are used.
create function sales_report_private.prepare(p_job uuid,p_lease uuid)
returns jsonb language plpgsql security invoker set search_path='' set timezone='UTC' set work_mem='16MB' as $$
declare j sales_report_private.jobs; result jsonb;
begin
  if not exists(select 1 from sales_report_private.state where singleton and lease=p_lease and lease_until>now()) then
    raise exception 'Worker lease expired';
  end if;
  select * into strict j from sales_report_private.jobs where id=p_job for update;
  if j.status<>'queued' then return to_jsonb(j); end if;
  delete from sales_report_private.pieces where job_id=j.id;
  with version as materialized (select sales_report_private.source_version() v),
  groups as materialized (select coalesce(jsonb_object_agg(upper(btrim(branch_name)),btrim(branch_group::text)),'{}') g from public.branches),
  numbered as (
    select row_number() over(order by right(h.month,4),left(h.month,2),h.branch_name,h.item_code,h.ctid) n,
      sales_report_private.csv_row(array[
        sales_report_private.display_branch(h.branch_name,g.g),h.item_code,h.item_name,h.month,
        h.cash::text,h.online::text,h.insurance::text,
        to_char(h.created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        h.total_sales::text,h.retail::text,h.sales_value::text]) line
    from public.sales_history h cross join groups g where h.month=any(j.months)
  ), chunks as (
    select 1+(n-1)/5000 part,convert_to(string_agg(line,'' order by n),'UTF8') data,count(*) rows
    from numbered group by (n-1)/5000
    union all select 0,convert_to(U&'\FEFF'||sales_report_private.csv_row(array[
      'branch_name','item_code','item_name','month','cash','online','insurance','created_at','total_sales','retail','sales_value']),'UTF8'),0
  ), positioned as (
    select part,data,rows,sum(octet_length(data)) over(order by part)::bigint byte_end from chunks
  ), saved as (
    insert into sales_report_private.pieces(job_id,generation,part,byte_start,byte_end,data)
    select j.id,j.generation,part,byte_end-octet_length(data),byte_end,data from positioned returning byte_end
  )
  update sales_report_private.jobs set source_version=(select v from version),
    row_count=(select sum(rows) from positioned),byte_size=(select max(byte_end) from saved),
    prepared_at=statement_timestamp(),storage_path=j.id::text||'/'||j.generation::text||'.csv',
    status='uploading',uploaded_bytes=0,upload_url=null
  where id=j.id returning to_jsonb(sales_report_private.jobs.*) into result;
  return result;
end $$;

-- Only service_role can reach this worker gateway. All privileged code lives
-- in the unexposed private schema, and every continuation is fenced by a lease.
create function sales_report_private.worker(p_action text,p_args jsonb)
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
        select array[a->>'month'],100 from jsonb_array_elements(s.months) a on conflict(months) do nothing;
      select array_agg(a->>'month' order by right(a->>'month',4),left(a->>'month',2)) into v_months
        from jsonb_array_elements(s.months) a;
      if cardinality(v_months)>1 then
        insert into sales_report_private.jobs(months,priority) values(v_months,200) on conflict(months) do nothing;
      end if;
      delete from sales_report_private.pieces p using sales_report_private.jobs q
        where q.id=p.job_id and q.source_version is distinct from s.metadata_version;
      update sales_report_private.jobs set status='queued',generation=gen_random_uuid(),source_version=null,
        storage_path=null,upload_url=null,byte_size=null,row_count=null,prepared_at=null,finished_at=null,
        uploaded_bytes=0,failures=0,last_error=null,next_attempt_at=now()
        where source_version is not null and source_version<>s.metadata_version;
    end if;
    select * into j from sales_report_private.jobs where status in ('queued','uploading') and next_attempt_at<=now()
      order by priority,requested_at limit 1 for update skip locked;
    if j.id is null then
      update sales_report_private.state set lease=null,lease_until=null where singleton and lease=v_lease;
      return null;
    end if;
    return jsonb_build_object('lease',v_lease,'job',to_jsonb(j));
  end if;
  v_lease:=(p_args->>'lease')::uuid;
  select * into s from sales_report_private.state where singleton and lease=v_lease and lease_until>now() for update;
  if not found then raise exception 'Worker lease expired'; end if;
  update sales_report_private.state set heartbeat_at=now(),lease_until=now()+interval '180 seconds' where singleton;
  if p_action='release' then
    update sales_report_private.state set lease=null,lease_until=null,dispatched_at=null where singleton;
    if exists(select 1 from sales_report_private.jobs where status in ('queued','uploading') and next_attempt_at<=now()) then
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
  if p_action='prepare' then return sales_report_private.prepare(j.id,v_lease); end if;
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
    if j.source_version is distinct from sales_report_private.source_version() then
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
create function public.sales_report_worker(p_action text,p_args jsonb default '{}')
returns jsonb language sql security invoker set search_path='' as $$
  select sales_report_private.worker(p_action,p_args);
$$;

create function sales_report_private.can_download(p_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and public.item_tracker_my_role()='inventory' and exists(
    select 1 from sales_report_private.jobs where storage_path=p_path and status='ready'
      and source_version=sales_report_private.source_version());
$$;
insert into storage.buckets(id,name,public,allowed_mime_types)
values('sales-report-exports','sales-report-exports',false,array['text/csv'])
on conflict(id) do nothing;
create policy sales_report_inventory_download on storage.objects for select to authenticated
  using(bucket_id='sales-report-exports' and sales_report_private.can_download(name));

revoke all on all functions in schema sales_report_private from public,anon,authenticated,service_role;
grant execute on function sales_report_private.api(text[],boolean),sales_report_private.can_download(text) to authenticated;
grant execute on function sales_report_private.worker(text,jsonb) to service_role;
revoke all on function public.get_sales_report(text[],boolean),public.sales_report_worker(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.get_sales_report(text[],boolean) to authenticated;
grant execute on function public.sales_report_worker(text,jsonb) to service_role;
select cron.schedule('sales-report-server-cache','* * * * *','select sales_report_private.dispatch();');
notify pgrst,'reload schema';
