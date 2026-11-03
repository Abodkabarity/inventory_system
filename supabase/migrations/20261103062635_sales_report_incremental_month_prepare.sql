-- Durable monthly checkpoints keep large annual/cross-year exports below the
-- existing RPC timeout. Revisions fence every checkpoint and final publication.
alter table sales_report_private.jobs add column prepared_months integer not null default 0;

create or replace function sales_report_private.prepare(p_job uuid,p_lease uuid)
returns jsonb language plpgsql security invoker set search_path='' set timezone='UTC'
  set work_mem='8MB' set enable_hashagg='off' as $$
declare j sales_report_private.jobs; result jsonb; v_version text; v_month text;
  v_header bytea; v_part bigint; v_offset bigint; v_index integer;
begin
  if not exists(select 1 from sales_report_private.state where singleton and lease=p_lease and lease_until>now()) then
    raise exception 'Worker lease expired'; end if;
  select * into strict j from sales_report_private.jobs where id=p_job and report_kind='monthly' for update;
  if j.status<>'queued' then return to_jsonb(j); end if;
  v_version:=sales_report_private.monthly_version(j.months);
  if j.source_version is distinct from v_version or j.prepared_months=0 then
    delete from sales_report_private.pieces where job_id=j.id;
    if j.source_version is not null and j.source_version<>v_version then j.generation:=gen_random_uuid(); end if;
    v_header:=convert_to(U&'\FEFF'||sales_report_private.csv_row(array[
      'branch_name','item_code','item_name','month','cash','online','insurance','total_sales','retail','sales_value']),'UTF8');
    insert into sales_report_private.pieces(job_id,generation,part,byte_start,byte_end,data)
      values(j.id,j.generation,0,0,octet_length(v_header),v_header);
    update sales_report_private.jobs set source_version=v_version,generation=j.generation,prepared_months=0,
      row_count=0,byte_size=octet_length(v_header),uploaded_bytes=0,upload_url=null,
      prepared_at=null,finished_at=null,storage_path=j.id::text||'/'||j.generation::text||'.csv'
      where id=j.id returning * into j;
  end if;
  v_index:=j.prepared_months+1;
  v_month:=j.months[v_index];
  if v_month is null then raise exception 'Invalid monthly preparation checkpoint'; end if;
  select coalesce(max(part),0) into v_part from sales_report_private.pieces where job_id=j.id and generation=j.generation;
  v_offset:=j.byte_size;
  with version as materialized(select sales_report_private.monthly_version(j.months) v),
  groups as materialized (select coalesce(jsonb_object_agg(upper(btrim(branch_name)),btrim(branch_group::text)),'{}') g from public.branches),
  numbered as (
    select row_number() over(order by h.branch_name,h.item_code,h.item_name,
      h.cash,h.online,h.insurance,h.total_sales,h.retail,h.sales_value) n,h.*
    from sales_report_private.monthly_rows(array[v_month],j.branch_names) h
  ), lines as (
    select h.n,
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
    from numbered h cross join groups g
  ), chunks as (
    select 1+(n-1)/5000 part,convert_to(string_agg(line,'' order by n),'UTF8') data,count(*) rows
    from lines group by (n-1)/5000

  ), positioned as (
    select part,data,rows,sum(octet_length(data)) over(order by part)::bigint byte_end from chunks
  ), saved as (
    insert into sales_report_private.pieces(job_id,generation,part,byte_start,byte_end,data)
    select j.id,j.generation,v_part+part,v_offset+byte_end-octet_length(data),v_offset+byte_end,data
      from positioned returning byte_end
  )
  update sales_report_private.jobs set prepared_months=v_index,
    row_count=j.row_count+coalesce((select sum(rows) from positioned),0),
    byte_size=coalesce((select max(byte_end) from saved),v_offset),
    prepared_at=case when v_index=cardinality(j.months) then statement_timestamp() end,
    status=case when v_index=cardinality(j.months) then 'uploading' else 'queued' end,
    requested_at=now(),failures=0,last_error=null,next_attempt_at=now()
    where id=j.id and (select v from version)=j.source_version
    returning to_jsonb(sales_report_private.jobs.*) into result;
  if result is null then raise exception 'Monthly source changed during preparation'; end if;
  return result;
end $$;

-- Retry only preparation timeouts that this change addresses. Ready files and
-- unrelated failures retain their existing state and retry policy.
update sales_report_private.jobs set status='queued',next_attempt_at=now(),failures=0,last_error=null
  where report_kind='monthly' and status in ('queued','failed') and failures>0
    and last_error like '%statement timeout%';
notify pgrst,'reload schema';
