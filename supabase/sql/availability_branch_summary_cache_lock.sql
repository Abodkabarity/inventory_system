-- Prevent concurrent dashboard sessions from rebuilding the same date cache.
create or replace function public.refresh_availability_branch_summary_cache_v2(
  p_run_date date default null
)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_run_date date;
  v_rows integer;
begin
  select coalesce(p_run_date, max(d.run_date))
  into v_run_date
  from public.daily_order as d;

  if v_run_date is null then
    return 0;
  end if;

  perform pg_advisory_xact_lock(
    hashtext('availability_branch_summary_cache_v2_' || v_run_date::text)
  );

  delete from public.availability_branch_summary_cache_v2
  where run_date = v_run_date;

  insert into public.availability_branch_summary_cache_v2 (
    run_date,
    branch_name,
    master_items,
    fully_available_items,
    shortage_items,
    pareto_items,
    consistent_items,
    weekly_need,
    branch_stock,
    covered_weekly_need,
    stock_shortage,
    availability_rate,
    calculated_at
  )
  select
    v_run_date,
    s.branch_name,
    s.master_items,
    s.fully_available_items,
    s.shortage_items,
    s.pareto_items,
    s.consistent_items,
    s.weekly_need,
    s.branch_stock,
    s.covered_weekly_need,
    s.stock_shortage,
    s.availability_rate,
    now()
  from public.get_availability_branch_summaries_v2(v_run_date) as s;

  get diagnostics v_rows = row_count;

  delete from public.availability_branch_summary_cache_v2
  where run_date < v_run_date - 14;

  return v_rows;
end;
$function$;

create or replace function public.ensure_availability_branch_summary_cache_v2(
  p_run_date date default null
)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_run_date date;
  v_rows integer;
begin
  select coalesce(p_run_date, max(d.run_date))
  into v_run_date
  from public.daily_order as d;

  if v_run_date is null then
    return 0;
  end if;

  perform pg_advisory_xact_lock(
    hashtext('availability_branch_summary_cache_v2_' || v_run_date::text)
  );

  select count(*)::integer
  into v_rows
  from public.availability_branch_summary_cache_v2 as c
  where c.run_date = v_run_date;

  if v_rows > 0 then
    return v_rows;
  end if;

  return public.refresh_availability_branch_summary_cache_v2(v_run_date);
end;
$function$;

grant execute on function public.ensure_availability_branch_summary_cache_v2(date)
to anon, authenticated, service_role;
