-- Mismatch must follow verified daily replacements as well as the original
-- monthly imports. A daily replacement intentionally invalidates its old month.
-- Do not mark that immutable monthly source complete again.
create or replace function inventory_audit.coverage_periods()
returns table(company text,from_date date,to_date date,complete boolean,
  expected_rows bigint,committed_rows bigint,updated_at timestamptz)
language sql stable security invoker set search_path='' as $$
  select p.company,p.from_date,p.to_date,p.complete,
    p.expected_rows::bigint,p.committed_rows::bigint,p.updated_at
  from public.stk_statement_history_load_progress p
  union all
  select d.company,d.report_date,d.report_date,
    -- A report downloaded during its own day is still a partial-day source.
    (d.requested_at at time zone 'Asia/Dubai')::date>d.report_date,
    d.row_count,d.row_count,d.published_at
  from stk_history_ingest_private.day_state d
  join stk_history_ingest_private.publications p
    on p.run_id=d.run_id and p.report_date=d.report_date
  where p.receipt->>'published'='true'
    and p.receipt->>'report_date'=d.report_date::text
    and p.expected ?& array['APG','71 Pharmacy L.L.C.']
    and p.expected->d.company->>'sha256'=d.source_sha256
    and (p.expected->d.company->>'rows')::bigint=d.row_count
    and (p.expected->d.company->>'quantity')::numeric=d.quantity_sum;
$$;
revoke all on function inventory_audit.coverage_periods() from public,anon,authenticated;
grant execute on function inventory_audit.coverage_periods() to service_role;

create or replace function inventory_audit.source_version() returns text
language sql stable security invoker set search_path='' as $$
  -- Include partial-day writes too: the underlying movements already changed,
  -- so a previously cached verdict must not survive the new source snapshot.
  select md5(jsonb_build_object('rules','daily-coverage-v1',
    'monthly',(select coalesce(jsonb_agg(jsonb_build_array(p.company,p.from_date,p.to_date,
        p.complete,p.expected_rows,p.committed_rows,p.source_file_sha256,p.committed_quantity_sum)
        order by p.company,p.from_date,p.to_date),'[]')
      from public.stk_statement_history_load_progress p
      where p.complete and p.committed_rows=p.expected_rows),
    'daily',(select coalesce(jsonb_agg(jsonb_build_array(d.company,d.report_date,d.run_id,
        d.source_sha256,d.row_count,d.quantity_sum,extract(epoch from d.requested_at),
        extract(epoch from d.published_at)) order by d.company,d.report_date),'[]')
      from stk_history_ingest_private.day_state d))::text);
$$;

-- Keep the established classification and authorization bodies intact. Fail
-- rather than silently applying to an unexpected version of either function.
do $migration$
declare definition text; old_fragment text; new_fragment text;
begin
  old_fragment:='for period in select * from public.stk_statement_history_load_progress';
  new_fragment:='for period in select * from inventory_audit.coverage_periods()';
  definition:=pg_get_functiondef('inventory_audit.compute_review(bigint)'::regprocedure);
  if strpos(definition,old_fragment)>0 then
    execute replace(definition,old_fragment,new_fragment);
  elsif strpos(definition,new_fragment)=0 then
    raise exception 'Unexpected mismatch compute_review coverage source';
  end if;

  old_fragment:='from public.stk_statement_history_load_progress)p)';
  new_fragment:='from inventory_audit.coverage_periods())p)';
  definition:=pg_get_functiondef('inventory_audit.review_page(bigint,integer,text)'::regprocedure);
  if strpos(definition,old_fragment)>0 then
    execute replace(definition,old_fragment,new_fragment);
  elsif strpos(definition,new_fragment)=0 then
    raise exception 'Unexpected mismatch review_page coverage source';
  end if;
end $migration$;
