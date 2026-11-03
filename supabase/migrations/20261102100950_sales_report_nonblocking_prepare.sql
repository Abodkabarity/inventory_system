-- Escape cells inline; keep expensive preparation independent of the global lease row.
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
        '"'||replace(coalesce(to_char(h.created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),''),'"','""')||'"',
        '"'||replace(coalesce(h.total_sales::text,''),'"','""')||'"',
        '"'||replace(coalesce(h.retail::text,''),'"','""')||'"',
        '"'||replace(coalesce(h.sales_value::text,''),'"','""')||'"'],',')||E'\r\n' line
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
