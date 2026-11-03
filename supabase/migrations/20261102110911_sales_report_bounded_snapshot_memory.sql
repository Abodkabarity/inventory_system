-- Keep branch-registry JSON out of the sales-row sort. Aggregate one 5,000-row
-- CSV piece at a time, rather than retaining all string_agg states in memory.
-- These planner settings apply only to this report function.
create or replace function sales_report_private.prepare(p_job uuid,p_lease uuid)
returns jsonb language plpgsql security invoker set search_path='' set timezone='UTC' set work_mem='8MB' set enable_hashagg='off' as $$
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
      h.branch_name,h.item_code,h.item_name,h.month,h.cash,h.online,h.insurance,h.total_sales,h.retail,h.sales_value
    from public.sales_history h where h.month=any(j.months) and (
      (j.scope_key='inventory' and j.scope_user_id is null)
      or (j.scope_user_id is not null and btrim(h.branch_name)=any(j.branch_names)))
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




notify pgrst,'reload schema';
