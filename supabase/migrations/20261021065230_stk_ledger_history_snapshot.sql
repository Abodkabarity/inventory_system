-- Dated ERP ledger snapshots; keep raw branch identities and system quantities.
-- Snapshot loading is one transaction across all requested companies.
create table public.stk_ledger_history (
  stock_date date not null,
  company text not null check (btrim(company) <> ''),
  branch_name text not null,
  source_branch_missing boolean generated always as (btrim(branch_name) = '') stored,
  item_code text not null check (btrim(item_code) <> ''),
  item_name text not null,
  actual_qty numeric not null,
  report_from_date date not null,
  report_to_date date not null,
  import_id uuid not null,
  source_file_sha256 text not null check (source_file_sha256 ~ '^[0-9a-f]{64}$'),
  imported_at timestamptz not null default now(),
  primary key (stock_date, company, branch_name, item_code),
  check (report_from_date = stock_date and report_to_date = stock_date),
  check (actual_qty not in ('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric))
);

create index stk_ledger_history_branch_item_date_idx
  on public.stk_ledger_history (branch_name, item_code, stock_date desc);

comment on table public.stk_ledger_history is
  'Raw Actual Qty from POSStockLadgerReport with FromDate=ToDate=stock_date. Zero rows present in the source are preserved; an absent row is unknown, not zero. No mismatch or pending-stock adjustment is applied.';
comment on column public.stk_ledger_history.imported_at is
  'Time of retrieval/import, distinct from the historical report date.';
comment on column public.stk_ledger_history.source_branch_missing is
  'Preserves an unassigned source row without guessing a branch. Exclude these rows from branch analysis.';

alter table public.stk_ledger_history enable row level security;
revoke all on public.stk_ledger_history from public, anon, authenticated;
grant select, insert on public.stk_ledger_history to service_role;
create policy stk_ledger_history_service_role
  on public.stk_ledger_history for all to service_role
  using (true) with check (true);
notify pgrst, 'reload schema';
