# Stock Management — MRN Overview & Near Expiry

Inventory Dashboard → Stock Management → MRN Overview / Near Expiry (a separate
expandable sidebar workspace, outside Operations). Access is restricted to
the existing `inventory` role by RLS; no service credentials are shipped to Flutter.

The separate **Overview** now includes the complete Item Report catalog. Its
sources, formulas and verification are documented in `stock_catalog_overview.md`.

## Sources and calculations

- Products: `mrn_apg_2026`, approved receipts in STORE / Main Virtual / New Virtual,
  matching the import filtering. Supplier is Category 3; company is Category 4;
  vendor remains a separate field.
- Latest receipt: most recent MRN date per item. If several documents share a date,
  MRN number descending is the deterministic tie-breaker (the source has no receipt
  time). Received quantity sums the document's split/batch rows, not all receipts
  on that day.
- Current branch stock: `daily_order.branch_stock + total_final_reorder_today`
  from the latest uploaded run date. Each normalized item/branch is counted once;
  duplicate raw names use the newest `created_at` (raw name breaks timestamp ties).
  Negative stock is preserved; null/negative final allocations contribute zero.
  Missing Daily Order rows or null `branch_stock` fall back to `stk_ledger.actual_qty`.
  Ledger duplicates retain the maximum-quantity rule. Active registered branches
  include APG and group 71; inactive/virtual/expired warehouses are excluded.
  STORE remains its ledger quantity, with no final reorder added.
- Total stock = STORE + active branches. STORE/branches is a ratio, not a percentage
  of total; it is unavailable when branches stock is zero or negative.
- Days on hand = total stock / average daily **net units** in `sales_last_45_days`
  for the same active branches. The denominator covers up to 45 calendar days ending
  on the latest available sales date, not the computer's current date. Returns
  remain signed. Non-positive stock displays No Stock; positive stock with no
  positive net demand displays No Recent Sales rather than invented coverage.
- Sales 2025: `sales_history_2025`; sales 2026: `sales_history` (the actual current
  table name). Cash, Insurance and Online are net quantities, **not currency**.
  Annual totals include all source branches, not just the current active list.
- Best month is the greatest positive Cash + Insurance + Online net quantity in
  each year. Ties select the earlier month. With no positive month it is unavailable.
  The current month's 2026 data can be partial and is included as uploaded.

The shared effective balance feeds Overview, MRN Overview, Near Expiry (including
saved receipt-only products), branch detail/stocked counts, days on hand, stock
statuses, stock/sales ratios, distribution coverage and exports. A zero-stock
branch with a positive final allocation counts as stocked when its resulting
balance is positive. Receipt quantities, expiry evidence and review fingerprints
remain historical facts. Rebuild after Daily Order imports/edits to publish the
atomic stock snapshots and invalidate register/detail caches for both roles.

`20261023061551_stock_effective_branch_balances.sql` introduces the internal
shared stock source. `supabase/tests/stock_effective_branch_balances_test.sql`
uses rollback-only source fixtures for zero-stock allocations, order-only group
71 branches, duplicate identities, old runs, signed/null quantities and fallback.
After rebuilding both registers, `stock_effective_snapshot_test.sql` reconciles
all published balances and derived fields against the current sources; rerun
after a rebuild if another user edits allocations during verification.
`test/stock_effective_balance_exports_test.dart` verifies branch coverage and
all three register exports, including group 71 presentation. Existing cache tests
cover revision invalidation and the complete 5,000-row bulk-loading contract.

The footer exposes source dates. Data is a snapshot of uploaded database tables,
not a new ERP pull. Filters operate on the latest MRN date, not all historic MRNs.

## Refresh and scale

`Refresh data` queues a one-shot database job and polls its state. Existing data
stays readable while it runs; a failed refresh preserves the previous complete
snapshot. The job removes itself after completion or a handled failure. Opening
the page resumes monitoring an already queued refresh. Refresh again after daily
imports to include newly uploaded source data.

The snapshot computes historical aggregates server-side. Page requests return 50
products (bounded to 100), with search, category/supplier/status/date filters and
sorting. Branch details and monthly chart data are fetched only when opening a
product. The table uses lazy rows and horizontal scrolling.

The first verified snapshot contained 9,581 products. Annual channel totals were
reconciled against both source years without differences. The current `sales_history`
table is intentionally untouched, as are the imported MRN and 2025 history tables.

## Verification

```powershell
flutter analyze --no-pub lib/domain/entities/stock_management.dart lib/data/datasources/remote/stock_management_remote_ds.dart lib/presentation/inventory_dashboard/page/stock_management_page.dart test/stock_management_test.dart
flutter test --no-pub test/stock_management_test.dart
flutter build web --release --no-pub
```

Widget tests cover pagination, search, filters, error/retry, background refresh,
detail views, desktop/compact layout, API parameters, and a portable golden image.

## Phase two — Expiry Watch

The Near Expiry sidebar entry opens the review workspace; Overview also has a
compact shortcut to it. The workspace's active counts include upcoming and expired date groups; the page defaults to upcoming
dates and offers separate expired/urgency queues. Rows are grouped by item code
and expiry date, **not** by product alone or the latest MRN only.

- The cutoff is today in `Asia/Dubai` plus **six calendar months**, exclusive
  (not a fixed 180 days). Expiry today is included; undated records are excluded.
- Source is approved `mrn_apg_2026` receipts in STORE/Main Virtual/New Virtual.
  Positive historic received quantities and positive current product stock are
  required. The existing source tables are not changed.
- There is **no current batch/expiry stock balance** in these sources. The UI
  explicitly labels historical MRN quantity separately from current product stock.
  These are review candidates, not confirmed remaining near-expiry quantities.
- Notes (up to 4,000 characters) and review state are shared persistently among
  inventory users in `stock_expiry_reviews`. Click Note/details or a row to edit.
- Save note leaves the alarm active. Mark reviewed removes it from active counts
  and queues; Reviewed retains the saved note. Reopen and immediate Undo restore
  it. Unsaved notes are protected by a discard confirmation.
- A review covers the exact item + date + receipt fingerprint. A different expiry
  or changed/new receipt reactivates the alarm without deleting the prior note.
  Fingerprints use grouped document/date/warehouse/quantity, so source reimports
  or numeric scale changes alone do not reactivate it.
- Writes go through a permission-checked private function with an invoker RPC.
  Browser clients have SELECT only on the review table. Optimistic version checks
  and a per-item/date advisory lock reject stale notes/reviews; a failed save
  keeps the user's text visible. Anonymous/non-inventory users cannot read or write.

The first verified October 7, 2026 view contained 1,515 upcoming date groups and
386 expired date groups across 1,368 stocked products. These are date-group counts,
not unique products or confirmed batch quantities. Reviews are never erased by
stock snapshot refreshes. Source stock dates are visible in the footer.

```powershell
flutter test --no-pub test/stock_management_test.dart test/stock_expiry_test.dart
```

Database checks verified note persistence, review/reopen, stale update rejection,
independent expiry dates, automatic receipt-change reactivation, and role access.
All test writes were rolled back; no real products were marked reviewed by tests.

## Inspection workspace redesign

Near Expiry cards show all overview facts immediately: total/STORE/branches stock,
STORE-to-branches ratio, days on hand, latest MRN date/number/quantity, both years'
Cash/Insurance/Online net units, and each year's best month. The API returns a
`product_data` object taken directly from the existing stock snapshot, excluding
large chart/branch arrays. This was reconciled across all 1,901 expiry candidates
with zero differences. Detailed monthly charts/branch balances remain available
through Product overview, loaded on demand.

Review notes are also previewed on each card, with larger typography and separate
note/review actions. The sidebar workspace expands/collapses with an active child
indicator and independently routes to Overview or Near Expiry. There are no
placeholder entries for future features. Existing review fingerprints and stored
notes are unchanged by this presentation update.
