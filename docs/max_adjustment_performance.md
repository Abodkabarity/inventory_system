# Max Adjustment loading/export performance

Publication requested 27 November 2026; final validation continued 28 November.
This release follows the Tibah-only release and includes the previously local
Max performance work. Online Overview, Preparation monitor, mobile and Recall
follow-ups remain outside this release.

## Behavior

- Full-table loading requests the shared 4,000-row default, detects smaller API
  caps, then uses at most two parallel batches. Results retain their server order.
- The table stays complete: no partial batch is shown as a complete result.
  Duplicate IDs, changed totals and incomplete replies fail visibly. Searches
  retain request-token cancellation and normal retry behavior.
- The page shows actual loaded/total rows and percentage. Recent complete results
  can be reused for 30 seconds when reopening the same query. Search, explicit
  refresh, imports and Max Realtime events keep their invalidation paths.
- Current/history exports use indexed ID cursors, a pinned upper ID, exact count,
  duplicate/completeness checks and the shared batch default. Slow reads reduce
  their batch at the same cursor, bounded to 500 rows; writes are not retried.
- A lazy typed report feeds the existing pinned browser Excel worker so writing
  and compression do not block the page. Codes remain text, Qty numeric, dates
  typed where previously typed, history fields intact and group 71 names formatted
  before the worker receives values. Export progress shows reads, writing,
  compression and download. No incomplete file is downloaded on failure.
- Buttons now read **Upload Tibah UPP** and **Upload Tibah Regular**. This is
  presentation only; raw branch matching and the two independent types are intact.

## Deleted Tibah Max

Installed migration `20261127125834_tibah_cancel_deleted_max.sql` cancels the
current Tibah Store generation when a referenced Max row is deleted, including
normal direct Supabase deletes. A whole-table truncate also withdraws pending
Tibah generations. Source Max policies and calculation jobs are unchanged.
History is retained. Staging cleanup does not cancel the new file, and removing
one type never cancels the other. A one-time reconciliation withdrew the user's
already-deleted seven-row UPP generation. Store sees the updated state on its
existing 15-second header refresh or manual refresh.

## Verification

- 35 Dart/widget tests: capped and parallel reads, cancellation, incomplete and
  duplicate batches, progress, current/history export cursors, bounded timeout
  recovery, typed report rows, expiry and Tibah isolation.
- Three actual browser tests cover 9,001 rows in three transport requests, recent
  reuse, duplicate opens, empty snapshots, worker export progress and retry.
- Node worker round-trip verifies text codes, Qty, dates, history and group 71;
  a stress file with 107,689 rows / 16 columns was built in 6 seconds locally
  (5.7 MB). This is a local measurement, not an end-user latency promise.
- Authenticated database reads returned 4,000 current and 4,000 history rows under
  the existing 8-second statement timeout, with current/history counts 19,912 and
  88,001 at verification. No database source rows were changed by those reads.
- Transactional SQL tests verify deleted Max withdraws only its own request,
  preserves historical rows and staging, and handles truncate dispatch using an
  empty temporary table rather than truncating real Max. Fixtures roll back.

Browser tests need pinned worker/CanvasKit assets. Start
`python test/serve_max_export_test_assets.py` in one terminal, then run
`flutter test --no-pub --platform chrome test/max_adjustment_performance_web_test.dart`.
The test asset origin can be overridden with the `MAX_EXPORT_TEST_ASSETS` Dart
constant. On the affected Windows Flutter SDK, the test server's CanvasKit route
returns 404 because of path separators. `node test/bridge_flutter_test_engine.mjs
<isolated-test-debugging-port>` supplies only those engine files from the local
pinned server and reloads the uninitialized test iframe. This does not modify
Flutter, security settings, application code or a user browser profile.

Generated workbooks and fixtures under `validation/` are excluded from release.
Shared stock worker/assets, workflows and protected Online files remain unchanged.
