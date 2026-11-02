-- Phase 1: improve planner estimates for the existing normalized MRN filters.
-- Optimizer metadata only: no source/snapshot rows, RPC definitions, RLS,
-- presentation/export labels, bulk limits, or timeout settings are changed.
-- The local timeouts below bound this migration, not application requests.
set local lock_timeout = '3s';
set local statement_timeout = '60s';

create statistics public.stock_mrn_receipt_filter_stats (mcv, dependencies)
  on (lower(btrim(status))), (lower(btrim(warehouse)))
  from public.mrn_apg_2026;

comment on statistics public.stock_mrn_receipt_filter_stats is
  'Planner statistics for approved/warehouse expressions used by Stock Management. No business-data or filtering changes.';

-- Populate expression statistics immediately; auto-analyze maintains them later.
analyze public.mrn_apg_2026;
