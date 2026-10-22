-- Reuse the existing 6.5m-row statement index (branch_name,item_code,trans_date).
-- The small event-log index supports prior discrepancy lookups for the same pair.
create index if not exists mismatch_log_branch_item_changed_idx
  on public.mismatch_log(branch_name,item_code,changed_at);

create or replace function public.stock_mismatch_movement_evidence(
  p_branch text, p_item text, p_through date
) returns jsonb
language plpgsql stable security invoker
set search_path = pg_catalog, public
as $$
declare
  result jsonb;
begin
  if p_branch is null or btrim(p_branch)='' or p_item is null or btrim(p_item)=''
     or p_through is null or p_through not between date '2026-01-01' and date '2026-12-31' then
    raise exception 'Exact raw branch/item and a date in 2026 are required';
  end if;
  select jsonb_build_object(
    'baseline', (select coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb) from (
      select stock_date, company, actual_qty::text qty, imported_at, source_file_sha256
      from public.stk_ledger_history
      where branch_name=p_branch and item_code=p_item and stock_date=date '2026-01-01'
        and not source_branch_missing
    ) b),
    'movements', (select coalesce(jsonb_agg(to_jsonb(s) order by s.trans_date,s.archive_fingerprint),'[]'::jsonb) from (
      select company,trans_date,qty::text qty,mode,trans_type,trans_no,archive_fingerprint
      from public.stk_statement_history_2026
      where branch_name=p_branch and item_code=p_item
        and trans_date between date '2026-01-01' and p_through
    ) s),
    'events', (select coalesce(jsonb_agg(to_jsonb(e) order by e.changed_at,e.id),'[]'::jsonb) from (
      select id,action,changed_at,item_name,old_system_stock::text old_system_stock,
        old_actual_stock::text old_actual_stock,old_diff::text old_diff,
        new_system_stock::text new_system_stock,new_actual_stock::text new_actual_stock,
        new_diff::text new_diff
      from public.mismatch_log
      where branch_name=p_branch and item_code=p_item
        and changed_at < p_through + interval '1 day'
    ) e)
  ) into result;
  return result;
end;
$$;
comment on function public.stock_mismatch_movement_evidence(text,text,date) is
  'Exact branch/item evidence only. Raw signed quantities; no absent=zero assumption. Daily dates cannot order same-day movements. Service-only and invoker RLS.';
revoke all on function public.stock_mismatch_movement_evidence(text,text,date) from public,anon,authenticated;
grant execute on function public.stock_mismatch_movement_evidence(text,text,date) to service_role;
notify pgrst, 'reload schema';
