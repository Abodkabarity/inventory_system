# Item Report stock Overview

Stock Management has three independent entries: Overview, MRN Overview, Near Expiry.
Overview includes every nonempty unique Item Report code, even without an MRN.
All three Stock Management registers and product details show Created date from
`item_report.added_date_time` as `dd/MM/yyyy`, without a time. Timestamp values
are converted to the Asia/Dubai calendar day; date-only values stay unchanged.
Headers filter/sort actual dates. Missing Item Report identities/dates show —;
they are never replaced with MRN dates or import `created_at`. Catalog CSV uses
the same date-only formatting (empty cell for missing dates). The catalog/MRN
snapshot writers preserve this field on rebuild; expiry readers enrich both
current and saved product facts from Item Report without changing receipt/review
fingerprints or historical quantities.
The existing MRN and expiry tables, refreshes and review notes are unchanged.

The complete product register loads in background batches of up to 4,000 products
and rejects changes of snapshot version/count or duplicate codes between batches.
There is one continuous table with no visible pagination. Search, Status, Item Status,
category, supplier and sorting operate locally on the complete loaded catalog. Rows are
virtualized; monthly charts and branch details load only when opening a product.
CSV exports use the same filtered snapshot as the table and include all matching
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
first on opening the page and after clearing filters. CSV includes Item status
and preserves the selected filters and order.
Every table header also offers the Daily Order grid's Excel-style menu: search
and select text values, numeric comparisons/ranges, and ascending/descending
sorting. Item Status is a separate column. Cells carry their actual text/numeric
values rather than item codes; cover conditions use days and ratio/growth use
percentages. Undefined numeric values remain blank. Column filters combine with
toolbar filters and persist through search/sort changes, including zero matches.
Summary cards reflect column-filtered rows, and CSV uses the grid's effective
rows in displayed order. Clear filters resets both column filters and sorting.
Opening a filtered/sorted row resolves its product identity from the effective
row rather than its original position. Filtering controls use AppColors.primaryColor.
Branch labels, search and exported cells use StoreBranchIdentityRegistry, and
labels repaint when authoritative group metadata arrives.

## New product distribution

Overview has a Needs distribution card, Status option, priority sort, column
filters and CSV fields. Default rules are age 0–30 Dubai calendar days, STORE
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
and CSV. Days in STORE starts at the first qualifying receipt and is not reset
by later deliveries. Receipt facts are informational only: missing, unapproved,
or out-of-range MRNs do not suppress the distribution alert or change its status.
The partial-distribution limit remains.

Covered means the union of eligible branches with positive ledger stock OR a
positive Final Reorder; overlapping branches count once. Reorder demand remains
separate. The latest Daily Order run supplies `total_reorder_today` and
`total_final_reorder_today`, collapsed once per normalized item/branch. This uses
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
branches. Branch labels/search/CSV use StoreBranchIdentityRegistry. Final orders
are planned allocation, not proof of delivery. Counts and order details share
the stock snapshot: Rebuild data after order edits/imports to recalculate them.
List RPCs omit the branch-order map to keep the virtualized register lightweight.
The existing daily/manual catalog rebuild updates all facts atomically.

## Stock and demand calculations

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
- Branches / STORE % = branches / STORE ×100; null when STORE ≤0. Can exceed 100%.
- Sales > stock compares 45-day net demand to current stock, with the shortfall
  shown in product details. It is a period comparison, not unfulfilled orders.

Monthly bars preserve negative quantities. The trailing 3-month mean requires
3 calendar months; missing months within the uploaded span are zero. The current
uploaded month may be partial. There is no revenue or margin source in these
tables, so monetary totals are not invented. Branch recent/stock data share the
snapshot; branch annual totals load live for one product using existing indexes.

## Refresh, permissions and verification

stock_catalog_snapshot and stock_catalog_refresh_state have inventory-only RLS.
Public RPCs are SECURITY INVOKER; private cron writers have a fixed search path
and narrowly scoped grants. Rebuild data queues a background job; atomic refresh
keeps the prior complete snapshot readable and preserves it on error. A daily
refresh runs at 07:15 Asia/Dubai; users can rebuild after later imports. Reload
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
CSV formatting, moving averages, partial/negative demand, responsive layout,
refresh failure/retry and distinct sidebar routes.
