-- Run each statement separately, outside a transaction, before applying
-- optimize_branch_tracker_badge on a live database. Concurrent construction
-- permits branch INSERT/UPDATE/DELETE operations to continue.
create index concurrently if not exists idx_order_edits_tracker_changed_at
  on public.order_edits ((coalesce(updated_at, created_at)));

create index concurrently if not exists idx_max_adj_log_tracker_changed_at
  on public.max_adj_log ((coalesce(moved_at, created_at)));
