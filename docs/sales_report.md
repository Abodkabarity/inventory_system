# Sales Report

Inventory Dashboard → Analytics & Reports → Sales Report. Select one or more
months and press **Download CSV once** for one complete file. If preparation
is needed, the page requests it and starts the download automatically when ready.
Completed 2025 months read `public.sales_history_2025`; other completed months read `public.sales_history`. The calendar-current month reads `public.sales_last_45_days`, grouped by raw branch and item, with ten consistent sales columns. `created_at` is omitted from CSV exports.

View Dashboard → Analytics & Reports → Sales Report uses the same page and
global prepared files as Inventory, including 2025, other available years, the
current month and Sales 45 Days. Only active View accounts receive this report
access. The server reads the authoritative role; no client-selected scope or
additional Inventory write permissions are granted. Zonal scopes remain separate.

Category Dashboard uses the Inventory drawer styling with Items Tracker under
Operations and Sales Report under Analytics & Reports. Its existing tracker
permissions are retained; switching pages preserves filters and loaded state.
The menu collapses on desktop and opens as a drawer on narrower screens.
Active Category accounts share Inventory/View's global reports and download
authorization for all available years, the current month and Sales 45 Days.

Zonal Manager → Sales Report uses the same page and controls. The server derives
its scope from the signed-in active user's role, `get_my_effective_zones()` and
active authoritative branch assignments. Permanent and currently effective
delegated zones are supported. No zone or branch list is accepted from a client.
Month availability and the current-month last invoice day are scoped too.

Each zonal cache is keyed by the user and the exact authorized branch set.
Jobs persist that immutable branch snapshot and filter source rows on the server.
The private Storage policy recomputes authorization before signing a download:
a zone manager cannot sign a global file or another user's scoped file, even
with a known object path. Changed assignments or expired delegations revoke the
old scope's download eligibility immediately. Already issued links expire within
60 seconds. Source version v3 also invalidates the previous CSV format.

The access audit also covers direct reads of `sales_history` and
`sales_last_45_days`. Both enforce zonal branch scope through source RLS;
the monthly Availability views use `security_invoker` so they cannot bypass
that policy. Anonymous source reads and client source writes are denied.
User roles and zone assignments are writable only by server administration;
branch metadata writes remain available to Inventory through Branch Settings.
This prevents a zone manager from promoting their role, moving a branch into
their scope or invoking the privileged daily-sales truncate function.

`supabase/tests/sales_report_zone_access_audit.py` exercises every currently
active zonal identity against the live database inside a rollback transaction.
It verifies source rows, scoped month metadata, view access and all ready
Storage object paths, along with anonymous denial and Inventory compatibility.
The saved audit is `outputs/sales_report/all_zone_access_audit.json`.

Compatibility checks for the current Flutter source reads, Availability cache,
Stock Catalog/MRN product details and cache state are saved in
`outputs/sales_report/dependency_compatibility.json`. Non-zone business roles
retain their existing sales reads, and postgres/service_role ingestion and
refresh privileges remain intact. `created_at` remains in the source table.

Known performance limitation: direct authenticated queries to the legacy live
`availability_branch_master` view are slower with source RLS. The checked query
timed out at 35 seconds for Inventory/View, while the owner query bypassing RLS
completed in about five seconds. The current Flutter Availability page reads
`availability_branch_master_cache`; that application path passed. This live-view
performance issue remains unresolved. No experimental replacement was deployed.
External integrations using anonymous sales reads or ordinary client source
writes are affected by the new permissions and need server-side credentials.

Everything runs inside Supabase. `sales-report-server-cache` uses pg_cron and
pg_net every minute to invoke `sales-report-worker`. No Python, workstation,
Automation Dashboard, browser tab or external scheduler runs the export.
Requests also wake the worker immediately. Single months and each complete available year
are prewarmed; requested month combinations are cached and rebuilt too.

The existing `stock_catalog_cache_revisions` entries for `sales_2026` and
`branches` invalidate monthly source reports, including insert, update, delete and truncate. Current-month selections additionally depend on the private daily revision and Dubai calendar cutoff.
No source sales rows, source refresh jobs, Overview jobs or Online Overview code
are changed; daily exports add only the private revision trigger described below. Month metadata is rescanned only when the source version changes.
The source's own update cadence still determines which sales are available.

The current month is selectable when daily invoice rows exist in the user's
scope, up to the expected completed morning sale date. Its tile shows the
actual last invoice date. It can be combined with completed months in one CSV.
Historical current-month rows are excluded to prevent double counting, even
if `sales_history` already contains a provisional copy of that month.
Daily lines use the existing app classification: normalized Insurance, Direct
Insurance and Dirict Insurance invoice types take precedence, Delivery Invoice
and Return Delivery Invoice are online, and remaining lines are cash. Signed
quantities preserve returns. `total_sales` sums every signed quantity.
Daily source duplicates contribute to the grouped totals. Item labels use a
deterministic nonempty source label per branch/item. The daily source has no
unit retail price or sales value, so `retail` and `sales_value` are empty for
the current month. Completed-month prices remain unchanged.

Current-month selections require the same completed two-company 08:00 UAE
import receipt, expected global coverage and 60-second quiet period as daily
exports. Worker eligibility, completion, client download revalidation and
Storage enforce this gate. Historical-only selections remain downloadable
during daily updates. Only selections containing the current month depend on
the daily revision; completed-month cached files keep their existing versions.
On calendar rollover, the finished month switches to history. If that month
has not been published there yet, the worker and Storage block its old or
incomplete selection until the monthly source becomes available.

Daily preparation takes one MVCC snapshot. Monthly preparation checkpoints one
month per server invocation, with temporary CSV pieces of 5,000 rows (the final
piece of each month can be smaller). Every checkpoint is fenced by the same
source/branch revisions; a correction restarts the generation, and Storage
publication checks the revision again. This keeps the combined report consistent
without a single long-running annual query. Historical source duplicate rows are
preserved; current-month daily duplicates contribute to grouped quantities. Preparation sorts raw source fields before adding display metadata,
and aggregates one CSV piece at a time with function-scoped memory settings.
CSV uses UTF-8 BOM, CRLF and quoted/escaped cells. Branch names use
the server counterpart of `StoreBranchIdentityRegistry.displayName`, tested
against the Dart registry contract. Only authoritative branch group 71 is
prefixed, once; raw source identities and numeric values stay unchanged.

The Edge worker uploads exact 6 MiB byte ranges through resumable TUS uploads.
It checkpoints after each acknowledged chunk, reconciles the remote offset
after interruption and yields after four chunks. A global fenced lease limits
database load to one worker. Expired leases, invocation interruption and
transient failures are recovered by cron. After five failed attempts, the UI
offers explicit retry. Ready files are served directly by private Storage,
without moving CSV rows into Flutter or encoding them in the browser.

A file is marked ready only after Storage byte size and the current source
version are verified. Upload pieces are then removed. Old immutable files are
cleaned through the Storage API after a day. A scope-aware Storage policy
checks authorization and the version when issuing a 60-second download link. A link already
issued can remain valid until its expiry; a file is a snapshot as of the time
shown on the page. Source changes are detected by the server at the next minute
tick and download eligibility is checked against current revisions immediately.

Worker HTTP requests authenticate with a dedicated random token stored in
Supabase Vault. Gateway JWT verification is disabled for this function because
it verifies this token itself; missing/invalid tokens are rejected. Worker RPCs
are service-only. Client RPCs require an active inventory or zone-manager user. All job tables
and privileged functions are in the unexposed `sales_report_private` schema.

Validation:

```text
flutter test test/sales_report_page_test.dart
deno check supabase/functions/sales-report-worker/index.ts
python supabase/tests/sales_report_server_cache_test.py --migration <migration.sql>
```

The SQL integration test uses temporary sales/branch fixtures in a rollback-only
transaction. Configure `DATABASE_URL` or `SUPABASE_DB_*`; it never writes source
sales or branches. It covers duplicate rows, Arabic, commas, quotes, newlines,
nulls, negative sales, 5,000-row pieces, exact 6 MiB ranges and access controls.
It also verifies disjoint zonal exports, denial of global/cross-zone downloads,
scoped month/day metadata, expired-scope revocation and multi-zone assignments.


The same monthly page includes one **Download Sales 45 Days** button for
Inventory and Zonal Manager. There is no daily tab or daily/month selection.
It downloads one complete daily CSV from `sales_last_45_days`, with invoice
dates, limited to the latest 45 calendar days in the authorized scope. A click
prioritizes preparation and starts the download automatically when ready;
monthly selections and jobs remain independent. Columns are `branch_name`,
`inv_date`, `item_code`, `item_name`, `qty`, `sales_type`, `inv_type`,
`customer_name`; internal `id` and `created_at` are omitted.

Freshness follows the existing **08:00 Asia/Dubai** morning import. Before
08:00, the required completed sale date is two days ago; from 08:00, yesterday.
The server requires the existing successful atomic two-company publication
receipt in `sales_ingest_private.daily_runs`, matching global date coverage,
and 60 seconds without live-source writes. Date coverage alone cannot substitute
for completion. Exports exclude dates newer than that scheduled completed day.
A zone with no sales on the global latest day can still download its complete
scoped data after the global import completes.

A lightweight statement trigger bumps a new private daily revision counter
on insert/update/delete/truncate. It does not alter source rows, columns,
import schedules or monthly revisions. Cron prewarms the global daily file;
scoped files are prewarmed when the page is opened. Source/branch changes and
the 08:00 cutoff invalidate daily jobs and Storage authorization immediately.
During a pending morning update, the button shows a waiting state and the
server blocks older cached versions. Existing signed links expire within
60 seconds. The same server worker and private bucket are reused, with no
separate Python process.

The monthly integration cases also cover combined historical/current CSVs,
channel precedence, signed returns, unavailable prices, no history/daily double
counting, cross-zone denial, current-only invalidation, pending import receipts,
API-before-worker metadata refresh and calendar rollover. The live zonal audit
checks current-month availability against independent source queries.

Download feedback is shared by monthly and 45-day reports. A blocking branded
loading panel is painted before URL validation and browser navigation, with
button spinners and duplicate-request guards. After a successful handoff, a
persistent dismissible notice directs users to their browser's downloads.
The browser owns the actual file transfer; the app does not claim completion,
show invented byte progress or buffer large CSV files in browser memory.
Signing/opening failures clear the loading panel and restore retry controls.
Widget tests hold both signing and launcher futures to verify these states,
including recovery after failure and desktop/mobile layouts.

The monthly button uses a single user intent for preparation and download,
matching the 45-day button. Requested selections show a disabled spinning
button and an automatic-download notice while polling. Already-ready files
start immediately. A click during an in-flight metadata poll is retained and
sent after that poll. Changing the month selection cancels its pending download;
leaving/disposal also stops polling. Failures release the button for retry.
Widget tests verify one preparation request, one browser launch after readiness,
in-flight polling, selection cancellation and retry after failed preparation.

Status reads are now on demand: one initial metadata read when the page opens,
then checks on download, month selection or explicit refresh. Idle/ready reports
have no recurring UI timer or RPC requests. Each download click checks the
server even if the screen still shows an older ready file. The five-second
poll runs only for pending user downloads, and stops on handoff, failure,
selection cancellation or disposal. Status requests never disable or recolor
a usable button by themselves. Tests verify no extra reads during 30 minutes
of idle time, freshness checks on click, update preparation and automatic
handoff, and timer shutdown after completion. The server worker and source
import schedule are unchanged.

2025 is available through the same year selector in both Inventory and Zonal
Manager. Switching years preserves selections; the Latest month, Last 3 months
and All months presets apply to the displayed year. Mixed-year selections
retain chronological sorting and download once as one CSV, including the
current daily month when selected.

The archive exclusively owns `/2025` months. Matching 2025 copies in the newer
history table and misplaced non-2025 archive rows are excluded, preventing
double counting. Historical raw rows, duplicate rows, prices and sales values
remain intact. Archive versions use the existing `sales_2025` and `branches`
revision entries. Archive-only caches do not depend on newer-year/daily sales;
selections without 2025 retain their pre-existing versions and ready files.
Metadata includes both sources. Per-year ranges are prewarmed; mixed-year
ranges are prepared and cached on request.

No source rows, source RLS policies, importer schedules or other application
caches are modified. The existing 2025 source RLS remains in force (zonal raw
reads are denied); the authenticated report gateway and private worker apply
server-derived branch filters before producing scoped archive CSVs. Tests cover
2025 + 2026 + current-month exports, year-source ownership, independent archive
invalidation, all active zonal identities, and exact real-file cell/duplicate
comparison against both source tables.

Large annual/month combinations resume from `jobs.prepared_months`. One UTF-8
header is written at the start; each month appends contiguous byte ranges.
The worker releases its lease between months and requeues automatically,
allowing other requested reports to progress too. Upload begins only after all
months are prepared. RPC timeout (60 seconds), function memory limit (8 MiB),
source tables and source permissions remain unchanged. Validation covers
lease reacquisition, correction-safe restart, one header, exact cross-month
6 MiB upload ranges and the complete production 2025 year.

The exported monthly `month` cell is an Excel constant text expression such as
`="06/2025"`, CSV-escaped normally. This prevents Excel's automatic conversion
of plain `06/2025` into a displayed `Jun-25`. The formatter accepts only strict
`MM/YYYY` months; arbitrary expressions are rejected. It is evaluated once per
month checkpoint. Source values, API/filter months and numeric columns remain
raw and unchanged, and 45-day invoice dates are unaffected. The monthly format
version invalidates older prepared CSVs. Other CSV readers see the constant
text expression and can unwrap its validated string when consuming the file.
An actual Excel import of a server-generated fixture was verified to display
`06/2025` and `01/2027`. Live Inventory/zonal files are compared against all
source cells after decoding only the month display expression.
