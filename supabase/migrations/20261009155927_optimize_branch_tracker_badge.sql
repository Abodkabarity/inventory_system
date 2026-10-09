-- On an active project, build these two indexes CONCURRENTLY first using
-- supabase/sql/branch_tracker_badge_indexes_online.sql. The catalog checks below
-- skip CREATE INDEX entirely on that project, avoiding even its initial table
-- lock. Fresh installations can create the same indexes during their migration.
set local lock_timeout = '2s';

do $$
begin
  if to_regclass('public.idx_order_edits_tracker_changed_at') is null then
    execute 'create index idx_order_edits_tracker_changed_at
      on public.order_edits ((coalesce(updated_at, created_at)))';
  end if;
  if to_regclass('public.idx_max_adj_log_tracker_changed_at') is null then
    execute 'create index idx_max_adj_log_tracker_changed_at
      on public.max_adj_log ((coalesce(moved_at, created_at)))';
  end if;
end;
$$;

-- The drawer displays 999+, so reading beyond 1000 matching rows is unnecessary.
-- Each source is counted separately to avoid constructing the wide UNION view.
create or replace function public.get_branch_tracker_badge_count(
  p_since timestamptz,
  p_inclusive boolean default false
)
returns integer
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_added integer;
  -- These source columns are timestamp WITHOUT time zone. Converting the
  -- cutoff in the caller's session timezone preserves the existing view's
  -- timestamp-to-timestamptz comparison (the project's timezone is Asia/Dubai).
  v_since_local timestamp := p_since::timestamp;
begin
  if p_since is null then
    return 0;
  end if;

  select count(*)::integer into v_added
  from (
    select 1 from public.order_edits
    where coalesce(updated_at, created_at) >= p_since
      and (coalesce(p_inclusive, false) or coalesce(updated_at, created_at) > p_since)
    limit 1000
  ) matching;
  v_count := v_added;
  if v_count = 1000 then return v_count; end if;

  select count(*)::integer into v_added
  from (
    select 1 from public.max_adj
    where created_at >= p_since
      and (coalesce(p_inclusive, false) or created_at > p_since)
    limit (1000 - v_count)
  ) matching;
  v_count := v_count + v_added;
  if v_count = 1000 then return v_count; end if;

  select count(*)::integer into v_added
  from (
    select 1 from public.max_adj_log
    where coalesce(moved_at, created_at) >= v_since_local
      and (coalesce(p_inclusive, false) or coalesce(moved_at, created_at) > v_since_local)
    limit (1000 - v_count)
  ) matching;
  v_count := v_count + v_added;
  if v_count = 1000 then return v_count; end if;

  select count(*)::integer into v_added
  from (
    select 1 from public.mismatch_log
    where changed_at >= v_since_local
      and (coalesce(p_inclusive, false) or changed_at > v_since_local)
    limit (1000 - v_count)
  ) matching;
  v_count := v_count + v_added;
  if v_count = 1000 then return v_count; end if;

  select count(*)::integer into v_added
  from (
    select 1 from public.stk_mismatch
    where created_at >= p_since
      and (coalesce(p_inclusive, false) or created_at > p_since)
    limit (1000 - v_count)
  ) matching;
  return v_count + v_added;
end;
$$;

revoke all on function public.get_branch_tracker_badge_count(timestamptz, boolean)
  from public, anon;
grant execute on function public.get_branch_tracker_badge_count(timestamptz, boolean)
  to authenticated, service_role;

comment on function public.get_branch_tracker_badge_count(timestamptz, boolean)
  is 'Read-only inventory tracker badge count, capped at 1000; preserves the source view cutoff semantics.';

notify pgrst, 'reload schema';
