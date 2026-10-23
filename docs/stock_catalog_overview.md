# Item Report stock Overview

Stock Management has three independent entries: Overview, MRN Overview, Near Expiry.
Overview reads `item_report_apg`, resolving the latest import per nonempty trimmed
item code before filtering. It includes only `status = active`,
`is_block = unchecked` and Item Status number prefixes 1, 2 or 3 (for example
`1#NORMAL PURCHASE`). Comparisons trim whitespace and ignore case. At an equal
latest timestamp, a disallowed row takes precedence over an allowed duplicate;
remaining ties use the product facts for deterministic selection. An empty eligible
catalog aborts the rebuild and preserves the previous snapshot. MRN is not required.
The table includes Category, Supplier, Ingredient, Indication and Sub-category
as text columns with Excel-style filters and sorting. Excel includes the same facts.
The APG rebuild disables nested-loop joins only within its private builder:
correlated catalog eligibility predicates otherwise cause an estimate of one row
and repeated annual-sales scans. The caller's planner settings are restored.
All three Stock Management registers and product details show Created date from
`added_date_time` as `dd/MM/yyyy`, without a time (Overview uses `item_report_apg`;
MRN Overview and Near Expiry retain `item_report`). Timestamp values
are converted to the Asia/Dubai calendar day; date-only values stay unchanged.
Headers filter/sort actual dates. Missing Item Report identities/dates show —;
they are never replaced with MRN dates or import `created_at`. Catalog Excel uses
the same date-only formatting (empty cell for missing dates). The catalog/MRN
snapshot writers preserve this field on rebuild; expiry readers enrich both
current and saved product facts from Item Report without changing receipt/review
fingerprints or historical quantities.
The existing MRN and expiry tables, refreshes and review notes are unchanged.

The complete product register loads in background batches of up to 5,000 products
and rejects changes of snapshot version/count or duplicate codes between batches.
There is one continuous table with no visible pagination. Search, Status, Item Status,
category, supplier and sorting operate locally on the complete loaded catalog. Rows are
virtualized; monthly charts and branch details load only when opening a product.
Excel exports use the same filtered snapshot as the table and include all matching
products without additional page requests. Compact summary cards and a shorter
banner give the table more height. The footer and its pagination/source text are
removed; source dates and formula explanations remain in product details/exports.
The filter toolbar uses filled rounded search and selector controls, branded
selection menus and a compact export action. Its controls and product dialog
use AppColors.primaryColor explicitly for focus, selection and primary actions,
independent of the inherited Material theme's default accent.
Item Status uses Item Report's `item_status` purchase status, independently of
the calculated stock Status. Choices come from the complete register and include
Not specified for blank values. Status sorting supports A–Z and Z–A, keeps blank
statuses last in both directions, and orders products by name/code within each
status. The default is Item status A–Z, so `1#NORMAL PURCHASE` products appear
first on opening the page and after clearing filters. Excel includes Item status
and preserves the selected filters and order.
Every table header also offers the Daily Order grid's Excel-style menu: search
and select text values, numeric comparisons/ranges, and ascending/descending
sorting. Item Status is a separate column. Cells carry their actual text/numeric
values rather than item codes; cover conditions use days and stock ratios use
percentages. Undefined numeric values remain blank. Column filters combine with
toolbar filters and persist through search/sort changes, including zero matches.
Summary cards reflect column-filtered rows, and Excel uses the grid's effective
rows in displayed order. Clear filters resets both column filters and sorting.
Opening a filtered/sorted row resolves its product identity from the effective
row rather than its original position. Filtering controls use AppColors.primaryColor.
Branch labels, search and exported cells use StoreBranchIdentityRegistry, and
labels repaint when authoritative group metadata arrives.

## New product distribution

Overview has a Needs distribution card, Status option, priority sort, column
filters and Excel fields. Default rules are age 0–30 Dubai calendar days, STORE
stock ≥50, and at most six covered branches, with at least one eligible branch
still uncovered. MRN is not a condition for the distribution alert.
Rules can be changed via Distribution rules and are remembered
on the current device. No sales history is required for a new product.

STORE receipt facts come from `mrn_apg_2026`, grouped by product, MRN number and
MRN date with positive net received quantity. Pending/cancelled receipts, zero or
net-negative receipts, future receipts, receipts before creation, and virtual or
other warehouses do not qualify. `mrn_date` has no time, so same-day receipt and
creation qualify without claiming a precise intraday order. First/latest dates
and total qualified received units are preserved in the snapshot, table/detail
and Excel. Days in STORE starts at the first qualifying receipt and is not reset
by later deliveries. Receipt facts are informational only: missing, unapproved,
or out-of-range MRNs do not suppress the distribution alert or change its status.
The partial-distribution limit remains.

Covered means eligible branches with a positive effective balance after adding
Final Reorder; each branch counts once. Reorder demand remains
separate. The latest Daily Order run supplies order quantities, collapsed once per
normalized item/branch; Final Reorder uses `total_final_reorder_today`. This uses
the current day's requirements and allocations rather than historical runs or
the original pre-edit reorder calculation. Active non-warehouse branches and
their authoritative identities come from `branches`, including group 71.
NON formulary rows are excluded, respecting the existing New Item/TMA override.
Latest branch-formulary revisions are also respected.

Recommendations require a complete active-branch order matrix from today or
yesterday. Missing, future or older order data produces no recommendation;
the product details explain that data is unavailable. Future/missing Created date
is never treated as a new product. All eligible branches covered means no alert,
even if there are six or fewer eligible branches in total. STORE remaining after
final allocations must fund at least one minimum order unit (fallback 1), so
already-allocated stock cannot produce an actionable distribution flag.

Product details show age, stocked/reorder/final-order/eligible counts, available
STORE stock, an explanation, source dates, and a filter for uncovered eligible
branches. Branch labels/search/Excel use StoreBranchIdentityRegistry. Final orders
are planned allocation, not proof of delivery. Counts and order details share
the stock snapshot: Rebuild data after order edits/imports to recalculate them.
List RPCs omit the branch-order map to keep the virtualized register lightweight.
The existing daily/manual catalog rebuild updates all facts atomically.

## Stock and demand calculations

The shared product dialog includes a Sales 45 Days stacked daily chart below the
monthly chart. It uses the same snapshot window, active branches and signed net
Qty as the 45-day KPI. Cash and Online keep the existing sales classification:
Delivery Invoice / Return Delivery Invoice are Online; remaining non-insurance
sales are Cash. Insurance / Direct Insurance (including the source typo Dirict
Insurance) are split by exact normalized customer name into Insurance Basic
(`National Health Insurance Company - Daman Basic`), Insurance Thiqa
(`National Health Insurance Company - Daman Thiqa`) and Other Insurance, including
missing customer names. Insurance classification takes priority for insurance
invoice types. Matching ignores case and surrounding/repeated whitespace.
Customer names and individual invoices are never included in the client payload.

Sparse per-day channel sums are stored in the same atomic catalog snapshot;
list/header and 5,000-row register RPCs omit the daily series. Details reuse the
existing validated memory cache and invalidate when the snapshot changes. The
client fills missing in-window calendar days with zero, preserves negative
returns and fractions, and verifies its total against the snapshot KPI. Partial
source windows show their actual bounds rather than inventing earlier zero sales.
Products without catalog detail data show an unavailable message, never a false
zero-sales chart. Hover/tap and day navigation expose each day's five quantities;
the dedicated Excel export contains every date, all five channels and total Qty.

- Branches Stock: all active registered branches, excluding warehouses and STORE.
- STORE Stock: STORE warehouse balance. Duplicate item/branch balances use MAX,
  matching the existing stock workspace. Signed balances remain signed.
- APG Stock: **STORE + active branches with branches.branch_group in (APG, 71)**.
  The UI/export label stays APG Stock without a group suffix.
  It overlaps other columns. Total Stock = STORE + Branches; never add APG again.
  APG branch-only and group 71 balances are available in exports/details.
- Annual 2025/2026 Cash, Insurance and Online are signed net units from
  sales_history_2025 and sales_history; annual totals include all source branches.
- Recent demand: sales_last_45_days, active registered branches. All windows end
  at the latest uploaded sales date, not the client date. The latest 3 calendar
  days are separate from the preceding 42 calendar days. Partial global windows
  use the available calendar-day counts and are labelled in the details.
- Growth = (last-three-day daily average / preceding-42-day daily average − 1)
  × 100. A non-positive baseline has no numeric percentage. Recent quantity ≥3
  with a non-positive baseline is labelled New demand. Purple Sales increase
  requires ≥3 recent net units and ≥2× the preceding daily average.
  The Growth card uses green with an upward arrow for an increase, red with a
  downward arrow for a decrease, and its existing orange tint with a horizontal
  wavy arrow for zero at the displayed one-decimal precision. Unavailable growth
  keeps a neutral ellipsis; New demand uses the green increase style without
  inventing a percentage. Arrow changes and card colors animate briefly and
  respect the system's reduced-motion preference. Card sizes remain uniform.
- Cover days = total stock / average daily 45-day net units. Non-positive stock
  has zero cover; positive stock without positive net demand has no numeric
  coverage. Months use 30 days. Returns are not converted into positive demand.
- STORE / Total Stock % = STORE / total stock ×100; blank when total stock ≤0.
- Stock / Sales % = current stock / 45-day net sales ×100. The displayed value is
  uncapped; the animated gauge stops at 100%. Non-positive net sales have no
  percentage. Overview, MRN Overview and Near Expiry product details share it.
- Sales > stock compares 45-day net demand to current stock, with the shortfall
  shown in product details. It is a period comparison, not unfulfilled orders.

The main Overview table replaces the 42-day average, growth, distribution,
STORE MRN date, days in STORE and stocked-branch columns with Sales 45D. The
removed information remains available inside product details.

Reorder and Final Order columns show branch counts with total Qty beneath them.
They use each branch's `reorder_qty_num` and numeric final reorder quantity,
never the repeated product-wide daily totals. All active participating branches
remain included, including Online branches in APG and group 71. Online-only
branches absent from Daily Order do not make an otherwise complete run fail.
Fresh partial data shows its actual counts and Qty with a partial label, while
new-product distribution recommendations still require complete data.

MRN Overview and Near Expiry provide Export Excel using the table's effective
rows after search, toolbar filters, Excel column filters and sorting. Expiry
exports preserve the alert's MRN/expiry dates, ordered/received Qty, review state
and note. Missing live stock remains blank rather than becoming zero.

Monthly bars preserve negative quantities. The trailing 3-month mean requires
3 calendar months; missing months within the uploaded span are zero. The current
uploaded month may be partial. There is no revenue or margin source in these
tables, so monetary totals are not invented. Branch recent/stock data share the
snapshot; branch annual totals load live for one product using existing indexes.

## Validated memory reuse

Overview keeps one complete register in session memory. Reopening still makes the
existing metadata request and checks its inventory RLS, row count and transactional
`catalog_cache_version` before reusing rows. The normal 5,000-row loader and its
snapshot/duplicate checks run whenever the version changes. No partial or cancelled
register is saved. This does not introduce pagination or change filter calculations.

Product details retain at most 24 recently used products per Supabase client.
The first open uses the existing detail RPC, which normalizes active branch names
once and joins each annual sales aggregate once. Reopening sends the saved revision
to `get_stock_catalog_item_if_changed`; unchanged results avoid reaggregating and
transferring the detail body. Otherwise the server returns a current full result.
Every cache hit is validated remotely; failures never fall back to old quantities.
Concurrent requests for the same product share one request.

Revisions are committed with writes to the catalog snapshot, both annual sales
tables and branches. Triggers run once per statement, including bulk loads and
TRUNCATE, using separate revision rows per source rather than a shared refresh-job
lock. Sales corrections therefore invalidate details without requiring a snapshot
rebuild. Existing RLS and SELECT privileges still apply to conditional reads.
Rebuild requests, sign-out, account changes and token changes clear memory; late
requests cannot populate a new session. Nothing is persisted to browser storage.

Deploy `20261019125348_stock_catalog_fast_details_and_validated_memory_cache.sql`
with these client changes to enable revision-based reuse. Older servers remain
compatible: missing revision metadata keeps the original loading path, without an
extra request on the first product open. A removed conditional RPC falls back to
the original detail RPC, while permission errors are surfaced.

Verification includes `test/stock_catalog_memory_cache_test.dart` and the local
PostgreSQL regression suite `supabase/tests/stock_catalog_read_cache_test.cjs`.
The latter uses an isolated `@electric-sql/pglite` installation supplied through
`STOCK_CACHE_PGLITE_MODULE` and checks full payload equality, signed quantities,
rollback, bulk-write revisions, deletion, RLS and privilege revocation.

## Refresh, permissions and verification

MRN Overview and Near Expiry now use the same product dialog component as
Overview. Current analytics come directly from `get_stock_catalog_item`, while
`get_stock_management_product_details` preserves the MRN reference, receipt date,
MRN number and receipt-specific ordered/received quantities under `mrn_details`.
The existing expiry note, review/reopen actions, conflict version and durable
receipt evidence remain intact. When catalog statistics are unavailable, saved
MRN evidence remains visible and missing short-term comparisons display a dash.

MRN receipt facts use five compact `CatalogMetric` cards: Last MRN, Vendor,
Expiry date, Ordered Qty and Received Qty. Reference stays in the dialog header;
the redundant MRN-number and expiry-received cards and section prose are removed.
Expiry facts retain their compact coloured badges. The review editor places note input and
actions together on wide screens and wraps on small screens, keeping multiline
notes, review conflicts and receipt evidence. The review action uses white text
and icons. Detailed receipt guidance is available in the collapsed evidence area.

Both registers place Vendor immediately after Received Qty and Total stock
immediately after Branches stock. Store / Total stock is STORE divided by total
stock, expressed as a numeric percentage; zero/unavailable totals remain empty.
The same column order and percentage are used by Excel exports.

`20261020122615_stock_mrn_expiry_vendor_and_stock_share.sql` enriches MRN rows
with the vendor for their matching latest MRN/expiry. Near Expiry uses the latest
nonblank vendor from that expiry's durable receipt evidence. Full vendor evidence
is retained with receipts, while public labels/exports are uppercase and limited
to ten characters. Vendor corrections invalidate memory but preserve review
fingerprints, notes and reviewed status. Evidence survives removal of source MRNs.

`20261020124301_stock_mrn_register_set_based_receipts.sql` aggregates receipt
facts for the entire MRN batch instead of repeating a correlated receipt query
per product. The bulk RPC disables nested-loop planning only for its own duration
to prevent underestimated CTE sizes causing a quadratic final join. The setting
is restored on return. RLS, payloads, first-expiry selection, vendor fallback,
signed quantities, snapshot checks and the 5,000-row cap remain unchanged.

Deploy `20261020105108_stock_workspaces_validated_cache_and_shared_details.sql`
with this client update. MRN and expiry maintain a bounded, account-scoped memory
cache (28 entries, at most one complete register per workspace). Each reopen
validates a fresh server revision; errors never return cached quantities or notes.
Full loads retain the shared 5,000-row size and completeness/duplicate checks,
and validate revisions before and after loading. Review writes and rebuilds clear
memory before dispatch; cancelled and late requests cannot repopulate it.

Revisions track MRN snapshots/imports, durable expiry receipts, reviews, Item
Report and watcher state. Product detail revisions also include Overview's stock,
annual-sales and branch revisions. The Dubai calendar day participates in expiry
validation. `prepare_stock_expiry_workspace` validates and discovers receipts in
one round trip; unchanged reopens avoid rediscovery, and bulk pages never repeat
the scan. Raw identities and original stock/demand calculations are unchanged.

Regression suites: `test/stock_workspace_memory_test.dart`,
`test/stock_workspace_dialog_test.dart` and the isolated PostgreSQL suite
`supabase/tests/stock_workspace_cache_test.cjs` (uses `STOCK_CACHE_PGLITE_MODULE`).

stock_catalog_snapshot and stock_catalog_refresh_state have inventory-only RLS.
Public RPCs are SECURITY INVOKER; private cron writers have a fixed search path
and narrowly scoped grants. Rebuild data queues a background job; atomic refresh
keeps the prior complete snapshot readable and preserves it on error. A daily
refresh runs at 08:30 Asia/Dubai (04:30 UTC); users can rebuild after later imports. Reload
reads the current snapshot. Both stock and sales source dates are visible.

Verified on 13 Oct 2026: 14,929 products; zero differences for catalog count,
current stock, 45-day demand and both annual net-sales totals against the sources.
Rebuild took about 20 seconds in the initial verification. Inventory RPC access,
non-inventory exclusion and anonymous privileges are checked separately.

```powershell
flutter test --no-pub test/stock_catalog_test.dart test/stock_management_test.dart test/stock_expiry_test.dart test/stock_management_formatters_test.dart test/branch_identity_display_test.dart
flutter build web --release --no-pub
```

Visual previews can be regenerated with UPDATE_CATALOG_PREVIEW=1 and optionally
CATALOG_FONT_ROOT set to the Flutter SDK material_fonts directory. Tests exercise
complete-register loading, search, filters, on-demand details, metadata-driven branch names,
Excel formatting, moving averages, partial/negative demand, responsive layout,
refresh failure/retry and distinct sidebar routes.

Excel exports use .xlsx files with brand-coloured white-text headers, thin cell borders,
blue/white alternating rows, fixed column widths, frozen headers and Excel filters.
Dates use dd/mm/yyyy and quantities/percentages remain numeric. Browser exports
reuse the pinned local ExcelJS worker in bounded batches; no CDN is required.
