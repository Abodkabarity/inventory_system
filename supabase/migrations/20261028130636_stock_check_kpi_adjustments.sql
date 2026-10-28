-- Read-only, scoped Inventory API; raw statement history stays service-only.
create index if not exists stk_history_kpi_adjustment_pair_date_idx
on public.stk_statement_history_2026
  (lower(btrim(branch_name)),lower(btrim(item_code)),trans_date)
include(qty,company,created_at)
where lower(btrim(trans_type))='invadjustment';

create function inventory_audit.kpi_adjustments(
  p_project_ids uuid[], p_after_branch text default '',p_after_code text default '',
  p_limit int default 5000,p_snapshot text default null,p_through date default null
) returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public set statement_timeout='30s' as $$
declare
  first_year int; last_year int; from_day date; through_day date;
  token text; pairs_token text; source_token text; total_pairs int; payload jsonb;
begin
  perform inventory_audit.require_inventory();
  if coalesce(cardinality(p_project_ids),0) not between 1 and 64
    or p_limit is null or p_limit not between 1 and 5000
    or p_after_branch is null or p_after_code is null then
    raise exception 'Invalid KPI adjustment request (maximum 5000 rows)';
  end if;
  if exists(select 1 from unnest(p_project_ids) id where not exists(
    select 1 from public.stock_check_tasks t where t.batch_id=id and t.check_kind='kpi')) then
    raise exception 'Selected KPI project not found';
  end if;
  select min(kpi_year),max(kpi_year) into first_year,last_year
  from public.stock_check_tasks where batch_id=any(p_project_ids) and check_kind='kpi';
  if first_year is distinct from 2026 or last_year is distinct from 2026 then
    raise exception 'Adjustment history is available only for KPI year 2026';
  end if;
  -- Use the actual Q1 campaign date, never January 1 or a quarter label.
  select (min(sent_at) at time zone 'Asia/Dubai')::date into from_day
  from public.stock_check_tasks where check_kind='kpi' and kpi_year=first_year and kpi_quarter=1
    and (batch_id=any(p_project_ids) or not exists(select 1 from public.stock_check_tasks
      where batch_id=any(p_project_ids) and check_kind='kpi' and kpi_quarter=1));
  through_day:=coalesce(p_through,(now() at time zone 'Asia/Dubai')::date);
  if from_day is null then raise exception 'Q1 project date is unavailable'; end if;
  if from_day<date '2026-01-01' or through_day>date '2026-12-31'
    or through_day<from_day or through_day>(now() at time zone 'Asia/Dubai')::date then
    raise exception 'Unsupported adjustment date range';
  end if;
  select count(*),md5(coalesce(string_agg(b||chr(31)||c,chr(30) order by b,c),''))
  into total_pairs,pairs_token from (
    select distinct lower(btrim(branch_name)) b,lower(btrim(item_code)) c
    from public.stock_check_tasks where batch_id=any(p_project_ids)
  ) pairs;
  -- Daily receipts and monthly checkpoints both participate in snapshot checks.
  select md5(coalesce((select string_agg(to_jsonb(p)::text,'|' order by company,from_date)
    from public.stk_statement_history_load_progress p),'')||coalesce((
    select string_agg(to_jsonb(d)::text,'|' order by company,report_date)
    from stk_history_ingest_private.day_state d),'')||coalesce((
    select count(*)::text||coalesce(max(created_at)::text,'')
    from public.stk_statement_history_2026
    where lower(btrim(trans_type))='invadjustment' and trans_date between from_day and through_day),''))
  into source_token;
  token:=md5(pairs_token||source_token||from_day||through_day);
  if p_snapshot is not null and p_snapshot<>token then
    raise exception 'adjustment_snapshot_changed' using errcode='40001';
  end if;
  with pairs as materialized (
    select lower(btrim(branch_name)) b,lower(btrim(item_code)) c
    from public.stock_check_tasks where batch_id=any(p_project_ids)
    group by 1,2
  ), page as materialized (
    select b,c from pairs where (b,c)>(p_after_branch,p_after_code)
    order by b,c limit p_limit
  ), companies as (
    select lower(btrim(branch_name)) b,
      case when min(branch_group)=max(branch_group) then
        case min(branch_group) when '71' then '71 Pharmacy L.L.C.' when 'APG' then 'APG' end end company
    from public.branches group by 1
  ), coverage as materialized (
    select company,bool_and(exists(select 1 from public.stk_statement_history_load_progress m
      where m.company=co.company and m.complete and m.committed_rows=m.expected_rows
        and day::date between m.from_date and m.to_date)
      or exists(select 1 from stk_history_ingest_private.day_state d
        where d.company=co.company and d.report_date=day::date)) complete
    from (select distinct company from companies where company is not null) co
    cross join generate_series(from_day::timestamp,through_day::timestamp,interval '1 day') day
    group by company
  ), rows as (
    select p.b branch,p.c item_code,count(h.archive_fingerprint) movement_count,
      coalesce(sum(h.qty),0)::text qty,coalesce(v.complete,false) complete
    from page p
    left join public.stk_statement_history_2026 h
      on lower(btrim(h.branch_name))=p.b and lower(btrim(h.item_code))=p.c
      and lower(btrim(h.trans_type))='invadjustment'
      and h.trans_date between from_day and through_day
    left join companies co on co.b=p.b left join coverage v on v.company=co.company
    group by p.b,p.c,v.complete
  ) select jsonb_build_object('rows',coalesce(jsonb_agg(to_jsonb(r) order by branch,item_code),'[]'),
    'has_more',exists(select 1 from pairs where (b,c)>(select b,c from page order by b desc,c desc limit 1)),
    'next_branch',(select b from page order by b desc,c desc limit 1),
    'next_code',(select c from page order by b desc,c desc limit 1),
    'total',total_pairs,'snapshot',token,'from_date',from_day,'through_date',through_day)
  into payload from rows r;
  return payload;
end $$;

create function public.stock_check_kpi_adjustments(
  p_project_ids uuid[],p_after_branch text default '',p_after_code text default '',
  p_limit int default 5000,p_snapshot text default null,p_through date default null
) returns jsonb language sql stable security invoker set search_path=pg_catalog,public as $$
  select inventory_audit.kpi_adjustments(p_project_ids,p_after_branch,p_after_code,p_limit,p_snapshot,p_through);
$$;
revoke all on function inventory_audit.kpi_adjustments(uuid[],text,text,int,text,date) from public,anon;
grant execute on function inventory_audit.kpi_adjustments(uuid[],text,text,int,text,date) to authenticated;
revoke all on function public.stock_check_kpi_adjustments(uuid[],text,text,int,text,date) from public,anon;
grant execute on function public.stock_check_kpi_adjustments(uuid[],text,text,int,text,date) to authenticated;
comment on function public.stock_check_kpi_adjustments(uuid[],text,text,int,text,date) is
  'Inventory-only signed INVAdjustment sums per selected branch/item, actual Q1 campaign date through Dubai today; 5000-row keyset pages with source snapshot and coverage checks.';
notify pgrst,'reload schema';
