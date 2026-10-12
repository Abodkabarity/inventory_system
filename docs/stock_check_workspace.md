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
`buildKpiAnalysisWorkbook` remains available for synchronous workbook inspection;
the production KPI download uses `buildKpiAnalysisBytes` instead.

The analysis panel paints progress before starting, shows real worksheet row
counts and an indeterminate finishing phase, and keeps branch search, project
selection and product details available. Cancel or leaving the page terminates
the worker. Errors reset the export button for retry. The report captures the
selected projects at the moment Export is pressed.

The browser suite validates actual worker XLSX contents/styles, cancellation,
error recovery, usable controls during export, and event-loop heartbeats during
a 15,000-product, four-quarter export. The Windows test helper temporarily serves
the two worker assets as well as CanvasKit and cleans them afterward.
