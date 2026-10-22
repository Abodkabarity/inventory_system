# Inventory Dashboard: live Mismatch Report

The existing `MismatchPage` now opens `MismatchReviewWorkspace`. Production
analysis runs entirely in PostgreSQL; the application is Flutter/Dart. The
earlier offline Python report is not required to use this screen.

## Workflow

- Active counts load from a consistent snapshot in 5,000-row keyset pages.
  The client rejects duplicate IDs, count mismatches, source-version changes,
  stale snapshot tokens and incomplete pages. No silent REST 1,000-row cap.
- The server owns `inventory_mismatch_reviews`, keyed to the current mismatch
  ID with cascading deletion. An AFTER INSERT/UPDATE count trigger computes
  the review in the same transaction as the count and its audit log.
- The existing update logger runs BEFORE UPDATE, so reviewing its log INSERT
  would read old count values. `zz_inventory_review_after_count` runs after the
  new count values and after the existing AFTER INSERT logger. SQL integration
  tests cover both paths and delete cleanup, rolling back all test records.
- Same-transaction log timestamps can tie. At the latest timestamp, matching
  current count values are preferred over a random UUID ordering. No ordering
  of stock movements within a day is inferred from transaction numbers.
- Review calculation errors are shown as unavailable, not clear. The trigger
  records this state rather than rejecting an otherwise valid branch count.
- The screen watches count/review Postgres Changes and fetches only changed IDs
  after debouncing. Deletes remove those IDs locally. A metadata-only poll every
  45 seconds detects a missed event or new source version and reconciles the full
  snapshot; idle polling never downloads the full list. The full snapshot token
  is not advanced by partial responses, which could otherwise hide missed events.
  Reconnection also reconciles the full snapshot. The connection badge
  distinguishes a subscribed channel from fallback polling. Removing the page
  releases its channel and timers. Old data stays visible on a sync error.
- Archive completion changes the evidence version. In-progress upload batches
  do not repeatedly invalidate every review. Cached results for an old version
  show Pending, not a prior risk verdict, until refreshed in bounded 100-ID
  write requests. The version is captured before computing to avoid stamping
  old evidence as current if a source commits during the calculation.
- Detail requests compute current evidence without writing the cache. Opening
  a detail panel cannot create a realtime reload/analysis feedback loop.

## Review rules

The previous audit's conservative reconstruction rules are implemented in
`inventory_audit.compute_review`: January 1 system reference, signed IN/OUT,
single inclusion of adjustments, source/company validation, exact numeric
calculations, daily zero checkpoints, recent incoming movements, old versus
additional shortage, same-day ordering uncertainty and immutable document
numbers. Missing baseline is unknown, never zero. `INVAdjustment` is explicit;
`ReturnPOS` asks for the customer-return evidence rather than a transfer slip.

The classification concerns the latest add/update of the active count. The
original `update_date` can be unchanged after an edit. An unchanged discrepancy
is not automatically a new loss. The current archive covers through October
21, 2026: a new October 22 count is still analyzed immediately, but cannot get
a reliable movement-based verdict until its event date is covered. The page
shows this limitation and the exact coverage date. A system zero or a priority
flag never proves physical zero or branch responsibility.

## Interface

Summary cards filter active counts, follow-ups, adjustments and evidence gaps.
Search uses product name/code and raw/displayed branch names. Branch/date/risk
filters and priority/newest sorting work locally across the complete snapshot.
The queue uses a virtualized list with a separate, prominent branch column.
Priority follow-ups have a pale red row and red edge; recent receipts use amber,
and adjustment reviews use purple. Selecting a row always opens a centered
dialog up to 1,320 pixels wide, with the branch name above the product.
Visible wording uses "mismatch report" for report entries/dates and "branch
stock" for the physical quantity. The baseline is labeled "1-1-2026 stock".
The receipt card shows only its date. The report-event card shows "Added to
mismatch report" or "Updated in mismatch report" and "After N days" (or the
equivalent months/days), measured from the latest receipt to that report event.
The Case summary opens with a simple English narrative: quantity received, receipt
month/date, the exact elapsed calendar months/days until the reported difference,
carryover system stock, sales, outgoing transfers, other exits, stock corrections,
expected stock and branch count. POS/POSDVN are sales; StockTransferFrom is an
outgoing transfer. Unknown types remain other movements. Corrections are never
included in sales or transfers. Sales/transfer totals in this narrative cover
days strictly after the receipt day and before the count day. Other receipt-day
movements and count-day movements are separately explained with order unknown.
The narrative separates an older shortage from its increase in this event.
It does not claim sales came from a particular receipt lot. Missing reference,
source gaps or other server issues prevent a definitive comparison verdict.

The date cards present four chronological checkpoints: the last system
zero before incoming, latest incoming, movements on later days, and the branch
count. IN/OUT totals exclude corrections, which have their own count. Other
movements on the incoming day are explicitly unordered. An assertion of no
later movement requires complete coverage and no same-day conflicting rows.

A prominent adjustment summary and a dedicated Stock corrections tab show **every**
available INVAdjustment from January 1 through the count date, including those
before the latest receipt. Each entry retains its signed quantity, date and
document number and says whether it precedes, follows or shares the receipt
date. Adjustment entries are not deduplicated by document number: a document
can legitimately have multiple source rows. No absence before 2026 is inferred.
The Movements and Count history tabs retain the original evidence, including
initial count additions. All details continue updating while the dialog is open,
including branch labels when authoritative metadata arrives later.

Opening/closing the dialog does not set page selection state or rescan the
queue. Immutable review objects memoize parsed analysis, dates and ranking;
the screen projection caches filtering, sorting, branch choices and KPI counts
until rows, filters, branch metadata or the Dubai calendar date change. Detail
evidence is processed once per response and only the selected tab is built.
The first dialog frame shows count/receipt context before starting the detail
request. A bounded 12-entry, 45-second screen-local LRU cache reuses details and
deduplicates concurrent requests. Count/review notifications invalidate that
ID immediately, including outstanding responses; source version and row-value
changes also invalidate entries and refresh an open dialog. Cache lifetime is
limited to this controller and no detail is persisted in browser storage.

Visible-review Excel export includes analysis and evidence dates. Both existing
original-record and history Excel options remain accessible and are labeled
as unfiltered original exports. Every branch display/search/export uses the
actual `StoreBranchIdentityRegistry` and authoritative `branches.branch_group`.
Metadata updates repaint labels without changing raw identities or KPIs.

## Access and deployment

Only active `app_users.role = inventory` accounts can call the review RPCs.
Public RPCs are SECURITY INVOKER wrappers. The privileged implementations live
in the unexposed `inventory_audit` schema, check `auth.uid()` and the active role
on every call, and have a fixed search path. Raw ledger/statement archive grants
are unchanged. Review-cache RLS independently restricts SELECT to Inventory.
No service key is included in the client. Server-only trigger/computation
functions are not executable by authenticated callers.

Migration: `20261022071416_inventory_mismatch_live_review.sql` (depends on the
previous movement evidence function and its branch/item/date index). The cache
is initially backfilled server-side for existing active count IDs; all new
counts/edits are automatic. The screen falls back to refreshing missing/stale
cache rows if backfill was not run.

Verification:

```powershell
flutter test --no-pub test/mismatch_review_workspace_test.dart test/mismatch_stock_journey_test.dart
flutter analyze --no-pub lib/domain/entities/mismatch_review.dart lib/data/repositories/mismatch_review_repository.dart lib/presentation/inventory_dashboard/page/mismatch_page.dart lib/presentation/inventory_dashboard/widgets/mismatch_review_workspace.dart
flutter build web --no-pub
```

`supabase/tests/inventory_mismatch_live_review_test.sql` tests trigger behavior,
page limits/completeness, stale snapshots, active Inventory access, branch-role
denial and missing-identity denial. All synthetic count/log/cache writes roll
back. Widget tests cover live updates, offline retention, stale-source behavior,
late group-71 metadata, document detail and 640/1000/1700-pixel layouts. A visual
preview is saved under `outputs/mismatch-live-workspace-preview.png`.
Additional regressions cover the received-three/sold-one/transferred-one case,
exact two-month elapsed time, old stock, unknown outgoing types, same-day
uncertainty, and source-version refresh of an open dialog without row changes.
A synthetic 11,000-row widget test asserts opening/closing does not re-run
search over the list and reopening makes only one detail request. Cache tests
cover request deduplication, in-flight invalidation, source changes and eviction.
