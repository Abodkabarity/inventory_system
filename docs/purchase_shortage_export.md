# Purchase Shortage daily archive

`automation/purchase_shortage_export.py` uses the same live RPCs as the Inventory
Dashboard. It does not reimplement the shortage calculation:

- `get_purchase_shortage(p_run_date)` supplies all nine `TotalShortage` columns.
- `get_purchase_shortage_branch_stock_rows(p_run_date, p_limit, p_offset)` supplies
  `Branch`, `Item Code`, `Item Name`, `Branch Stock` for **all daily-order rows**.

The run date is captured once at startup in `Asia/Dubai`. Both sheets, the local
filename, the month directory and the Storage key use that date. This scheduled
archive uses calendar today, including after 9 PM, rather than the dashboard's
next-day business-date cutoff.

## Sequence

The existing scheduler runs Missing Items at 08:00 and then Mismatch. Only a
successful Mismatch exit launches Purchase Shortage in the same background
supervisor. Its lock covers the full chain; other scheduled appointments continue.
The shortage process also holds an OS file lock to prevent manual overlap.

1. Send STARTED using the existing `email_notifier`.
2. Read the existing RPC results in pages and write a streaming two-sheet XLSX.
3. Check branch row counts and XLSX integrity, then replace the local daily file.
4. Upload the saved file into the private `shotrage purchase` bucket.
5. Download the stored bytes and compare SHA-256 with the local file.
6. Send COMPLETED with row counts, date, paths and elapsed time. Errors send FAILED;
   the scheduler sends STOPPED if its watchdog terminates the process.

Local root:
`C:\Users\abdulrahim\OneDrive - Al Ain Pharmacy\INVENTORY INDEX BACKUP\00Branches Orders\Purchase Shortage`

Relative local/Storage path:
`MM-YYYY/Items Shortage Include Assortment DD-MM-YYYY.xlsx`

The same-day rerun replaces that day's file only after validation. Upload failure
retains the local report. A locked Excel target is retried for 60 seconds and then
reported as a failure; existing reports remain untouched. Missing daily-order
data or more than 1,048,575 branch data rows fails explicitly rather than publishing
a truncated sheet. A valid zero-shortage day has a header-only `TotalShortage`.

## App download

Calculate Shortage continues to calculate/display the live RPC result. Export
works without Calculate and requests only today's Dubai-dated stored workbook,
using a 60-second signed download URL. It never chooses the latest historical
file, calculates a replacement, or downloads a separate CSV. Displayed live
results can differ from the archived snapshot if source data changes later.

The Storage SELECT policy permits only active inventory users and only today's
exact object path. Upload/upsert is backend-only. Backend credentials are reused
from the existing Mismatch setup, with `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` environment overrides; no credentials are added to
Flutter.

## Operation and checks

Run with the scheduler's existing Python environment (`requests`, `openpyxl`,
`schedule`, and Dubai timezone data are already used by existing jobs):

```powershell
python automation/purchase_shortage_export.py
python -m unittest discover -s automation -p test_purchase_shortage_export.py
flutter test test/purchase_shortage_report_test.dart test/purchase_shortage_download_test.dart
```

`--output-root` overrides the archive root. `--no-email` is only for controlled
verification; it does not disable uploads. Restart an already-running scheduler
to load code changes, and publish a new Flutter web build to update the live button.
The `automation` directory is locally ignored by Git in this repository; preserve
these local files separately when moving the scheduler to another machine.
