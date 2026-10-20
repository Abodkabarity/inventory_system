# Zone Stock Check consistency

Zone dashboard alerts and Stock Check project details use
`ZoneStockCheckRemoteDs`. Inventory Dashboard and branch screens are unchanged.

The old zone loaders paged by `expires_at` or `sent_at` without a unique
tie-breaker. A campaign can have thousands of rows with the same timestamp;
Postgres can return different orders for successive OFFSET queries, repeating
some rows and omitting others. Counts, branch chips, details and downloads could
therefore disagree with the authoritative tasks.

The zone reader now requests 5,000 rows, advances by ascending unique task ID,
continues through smaller server API caps, and queries each raw branch once.
It checks row identities, branch scope, total count and the latest `updated_at`
before publishing a chunk. Concurrent changes retry once; persistent incomplete
or inconsistent reads surface an error instead of replacing validated data.
This count/latest-update check is a consistency guard, not a database transaction
snapshot across all branch chunks.

Both inventory and store tasks remain included. Pending alerts honor the selected
branch; opening an alert refreshes details. Refreshes from an obsolete zone scope
are ignored, and realtime detail refreshes arriving during a load are queued.
Stock Variances counts submitted tasks only. Branch labels/search react to the
shared group registry, preserving the required `71 ` display prefix and raw
database/filter identities.

Verification:

- `flutter test --no-pub test/zone_stock_check_remote_ds_test.dart`
- `flutter test --no-pub --platform chrome test/zone_stock_check_widget_test.dart`
  (Windows needs the same temporary CanvasKit files used by
  `tool/test_stock_check_workspace.ps1`.)
- Optional read-only live comparison, using the local `.env` URL/anon key:
  `flutter test --no-pub --dart-define=RUN_STOCK_CHECK_LIVE_TEST=true test/zone_stock_check_live_test.dart`

On Windows, `./tool/test_zone_stock_check.ps1` runs data and browser tests and
temporarily serves the SDK's CanvasKit/font files. Add `-Live` to include the
read-only live comparison.

The live test is skipped by default. It compares the zone detail and pending IDs
against exact server counts without changing database records.
