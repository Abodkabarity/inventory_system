-- Production: first run tools/cleanup_duplicate_indexes.py --apply.
-- That path uses DROP INDEX CONCURRENTLY, one index at a time.
-- Replay remains fail-fast and checks exact equivalence before any removal.
set local lock_timeout = '1s';
do $migration$
declare pair record; redundant oid; retained oid;
begin
  for pair in select * from (values
    ('idx_daily_order_run_date_branch', 'idx_daily_order_allocation_fast_2'),
    ('daily_order_run_branch_idx', 'idx_daily_order_allocation_fast_2'),
    ('idx_daily_order_allocation_run_branch', 'idx_daily_order_allocation_fast_2'),
    ('idx_daily_order_run_branch', 'idx_daily_order_allocation_fast_2'),
    ('daily_order_run_date_item_code_idx', 'idx_daily_order_allocation_fast_1'),
    ('daily_order_run_item_idx', 'idx_daily_order_allocation_fast_1'),
    ('idx_daily_order_allocation_run_item', 'idx_daily_order_allocation_fast_1'),
    ('idx_daily_order_run_date_item_code', 'idx_daily_order_allocation_fast_1'),
    ('idx_daily_order_run_item', 'idx_daily_order_allocation_fast_1'),
    ('idx_daily_order_allocation_run_status', 'idx_daily_order_allocation_fast_4'),
    ('idx_daily_order_allocation_run_category', 'idx_daily_order_allocation_fast_3'),
    ('idx_daily_order_allocation_run_min_unit', 'idx_daily_order_allocation_fast_5'),
    ('idx_daily_order_branch_run_date', 'idx_daily_order_branch_run'),
    ('daily_order_run_date_branch_item_code_idx', 'idx_daily_order_availability_lookup'),
    ('idx_daily_order_exports_unique', 'daily_order_exports_run_date_uidx'),
    ('daily_order_history_run_date_branch_idx1', 'daily_order_history_run_date_branch_idx'),
    ('daily_order_history_run_date_branch_idx2', 'daily_order_history_run_date_branch_idx'),
    ('daily_order_history_run_date_item_code_idx1', 'daily_order_history_run_date_item_code_idx'),
    ('daily_order_history_run_date_item_code_idx2', 'daily_order_history_run_date_item_code_idx'),
    ('daily_order_history_branch_run_date_idx1', 'daily_order_history_branch_run_date_idx'),
    ('daily_order_history_run_date_branch_item_code_idx', 'idx_daily_order_history_export'),
    ('idx_sales_90_days_branch_item', 'idx_sales_90_branch_item'),
    ('idx_stk_mismatch_branch_item', 'stk_mismatch_review_branch_item_idx')
  ) as pairs(redundant_name, retained_name) loop
    redundant := to_regclass('public.' || pair.redundant_name);
    if redundant is null then continue; end if;
    retained := to_regclass('public.' || pair.retained_name);
    if retained is null or not exists (
      select 1 from pg_index a join pg_index b on b.indexrelid=retained
      join pg_class ac on ac.oid=a.indexrelid join pg_class bc on bc.oid=b.indexrelid
      where a.indexrelid=redundant and a.indrelid=b.indrelid
        and a.indnatts=b.indnatts and a.indnkeyatts=b.indnkeyatts
        and ac.relam=bc.relam and a.indisunique=b.indisunique
        and a.indnullsnotdistinct=b.indnullsnotdistinct
        and a.indkey=b.indkey and a.indclass=b.indclass
        and a.indcollation=b.indcollation and a.indoption=b.indoption
        and a.indexprs::text is not distinct from b.indexprs::text
        and a.indpred::text is not distinct from b.indpred::text
        and a.indisvalid and a.indisready and b.indisvalid and b.indisready
        and not a.indisprimary and not a.indisreplident and not a.indisclustered
    ) or exists(select 1 from pg_constraint where conindid=redundant)
      or exists(select 1 from pg_depend where refclassid='pg_class'::regclass and refobjid=redundant)
    then raise exception 'Unsafe duplicate index cleanup: %',pair.redundant_name; end if;
  end loop;
end;
$migration$;
drop index if exists public.idx_daily_order_run_date_branch;
drop index if exists public.daily_order_run_branch_idx;
drop index if exists public.idx_daily_order_allocation_run_branch;
drop index if exists public.idx_daily_order_run_branch;
drop index if exists public.daily_order_run_date_item_code_idx;
drop index if exists public.daily_order_run_item_idx;
drop index if exists public.idx_daily_order_allocation_run_item;
drop index if exists public.idx_daily_order_run_date_item_code;
drop index if exists public.idx_daily_order_run_item;
drop index if exists public.idx_daily_order_allocation_run_status;
drop index if exists public.idx_daily_order_allocation_run_category;
drop index if exists public.idx_daily_order_allocation_run_min_unit;
drop index if exists public.idx_daily_order_branch_run_date;
drop index if exists public.daily_order_run_date_branch_item_code_idx;
drop index if exists public.idx_daily_order_exports_unique;
drop index if exists public.daily_order_history_run_date_branch_idx1;
drop index if exists public.daily_order_history_run_date_branch_idx2;
drop index if exists public.daily_order_history_run_date_item_code_idx1;
drop index if exists public.daily_order_history_run_date_item_code_idx2;
drop index if exists public.daily_order_history_branch_run_date_idx1;
drop index if exists public.daily_order_history_run_date_branch_item_code_idx;
drop index if exists public.idx_sales_90_days_branch_item;
drop index if exists public.idx_stk_mismatch_branch_item;
