-- Extend Sales Report only. Existing source rows, RLS, imports and other caches
-- remain unchanged. 2025 uses its authoritative archive, never an overlapping
-- copy in the newer history table. All branch filters still come from current_scope.
create function sales_report_private.history_2025_version()
returns text language sql stable security invoker set search_path='' as $$
  select case when count(*)=2 then 'sales-report-2025-v1:'||string_agg(source||':'||revision,',' order by source) end
  from public.stock_catalog_cache_revisions where source in ('sales_2025','branches');
$$;
create or replace function sales_report_private.monthly_version(p_months text[])
returns text language sql stable security invoker set search_path='' as $$
  select case
    when exists(select 1 from unnest(p_months) m where right(m,4)='2025') then
      case when exists(select 1 from unnest(p_months) m where right(m,4)<>'2025')
        then sales_report_private.source_version()||':archive:'||sales_report_private.history_2025_version()
        else sales_report_private.history_2025_version() end
    else sales_report_private.source_version() end || case
    when to_char(sales_report_private.current_month_start(),'MM/YYYY')=any(p_months)
    then ':current:'||sales_report_private.daily_version() else '' end;
$$;
create or replace function sales_report_private.monthly_metadata_version()
returns text language sql stable security invoker set search_path='' as $$
  select sales_report_private.source_version()||':archive:'||sales_report_private.history_2025_version()||
    ':calendar:'||sales_report_private.current_month_start()::text||':months:'||sales_report_private.daily_version();
$$;

create or replace function sales_report_private.monthly_rows(p_months text[],p_branches text[])
returns table(branch_name text,item_code text,item_name text,month text,cash numeric,
  online numeric,insurance numeric,total_sales numeric,retail numeric,sales_value numeric)
language sql stable security invoker set search_path='' as $$
  with bounds as (
    select sales_report_private.current_month_start() as first,
      sales_report_private.daily_expected_day() as last,
      to_char(sales_report_private.current_month_start(),'MM/YYYY') as month
  ), classified as (
    select d.branch_name,d.item_code,d.item_name,coalesce(d.qty,0) qty,
      case when lower(regexp_replace(btrim(coalesce(d.inv_type,'')),'[[:space:]]+',' ','g'))
          in ('insurance','direct insurance','dirict insurance') then 'insurance'
        when lower(btrim(coalesce(d.sales_type,''))) in ('delivery invoice','return delivery invoice') then 'online'
        else 'cash' end channel
    from public.sales_last_45_days d cross join bounds b
    where b.month=any(p_months) and d.inv_date between b.first and b.last
      and (p_branches is null or btrim(d.branch_name)=any(p_branches))
  )
  select h.branch_name,h.item_code,h.item_name,h.month,h.cash,h.online,h.insurance,h.total_sales,h.retail,h.sales_value
    from public.sales_history h cross join bounds b
    where h.month=any(p_months) and h.month<>b.month and right(h.month,4)<>'2025'
      and (p_branches is null or btrim(h.branch_name)=any(p_branches))
  union all
  select h.branch_name,h.item_code,h.item_name,h.month,h.cash,h.online,h.insurance,h.total_sales,h.retail,h.sales_value
    from public.sales_history_2025 h cross join bounds b
    where h.month=any(p_months) and h.month<>b.month and right(h.month,4)='2025'
      and (p_branches is null or btrim(h.branch_name)=any(p_branches))
  union all
  select d.branch_name,d.item_code,max(nullif(d.item_name,'')),(select b.month from bounds b),
    coalesce(sum(d.qty) filter(where channel='cash'),0),
    coalesce(sum(d.qty) filter(where channel='online'),0),
    coalesce(sum(d.qty) filter(where channel='insurance'),0),sum(d.qty),null::numeric,null::numeric
  from classified d group by d.branch_name,d.item_code;
$$;

create or replace function sales_report_private.available_months(p_branches text[])
returns jsonb language sql stable security invoker set search_path='' as $$
  with bounds as (
    select sales_report_private.current_month_start() as first,
      sales_report_private.daily_expected_day() as last,
      to_char(sales_report_private.current_month_start(),'MM/YYYY') as month
  ), months as (
    select h.month,count(*) rows,'history'::text source,null::date through
    from public.sales_history h cross join bounds b
    where h.month ~ '^(0[1-9]|1[0-2])/[0-9]{4}$' and h.month<>b.month and right(h.month,4)<>'2025'
      and (p_branches is null or btrim(h.branch_name)=any(p_branches)) group by h.month
    union all
    select h.month,count(*) rows,'history_2025'::text source,null::date through
    from public.sales_history_2025 h cross join bounds b
    where h.month ~ '^(0[1-9]|1[0-2])/[0-9]{4}$' and h.month<>b.month and right(h.month,4)='2025'
      and (p_branches is null or btrim(h.branch_name)=any(p_branches)) group by h.month
    union all
    select b.month,count(distinct (d.branch_name,d.item_code)),'daily',max(d.inv_date)
    from public.sales_last_45_days d cross join bounds b
    where d.inv_date between b.first and b.last
      and (p_branches is null or btrim(d.branch_name)=any(p_branches))
    group by b.month
  )
  select coalesce(jsonb_agg(jsonb_build_object('month',month,'row_count',rows,'source',source,'through',through)
    order by right(month,4),left(month,2)),'[]') from months;
$$;


-- Prewarm individual months and each year's complete range. Mixed-year ranges
-- are cached on request instead of generating every multi-year combination.
create function sales_report_private.prewarm_months(p_scope jsonb,p_branches text[],p_available jsonb)
returns void language plpgsql security invoker set search_path='' as $$
declare selected_months text[];
begin
  insert into sales_report_private.jobs(scope_key,scope_user_id,branch_names,months,priority)
    select p_scope->>'key',case when p_scope->>'kind'='zone' then auth.uid() end,p_branches,array[m->>'month'],100
    from jsonb_array_elements(p_available) m on conflict(scope_key,months) do nothing;
  for selected_months in
    select array_agg(m->>'month' order by right(m->>'month',4),left(m->>'month',2))
      from jsonb_array_elements(p_available) m group by right(m->>'month',4) having count(*)>1
  loop
    insert into sales_report_private.jobs(scope_key,scope_user_id,branch_names,months,priority)
      values(p_scope->>'key',case when p_scope->>'kind'='zone' then auth.uid() end,p_branches,selected_months,200)
      on conflict(scope_key,months) do nothing;
  end loop;
end $$;

create or replace function sales_report_private.api(p_months text[],p_request boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare scope jsonb; names text[]; available jsonb; meta_version text; selected_months text[];
  j sales_report_private.jobs; s sales_report_private.state; waiting boolean;
begin
  scope:=sales_report_private.current_scope();
  if scope is null then raise exception 'Inventory or Zone Manager access required' using errcode='42501'; end if;
  if scope->>'kind'='zone' then
    select coalesce(array_agg(b),array[]::text[]) into names from jsonb_array_elements_text(scope->'branches') b;
  end if;
  perform 1 from sales_report_private.state where singleton for update;
  perform sales_report_private.sync_daily();
  perform sales_report_private.refresh_monthly_metadata('inventory',null);
  if scope->>'kind'='zone' then
    perform sales_report_private.refresh_monthly_metadata(scope->>'key',names);
    select metadata_version,sc.months into meta_version,available from sales_report_private.scopes sc where scope_key=scope->>'key';
  else
    select metadata_version,st.months into meta_version,available from sales_report_private.state st where singleton;
  end if;
  perform sales_report_private.prewarm_months(scope,names,available);
  selected_months:=null;
  if coalesce(cardinality(p_months),0)>0 then
    if cardinality(p_months)>120 or exists(select 1 from unnest(p_months) m where m is null or m !~ '^(0[1-9]|1[0-2])/[0-9]{4}$') then
      raise exception 'Invalid month selection' using errcode='22023'; end if;
    select array_agg(m order by right(m,4),left(m,2)) into selected_months from (select distinct unnest(p_months) m) selected;
    if exists(select 1 from unnest(selected_months) month where not exists(select 1 from jsonb_array_elements(available) m where m->>'month'=month)) then
      raise exception 'Selected month is not available in your scope; refresh the month list' using errcode='22023'; end if;
    if p_request then
      insert into sales_report_private.jobs(scope_key,scope_user_id,branch_names,months,priority)
        values(scope->>'key',case when scope->>'kind'='zone' then auth.uid() end,names,selected_months,0)
        on conflict(scope_key,months) do update set priority=0,requested_at=now();
      select * into j from sales_report_private.jobs q where scope_key=scope->>'key' and q.months=selected_months for update;
      if j.status='failed' or (j.source_version is not null and j.source_version<>sales_report_private.monthly_version(selected_months)) then
        delete from sales_report_private.pieces where job_id=j.id;
        update sales_report_private.jobs set status='queued',generation=gen_random_uuid(),source_version=null,
          prepared_at=null,finished_at=null,storage_path=null,upload_url=null,byte_size=null,row_count=null,
          uploaded_bytes=0,failures=0,last_error=null,next_attempt_at=now() where id=j.id;
      end if;
    end if;
    select * into j from sales_report_private.jobs q where scope_key=scope->>'key' and q.months=selected_months;
  elsif p_request then raise exception 'Select at least one month' using errcode='22023'; end if;
  waiting:=coalesce(sales_report_private.needs_daily('monthly',selected_months),false) and not sales_report_private.daily_fresh();
  if exists(select 1 from sales_report_private.jobs q where scope_key=scope->>'key' and q.status in ('queued','uploading')
    and ((q.report_kind='daily45' and sales_report_private.daily_fresh()) or (q.report_kind='monthly'
      and sales_report_private.monthly_selection_available(q.months)
      and (not sales_report_private.needs_daily(q.report_kind,q.months) or sales_report_private.daily_fresh())))) then
    perform sales_report_private.dispatch();
  end if;
  select * into s from sales_report_private.state where singleton;
  return jsonb_build_object('months',available,'metadata_current',meta_version=sales_report_private.monthly_metadata_version(),
    'scope_kind',scope->>'kind','scope_label',scope->>'label','awaiting_update',waiting,
    'current_month_source','sales_last_45_days','heartbeat_at',s.heartbeat_at,'source_version',sales_report_private.monthly_version(selected_months),
    'job',case when j.id is null then null else jsonb_build_object('id',j.id,'generation',j.generation,'months',j.months,
      'status',j.status,'is_current',j.source_version=sales_report_private.monthly_version(selected_months) and not waiting,
      'row_count',j.row_count,'byte_size',j.byte_size,'uploaded_bytes',j.uploaded_bytes,'prepared_at',j.prepared_at,'finished_at',j.finished_at,
      'storage_path',case when j.status='ready' and j.source_version=sales_report_private.monthly_version(selected_months) and not waiting then j.storage_path end,
      'retrying',j.failures>0,'failed',j.status='failed') end);
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
    perform sales_report_private.sync_daily();
    v_version:=sales_report_private.monthly_metadata_version();
    if v_version is null then raise exception 'Sales source revision unavailable'; end if;
    if s.metadata_version is distinct from v_version then
      perform sales_report_private.refresh_monthly_metadata('inventory',null);
      select * into s from sales_report_private.state where singleton;
      perform sales_report_private.prewarm_months(jsonb_build_object('key','inventory','kind','inventory'),null,s.months);
    end if;
    -- APIs can refresh metadata before cron claims the queue; invalidate jobs
    -- independently of that metadata refresh so no stale ready cache gets stuck.
      delete from sales_report_private.pieces p using sales_report_private.jobs q
        where q.id=p.job_id and q.report_kind='monthly' and q.source_version is distinct from sales_report_private.monthly_version(q.months);
      update sales_report_private.jobs set status='queued',generation=gen_random_uuid(),source_version=null,
        storage_path=null,upload_url=null,byte_size=null,row_count=null,prepared_at=null,finished_at=null,
        uploaded_bytes=0,failures=0,last_error=null,next_attempt_at=now()
        where report_kind='monthly' and source_version is not null and source_version<>sales_report_private.monthly_version(months);
    select * into j from sales_report_private.jobs where status in ('queued','uploading') and next_attempt_at<=now()
      and ((report_kind='daily45' and sales_report_private.daily_fresh()) or (report_kind='monthly' and sales_report_private.monthly_selection_available(months) and (not sales_report_private.needs_daily(report_kind,months) or sales_report_private.daily_fresh())))
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
      and ((report_kind='daily45' and sales_report_private.daily_fresh()) or (report_kind='monthly' and sales_report_private.monthly_selection_available(months) and (not sales_report_private.needs_daily(report_kind,months) or sales_report_private.daily_fresh())))) then
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
    if j.source_version is distinct from sales_report_private.export_version(j.report_kind,j.months)
      or (sales_report_private.needs_daily(j.report_kind,j.months) and not sales_report_private.daily_fresh()) then
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





revoke all on function sales_report_private.history_2025_version(),
  sales_report_private.prewarm_months(jsonb,text[],jsonb) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
