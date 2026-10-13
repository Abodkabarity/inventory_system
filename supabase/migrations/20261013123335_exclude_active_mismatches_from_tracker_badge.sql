-- Count the same change sources displayed in Branches Tracker.
-- Current mismatches remain available in Mismatch Report.
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
  return v_count + v_added;
end;
$$;

revoke all on function public.get_branch_tracker_badge_count(timestamptz, boolean)
  from public, anon;
grant execute on function public.get_branch_tracker_badge_count(timestamptz, boolean)
  to authenticated, service_role;

comment on function public.get_branch_tracker_badge_count(timestamptz, boolean)
  is 'Read-only inventory tracker badge count, capped at 1000; excludes active mismatch snapshots; preserves the source view cutoff semantics.';

notify pgrst, 'reload schema';
