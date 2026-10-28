# Stock Check: restored Git interface

The Inventory and Store management page was restored directly from Git HEAD
`6e9df1c` (the Stock Check file's last change is `042fa7f`). Its original UI is
preserved: Stock Checks / Accuracy Analysis tabs, inline creation form,
Inventory / Store campaign toggle, date filter, campaign deadline and delete
buttons, and the original results grid and project comparison.

The replacement layout parts were archived in the ignored
`tmp/stock-check-restore/` directory, alongside the previous page and test files.
The application sidebar and the Branch Stock Check page are unchanged by this
restoration.

The only production changes to the Git page are an optional injected client for
verification and automatic sender capture before sending. The existing
`StockCheckWorkspaceRemoteDs.currentSender()` reads the signed-in
`app_users.role`, `user_name` and `is_active`. Non-branch senders need an active
profile and a name. The captured ID/name are added to new management campaigns.
For the `branch` role, no `user_name` is required and no sender fields are added.
No team or owner inputs were introduced.

The applied database migrations are retained. In particular,
`20261008164601_stock_check_branch_sender_exemption.sql` allows branch UPSERT
submissions without a personal `user_name`. It preserves campaign attribution
because branch response updates exclude sender fields. Restoring the management
UI does not change this trigger or the branch submission payload.

Validation uses the existing model/data tests and Chrome widget tests of the
restored UI, Inventory/Store sender capture, branch name exemption and non-branch
missing-name validation. The earlier rollback SQL regression test remains in
`test/sql/stock_check_branch_sender_exemption_test.sql`.

On Windows, run `./tool/test_stock_check_workspace.ps1` for both Dart and Chrome
tests. The script temporarily serves the installed SDK renderer files for the
Flutter Windows test server and removes them afterward.

## Responsive KPI export

Selecting KPI projects keeps the analysis panel mounted during loading. A
compact status card shows completed project counts; the first load uses branch
placeholders, while later loads retain the previous complete report. Updated
results are committed together after every selected project has loaded. Search
and scroll state survive the update. Export is disabled until loading succeeds.
Failures appear inside the panel with Retry, and selection changes invalidate
older requests so late responses cannot replace the current analysis.

`exportKpiAnalysis` prepares bounded batches of 250 product rows and sends them
to a dedicated browser Web Worker. The worker builds the worksheets and compresses
the XLSX with the bundled, pinned ExcelJS 4.4.0 library. It returns a transferable
buffer; the UI only initiates the local download. No runtime CDN is required.
The pinned ExcelJS library is cached, while the small export worker is loaded
without the Flutter string cache on every export. This prevents stale worker
code after hot reload. Quarter colors are also inferred from column labels for
older open clients that do not yet supply a color palette. JavaScript asset
changes still require rebuilding the served asset bundle or a Flutter restart.
The KPI worker has a version marker checked before execution, so an outdated
served asset gives an explicit restart message instead of a JavaScript palette
index error. Palette lengths follow the actual quarter columns and missing or
malformed entries use the inferred colors; trailing comparison, accuracy, and
Adjustment columns cannot be mistaken for another quarter. When repairing a
running local build, the worker in both `build/flutter_assets/assets/workers/`
and `build/web/assets/assets/workers/` must match the source asset.
`buildKpiAnalysisWorkbook` remains available for synchronous workbook inspection;
the production KPI download uses `buildKpiAnalysisBytes` instead.

KPI Summary includes separate Awaiting / Review and Excluded from KPI columns.
Shared Items appears only
when at least two projects are selected, with the selected quarters in its
header (for example, `Shared Items (Q1 - Q2 - Q3)`). Summary headers, row values,
and column widths are generated together for both workbook export paths.

KPI calculation uses the latest selected project in chronological quarter/year
order. A product absent from that project is excluded from the numerator and
denominator, but remains in the detail rows for audit. Submitted products with
both latest System and Actual within ±0.01 of zero also stay out of the final
percentage and have a blank individual Accuracy cell in the UI and Excel,
regardless of earlier quantities, differences, or missing quarters.
Latest-only zero stock uses the short Result `Zero stock in Q2` (for Q2).
Other completed products earn
100% when their latest Difference is zero, or their Difference is unchanged
across all included projects. A single-project product needs zero Difference.
All other scored products receive 0%. If no products are scored, accuracy is
unknown rather than a fabricated percentage.

Difference remains Actual minus System. Absolute differences and changes up to
0.01 inclusive normalize to zero with a small floating-point allowance. Larger
fractions and all source quantities remain intact. The comparison column keeps
the normalized full range (largest minus smallest included Difference), so an
intermediate error remains visible even when the latest quarter is corrected.
Result uses one short English category for the most recent meaningful transition,
including corrections, new errors, unchanged variances, increases, decreases,
and sign reversals. It contains no quantities, percentages, or repeated history;
all-zero products use `Zero stock in both quarters` for two selected projects. Quarter labels
omit the year unless selected projects span years. Product search also accepts
Result text, and both Excel paths enable column autofilters. The UI
and both Excel paths share the report model and normalized display values.
Pending counts and duplicates retain review protection; incomplete project
loads cannot masquerade as products missing from the latest quarter.

Branch labels in Stock Check and KPI use
`StoreBranchIdentityRegistry.displayName`, including summary/detail exports,
branch cards, grids, selectors, and dialogs. Group 71 displays `71 ` before the
name. Raw names remain the keys for queries, branch/product matching and KPI
calculations. KPI cards and product dialogs react to registry metadata updates,
and branch search accepts the displayed prefix. This project-wide requirement
is also recorded in the repository's `AGENTS.md` for future changes.

The analysis panel paints progress before starting, shows real worksheet row
counts and an indeterminate finishing phase, and keeps branch search, project
selection and product details available. Cancel or leaving the page terminates
the worker. Errors reset the export button for retry. The report captures the
selected projects at the moment Export is pressed.

The browser suite validates actual worker XLSX contents/styles, cancellation,
error recovery, usable controls during export, and event-loop heartbeats during
a 15,000-product, four-quarter export. The Windows test helper temporarily serves
the two worker assets as well as CanvasKit and cleans them afterward.

## Adjustment quantities in KPI comparison

The final `Adjustment Qty` column in product details and both Excel export paths
shows signed net `qty` from `stk_statement_history_2026`, restricted to
`trans_type = INVAdjustment` (case/whitespace insensitive) for the same raw
branch/item identity. This is informational and never changes the KPI score.
Legitimate source lines are summed individually, including multiple lines with
the same document number. Fractions retain their source values; the KPI 0.01
difference tolerance is not applied to adjustments.

The inclusive date range starts on the actual Q1 campaign's `sent_at` date in
Dubai, not the calendar quarter boundary, and ends on Dubai today at load time.
If Q1 is not selected, its campaign for the same KPI year is looked up on the
server. Missing Q1 dates and unsupported source years produce a retryable
unavailable state rather than a guessed date. The current archive is 2026 only.
The loaded range appears beside the dashboard and in the Excel column heading.

No matching adjustment movements display a blank cell in the UI and Excel.
Existing records display signed net quantity and count, for example
`6 (1 adjustment)`, `-3.5 (2 adjustments)`, or `0 (2 adjustments)` when recorded
movements cancel out. Counts refer to matching source records, not distinct
document numbers. The same format is used regardless of archive coverage;
no coverage qualifier, warning, or special color is added to these values.
Displayed date ranges and Excel headings omit the timezone name. Internal date
calculations retain the business timezone. Coverage checks combine complete monthly load
checkpoints and independently verified daily publication receipts. A monthly
checkpoint invalidated by a daily replacement is not silently considered whole.

The Inventory-only `stock_check_kpi_adjustments` invoker RPC delegates to a
guarded private implementation. The raw archive permissions remain unchanged.
A partial index limits reads to adjustments; keyset pages use 5,000 rows on both
client and server. Source snapshots, row totals, cursor progress, and duplicate
checks reject mixed or incomplete loads. Stale requests cannot replace a newer
selection. Once project counts are ready, Export remains available while
adjustments load: clicking immediately paints progress and waits for that same
load before writing the workbook. Waiting can be cancelled; a later attempt
reuses an ongoing load, and clicking after a history failure retries it. A changed
project selection cannot mix with the queued export. Copies of the same project
rows during parent rebuilds do not restart the history query. Open product
dialogs receive loaded quantities without closing. Refresh adjustments obtains
a new date/source snapshot. Excel uses that same loaded snapshot.

Validation: `test/stock_check_kpi_adjustment_test.dart` covers pagination,
source consistency, signed fractions, cancellation to zero, and incomplete
coverage. The Chrome suite checks asynchronous dialogs and both actual XLSX
paths. `test/sql/stock_check_kpi_adjustments_test.sql` is a read-only linked-project
regression for all product pages, raw signed reconciliation, Q1 date lookup,
access denial, snapshot rejection, and server limit validation.
