-- Shared Sales Report UI, server-derived scopes and isolated cached CSV files.
alter table sales_report_private.jobs add column scope_key text not null default 'inventory';
alter table sales_report_private.jobs add column scope_user_id uuid;
alter table sales_report_private.jobs add column branch_names text[];
alter table sales_report_private.jobs drop constraint jobs_months_key;
alter table sales_report_private.jobs add constraint sales_report_scope_months_key unique(scope_key,months);
alter table sales_report_private.jobs add constraint sales_report_scope_shape check(
  (scope_key='inventory' and scope_user_id is null and branch_names is null)
  or (scope_key<>'inventory' and scope_user_id is not null and branch_names is not null and cardinality(branch_names)>0));
create table sales_report_private.scopes (
  scope_key text primary key,
  metadata_version text,
  months jsonb not null default '[]'
);
alter table sales_report_private.scopes enable row level security;
revoke all on sales_report_private.scopes from public,anon,authenticated,service_role;

-- No caller-supplied zone, user, scope key or branch filter is accepted.
create function sales_report_private.current_scope()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_role text; v_zones text[]; v_branches text[];
begin
  if auth.uid() is null then return null; end if;
  select lower(btrim(role)) into v_role from public.app_users
    where user_id=auth.uid() and is_active is not false limit 1;
  if v_role='inventory' then
    return jsonb_build_object('key','inventory','kind','inventory','label',null,'branches',null);
  end if;
  if v_role is distinct from 'zone_manager' then return null; end if;
  select coalesce(array_agg(distinct btrim(z.zone) order by btrim(z.zone)),array[]::text[])
    into v_zones from public.get_my_effective_zones() z where nullif(btrim(z.zone),'') is not null;
  select coalesce(array_agg(distinct btrim(b.branch_name) order by btrim(b.branch_name)),array[]::text[])
    into v_branches from public.branches b
    where b.is_active is true and b.zone=any(v_zones) and nullif(btrim(b.branch_name),'') is not null;
  return jsonb_build_object('key','zone:'||auth.uid()::text||':'||encode(sha256(convert_to(array_to_json(v_branches)::text,'UTF8')),'hex'),
    'kind','zone','label',array_to_string(v_zones,' + '),'user_id',auth.uid(),'branches',v_branches);
end $$;
revoke all on function sales_report_private.current_scope() from public,anon,authenticated,service_role;

create or replace function sales_report_private.api(p_months text[],p_request boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_version text; v_months text[]; v_job sales_report_private.jobs;
  v_state sales_report_private.state; v_scope jsonb; v_key text; v_branches text[];
  v_available jsonb; v_metadata_version text; v_all_months text[];
begin
  v_scope:=sales_report_private.current_scope();
  if v_scope is null then raise exception 'Inventory or Zone Manager access required' using errcode='42501'; end if;
  v_key:=v_scope->>'key';
  v_version:=sales_report_private.source_version();
  if v_version is null then raise exception 'Sales source revision unavailable'; end if;
  if v_scope->>'kind'='zone' then
    select coalesce(array_agg(x),array[]::text[]) into v_branches from jsonb_array_elements_text(v_scope->'branches') x;
    insert into sales_report_private.scopes(scope_key) values(v_key) on conflict do nothing;
    select metadata_version,months into v_metadata_version,v_available from sales_report_private.scopes where scope_key=v_key;
    if v_metadata_version is distinct from v_version then
      with version as materialized(select sales_report_private.source_version() v),
      months as (select month,count(*) as rows from public.sales_history
        where btrim(branch_name)=any(v_branches) and month ~ '^(0[1-9]|1[0-2])/[0-9]{4}$' group by month)
      update sales_report_private.scopes set metadata_version=(select v from version),
        months=(select coalesce(jsonb_agg(jsonb_build_object('month',month,'row_count',rows)
          order by right(month,4),left(month,2)),'[]') from months)
        where scope_key=v_key returning metadata_version,months into v_metadata_version,v_available;
    end if;
  end if;
  -- Keep the same lock order as the worker's short queue transactions.
  if p_request then
    select * into v_state from sales_report_private.state where singleton for update;
  else
    select * into v_state from sales_report_private.state where singleton;
  end if;
  if v_scope->>'kind'='inventory' then
    v_available:=v_state.months; v_metadata_version:=v_state.metadata_version;
  end if;
  if v_state.metadata_version is distinct from v_version then perform sales_report_private.dispatch(); end if;
  if v_scope->>'kind'='zone' and cardinality(v_branches)>0 then
    insert into sales_report_private.jobs(scope_key,scope_user_id,branch_names,months,priority)
      select v_key,auth.uid(),v_branches,array[a->>'month'],100 from jsonb_array_elements(v_available) a
      on conflict(scope_key,months) do nothing;
    select array_agg(a->>'month' order by right(a->>'month',4),left(a->>'month',2)) into v_all_months
      from jsonb_array_elements(v_available) a;
    if cardinality(v_all_months)>1 then
      insert into sales_report_private.jobs(scope_key,scope_user_id,branch_names,months,priority)
        values(v_key,auth.uid(),v_branches,v_all_months,200) on conflict(scope_key,months) do nothing;
    end if;
    if exists(select 1 from sales_report_private.jobs where scope_key=v_key and status in ('queued','uploading')) then
      perform sales_report_private.dispatch();
    end if;
  end if;
  if coalesce(cardinality(p_months),0)>0 then
    if cardinality(p_months)>120 or exists(select 1 from unnest(p_months) m where m is null or m !~ '^(0[1-9]|1[0-2])/[0-9]{4}$') then
      raise exception 'Invalid month selection' using errcode='22023';
    end if;
    select array_agg(m order by right(m,4),left(m,2)) into v_months from (select distinct unnest(p_months) m) x;
    if exists(select 1 from unnest(v_months) m where not exists(
      select 1 from jsonb_array_elements(v_available) a where a->>'month'=m)) then
      raise exception 'Selected month is not available in your scope; refresh the month list' using errcode='22023';
    end if;
    if p_request then
      insert into sales_report_private.jobs(scope_key,scope_user_id,branch_names,months,priority)
        values(v_key,case when v_scope->>'kind'='zone' then auth.uid() end,v_branches,v_months,0)
        on conflict(scope_key,months) do update set priority=0,requested_at=now();
      select * into v_job from sales_report_private.jobs where scope_key=v_key and months=v_months for update;
      if v_job.status='failed' or (v_job.source_version is not null and v_job.source_version<>v_version) then
        delete from sales_report_private.pieces where job_id=v_job.id;
        update sales_report_private.jobs set status='queued',generation=gen_random_uuid(),source_version=null,
          prepared_at=null,finished_at=null,storage_path=null,upload_url=null,byte_size=null,row_count=null,
          uploaded_bytes=0,failures=0,last_error=null,next_attempt_at=now() where id=v_job.id;
      end if;
      perform sales_report_private.dispatch();
    end if;
    select * into v_job from sales_report_private.jobs where scope_key=v_key and months=v_months;
  elsif p_request then
    raise exception 'Select at least one month' using errcode='22023';
  end if;
  return jsonb_build_object('months',v_available,'metadata_current',v_metadata_version=v_version,
    'scope_kind',v_scope->>'kind','scope_label',v_scope->>'label',
    'heartbeat_at',v_state.heartbeat_at,'source_version',v_version,
    'job',case when v_job.id is null then null else jsonb_build_object(
      'id',v_job.id,'generation',v_job.generation,'months',v_job.months,'status',v_job.status,
      'is_current',v_job.source_version=v_version,'row_count',v_job.row_count,'byte_size',v_job.byte_size,
      'uploaded_bytes',v_job.uploaded_bytes,'prepared_at',v_job.prepared_at,'finished_at',v_job.finished_at,
      'storage_path',case when v_job.status='ready' and v_job.source_version=v_version then v_job.storage_path end,
      'retrying',v_job.failures>0,'failed',v_job.status='failed') end);
end $$;

create or replace function sales_report_private.current_month_info()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_today date := (statement_timestamp() at time zone 'Asia/Dubai')::date;
  v_month_start date; v_last_day date; v_scope jsonb; v_branches text[];
begin
  v_scope:=sales_report_private.current_scope();
  if v_scope is null then raise exception 'Inventory or Zone Manager access required' using errcode='42501'; end if;
  v_month_start:=date_trunc('month',v_today)::date;
  if v_scope->>'kind'='zone' then
    select coalesce(array_agg(x),array[]::text[]) into v_branches from jsonb_array_elements_text(v_scope->'branches') x;
    select inv_date into v_last_day from public.sales_last_45_days
      where inv_date>=v_month_start and inv_date<=v_today and btrim(branch_name)=any(v_branches)
      order by inv_date desc limit 1;
  else
    select inv_date into v_last_day from public.sales_last_45_days
      where inv_date>=v_month_start and inv_date<=v_today order by inv_date desc limit 1;
  end if;
  return jsonb_build_object('current_month',to_char(v_month_start,'MM/YYYY'),'current_month_last_day',v_last_day);
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
    and source_version=sales_report_private.source_version() and scope_key=v_scope->>'key'
    and ((v_scope->>'kind'='inventory' and scope_user_id is null and branch_names is null)
      or (v_scope->>'kind'='zone' and scope_user_id=auth.uid() and branch_names=v_branches)));
end $$;

-- Format/scope version changes revoke old cached download eligibility immediately.
create or replace function sales_report_private.source_version()
returns text language sql stable security invoker set search_path='' as $$
  select case when count(*)=2 then 'sales-report-v3:'||string_agg(source||':'||revision,',' order by source) end
  from public.stock_catalog_cache_revisions where source in ('sales_2026','branches');
$$;

create or replace function sales_report_private.prepare(p_job uuid,p_lease uuid)
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
      array_to_string(array[
        '"'||replace(coalesce(sales_report_private.display_branch(h.branch_name,g.g),''),'"','""')||'"',
        '"'||replace(coalesce(h.item_code,''),'"','""')||'"',
        '"'||replace(coalesce(h.item_name,''),'"','""')||'"',
        '"'||replace(coalesce(h.month,''),'"','""')||'"',
        '"'||replace(coalesce(h.cash::text,''),'"','""')||'"',
        '"'||replace(coalesce(h.online::text,''),'"','""')||'"',
        '"'||replace(coalesce(h.insurance::text,''),'"','""')||'"',
        '"'||replace(coalesce(h.total_sales::text,''),'"','""')||'"',
        '"'||replace(coalesce(h.retail::text,''),'"','""')||'"',
        '"'||replace(coalesce(h.sales_value::text,''),'"','""')||'"'],',')||E'\r\n' line
    from public.sales_history h cross join groups g where h.month=any(j.months) and (
      (j.scope_key='inventory' and j.scope_user_id is null)
      or (j.scope_user_id is not null and btrim(h.branch_name)=any(j.branch_names)))
  ), chunks as (
    select 1+(n-1)/5000 part,convert_to(string_agg(line,'' order by n),'UTF8') data,count(*) rows
    from numbered group by (n-1)/5000
    union all select 0,convert_to(U&'\FEFF'||sales_report_private.csv_row(array[
      'branch_name','item_code','item_name','month','cash','online','insurance','total_sales','retail','sales_value']),'UTF8'),0
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
  -- Preparation holds only its job row, keeping other selections responsive.
  -- Its immutable generation and the 180-second lease fence the continuation.
  if p_action='prepare' then
    select * into strict j from sales_report_private.jobs where id=(p_args->>'id')::uuid
      and generation=(p_args->>'generation')::uuid for update;
    return sales_report_private.prepare(j.id,v_lease);
  end if;
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


notify pgrst,'reload schema';
