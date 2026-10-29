create schema if not exists sales_ingest_private;
revoke all on schema sales_ingest_private from public, anon, authenticated;

create table sales_ingest_private.daily_runs (
    run_id uuid primary key,
    report_date date not null,
    baseline text not null,
    created_at timestamptz not null default now(),
    result jsonb
);
create table sales_ingest_private.daily_batches (
    run_id uuid not null references sales_ingest_private.daily_runs on delete cascade,
    company text not null check (company in ('APG', '71')),
    batch_no integer not null check (batch_no >= 0),
    payload jsonb not null check (jsonb_typeof(payload) = 'array' and jsonb_array_length(payload) between 1 and 5000),
    primary key (run_id, company, batch_no)
);
alter table sales_ingest_private.daily_runs enable row level security;
alter table sales_ingest_private.daily_batches enable row level security;
revoke all on sales_ingest_private.daily_runs, sales_ingest_private.daily_batches
    from public, anon, authenticated, service_role;

create function sales_ingest_private.day_snapshot(p_date date)
returns text language sql stable set search_path = pg_catalog as $$
    select md5(coalesce(string_agg(to_jsonb(s)::text, E'\n' order by s.id), ''))
    from public.sales_last_45_days s where s.inv_date = p_date;
$$;
revoke all on function sales_ingest_private.day_snapshot(date) from public, anon, authenticated;

create function public.stage_sales_day_batch(
    p_run_id uuid, p_report_date date, p_company text, p_batch_no integer, p_data jsonb
)
returns void language plpgsql security definer set search_path = pg_catalog as $$
declare
    v_run sales_ingest_private.daily_runs%rowtype;
begin
    if p_run_id is null or p_report_date is null or p_company is null
       or p_company not in ('APG','71') or p_batch_no is null or p_batch_no < 0 then
        raise exception 'Invalid daily sales batch identity';
    end if;
    if jsonb_typeof(p_data) is distinct from 'array' then
        raise exception 'Sales payload must be an array';
    end if;
    if jsonb_array_length(p_data) not between 1 and 5000 then
        raise exception 'Daily sales batches must contain 1 to 5000 rows';
    end if;
    if exists (
        select 1 from jsonb_array_elements(p_data) r
        where jsonb_typeof(r) <> 'object'
          or not (r ?& array['branch_name','item_code','item_name','qty','inv_date','sales_type','inv_type','customer_name'])
          or btrim(coalesce(r->>'branch_name','')) = ''
          or btrim(coalesce(r->>'item_code','')) = ''
          or jsonb_typeof(r->'customer_name') is distinct from 'string'
          or (r->>'inv_date')::date is distinct from p_report_date
          or (r->>'qty')::numeric is null
          or (r->>'qty')::numeric::text in ('NaN','Infinity','-Infinity')
    ) then
        raise exception 'Invalid sales rows or invoice date outside the requested day';
    end if;

    -- An interrupted upload never changes the live sales snapshot.
    insert into sales_ingest_private.daily_runs(run_id,report_date,baseline)
    values(p_run_id,p_report_date,sales_ingest_private.day_snapshot(p_report_date))
    on conflict (run_id) do nothing;
    select * into strict v_run from sales_ingest_private.daily_runs
        where run_id=p_run_id for update;
    if v_run.report_date <> p_report_date then
        raise exception 'Daily sales run date changed';
    end if;
    if v_run.result is not null then return; end if;
    insert into sales_ingest_private.daily_batches(run_id,company,batch_no,payload)
    values(p_run_id,p_company,p_batch_no,p_data)
    on conflict (run_id,company,batch_no) do update set payload=excluded.payload;
end;
$$;

create function public.publish_sales_day(p_run_id uuid, p_expected jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare
    v_run sales_ingest_private.daily_runs%rowtype;
    v_company text;
    v_rows bigint;
    v_qty numeric;
    v_batches integer;
    v_min integer;
    v_max integer;
    v_actual jsonb := '{}'::jsonb;
    v_total bigint := 0;
    v_result jsonb;
begin
    select * into strict v_run from sales_ingest_private.daily_runs
        where run_id=p_run_id for update;
    -- A lost HTTP response can safely be retried after successful publication.
    if v_run.result is not null then return v_run.result; end if;
    if jsonb_typeof(p_expected) is distinct from 'object'
       or not (p_expected ?& array['APG','71']) then
        raise exception 'Both companies are required before publishing daily sales';
    end if;
    foreach v_company in array array['APG','71'] loop
        select count(*), min(batch_no), max(batch_no) into v_batches,v_min,v_max
        from sales_ingest_private.daily_batches where run_id=p_run_id and company=v_company;
        select count(*),coalesce(sum(x.qty),0) into v_rows,v_qty
        from sales_ingest_private.daily_batches b,
             lateral jsonb_to_recordset(b.payload) as x(qty numeric)
        where b.run_id=p_run_id and b.company=v_company;
        if v_rows=0 or v_min<>0 or v_max<>v_batches-1
           or v_batches is distinct from (p_expected->v_company->>'batches')::integer
           or v_rows is distinct from (p_expected->v_company->>'rows')::bigint
           or (p_expected->v_company->>'quantity') is null
           or abs(v_qty-(p_expected->v_company->>'quantity')::numeric)>0.000001 then
            raise exception 'Incomplete daily sales data for company %',v_company;
        end if;
        v_actual:=v_actual || jsonb_build_object(v_company,jsonb_build_object('rows',v_rows,'quantity',v_qty));
        v_total:=v_total+v_rows;
    end loop;
    if exists (
        select 1 from sales_ingest_private.daily_batches b,
            lateral jsonb_to_recordset(b.payload) as x(
                branch_name text,item_code text,inv_date date,sales_type text,inv_type text,customer_name text)
        where b.run_id=p_run_id
        group by x.branch_name,x.item_code,x.inv_date,
            coalesce(nullif(btrim(x.sales_type),''),'UNKNOWN'),
            coalesce(nullif(btrim(x.inv_type),''),'UNKNOWN'),btrim(x.customer_name)
        having count(*)>1
    ) then raise exception 'Duplicate daily sales identities'; end if;

    -- Hold the live-table lock only for snapshot verification and atomic publication.
    lock table public.sales_last_45_days in share row exclusive mode;
    if sales_ingest_private.day_snapshot(v_run.report_date) <> v_run.baseline then
        raise exception 'Sales snapshot changed during download; retry the daily import';
    end if;
    -- Only the requested day is refreshed, so retries never double quantities.
    delete from public.sales_last_45_days where inv_date=v_run.report_date;
    insert into public.sales_last_45_days(
        branch_name,item_code,item_name,qty,inv_date,sales_type,inv_type,customer_name)
    select x.branch_name,x.item_code,x.item_name,x.qty,x.inv_date,
        coalesce(nullif(btrim(x.sales_type),''),'UNKNOWN'),
        coalesce(nullif(btrim(x.inv_type),''),'UNKNOWN'),btrim(x.customer_name)
    from sales_ingest_private.daily_batches b,
         lateral jsonb_to_recordset(b.payload) as x(
             branch_name text,item_code text,item_name text,qty numeric,inv_date date,
             sales_type text,inv_type text,customer_name text)
    where b.run_id=p_run_id;
    v_result:=jsonb_build_object('report_date',v_run.report_date,'rows',v_total,'companies',v_actual,'published',true);
    update sales_ingest_private.daily_runs set result=v_result where run_id=p_run_id;
    delete from sales_ingest_private.daily_batches where run_id=p_run_id;
    -- Completed receipts are retained for retries; stale unpublished payloads expire.
    delete from sales_ingest_private.daily_runs
        where run_id<>p_run_id and created_at<now()-interval '7 days';
    return v_result;
end;
$$;

revoke all on function public.stage_sales_day_batch(uuid,date,text,integer,jsonb),
    public.publish_sales_day(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.stage_sales_day_batch(uuid,date,text,integer,jsonb),
    public.publish_sales_day(uuid,jsonb) to service_role;
notify pgrst,'reload schema';
