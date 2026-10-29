# Daily raw Stock Statement archive refresh

The entrypoint in `automation/main.py` runs the optional
`statement_history_daily_sync.py` worker before the existing reports. It does not
change the scheduler, Branch Order, Submit, Max Decrease, or the aggregated sales
and TODAY uploaders. Imported `main.run()` calls are unchanged; direct/scheduled
execution of `main.py` performs the preflight.

## Update rule

The target date is frozen at process launch in **Asia/Dubai**. The server reads
the latest archive date separately for APG and 71 Pharmacy L.L.C., including
verified empty-day receipts. For each company the starting date is the earlier of
the next missing date and yesterday. The worker uses the earliest start across
both companies, downloads both complete reports, and replaces both companies for
each day through today. An empty archive starts at 2026-01-01.

Examples for a run on 2026-10-26:

| Latest APG | Latest 71 | Download/replacement range |
| --- | --- | --- |
| 2026-10-21 | 2026-10-21 | October 22 through 26 |
| 2026-10-26 | 2026-10-26 | October 25 and 26 |
| 2026-10-26 | 2026-10-23 | October 24 through 26, both companies |

The latest-date rule fills the missing **tail** of the archive. It does not assert
that arbitrary historical holes before the latest date have been detected.

## Source fidelity and safe publication

- ERP StockStatementReport uses **SalesType=0**, with both dates explicitly
  posted and checked after Refresh. Downloads span at most seven days each.
- All original rows are retained: sales, ReturnPOS, transfers, adjustments,
  inbound/outbound, signed and zero quantities, and document numbers. There is no
  sales-only filter, absolute-value conversion, grouping, or deduplication of
  legitimate identical source lines.
- Every row's date, identity and numeric quantity are validated. Invalid rows
  fail the whole source instead of being silently dropped. A suspected Excel
  row-limit truncation also fails the source.
- Both company files are validated before staging any date in that download
  range. Staging uses **5,000 rows maximum per batch** on client and server.
- Each day's complete batch sequence, file hash, row count, signed quantity sum
  and fingerprint uniqueness must reconcile for both companies.
- Only then does one transaction delete the old rows for that date and the two
  companies and insert the replacement. Any insert/verification failure rolls
  back the deletion. Other dates and companies are untouched.
- Retried batch requests are immutable. A lost publication response is resolved
  by its stored receipt rather than inserting a second copy. A source downloaded
  before a newer archive write is rejected as stale.
- Publication coordinates with the legacy full-history month's advisory locks.
  An overlapping monthly file checkpoint is marked incomplete because the
  refreshed slice no longer equals its old immutable source file. Daily receipts
  record the new complete slice; old source-file counts are not fabricated.
- A date with no rows can be published only after both complete, correctly dated
  reports were validated and explicit empty batches staged. Its receipt prevents
  the planner from mistaking a verified empty day for an unfinished import.

## Failure isolation

The preflight runs in a child process with a **300-second total limit**. Failures,
missing database setup, missing local dependencies, worker exit codes and timeout
are logged as warnings; the existing `main.py` always continues. On Windows,
timeout terminates that worker's process tree, including its browser children.
The publisher RPC alone has a 30-second statement timeout and a 2-second lock
timeout. Real publication of October 21 took 12.22 seconds and exceeded the
inherited 8-second REST limit; this narrow exception avoids changing any other
report's limits. The parent still enforces the same 300-second total worker limit.
The parent sends **STARTED** and then **SUCCESS** or **FAILED** emails using the
existing `main.send_email` sender, recipient and SMTP settings. The result includes
the requested period, confirmed published dates and row counts. Failure emails
include partial progress; timeout also produces a FAILED notification. If a worker
is interrupted during a database publication, its last local summary may not yet
include that receipt; the next run checks the authoritative server state.

Each email attempt is isolated with a 10-second wait limit. Email errors or stalls
do not stop the worker or existing main reports. Delivery still requires working
SMTP/network settings. The child suppresses legacy login-helper emails to avoid
duplicate notifications and logs progress in the scheduler console. Main's other
report notifications are unchanged. Standalone `--plan-only` and `--dry-run`
commands do not send emails.

Each date commits separately. If catch-up succeeds for some days and then fails,
completed dates remain, and the next scheduled run resumes from the saved dates.
A large initial backlog may require multiple scheduled runs under the time limit.
There is no database trigger or independent schedule for this worker.

## Transfer to the work computer

Copy **both files together** into the same existing automation directory:

1. `automation/main.py`
2. `automation/statement_history_daily_sync.py`

The existing scheduler continues to launch `main.py`; no scheduler edit/restart is
needed to pick up this preflight on its next main process launch. Use the same
Python environment and ERP/Supabase configuration as main. The new worker needs
only the already-used pandas, requests, Playwright and timezone support. It does
not require tkinter or direct PostgreSQL credentials on the work computer.

Install the migration `*_stk_statement_history_daily_refresh.sql` once in the
Inventory System database. The staging schema is private, RLS-protected, and
the three public RPCs are executable only by `service_role`. No client/browser
role can publish or delete archive rows through these endpoints.

No file under `D:\automation` is changed by this repository implementation.

## Checks and manual commands

From the `automation` directory:

```powershell
python -m unittest test_statement_history_daily_sync test_statement_history_daily_sql -v
python statement_history_daily_sync.py --plan-only
python statement_history_daily_sync.py --dry-run
python statement_history_daily_sync.py --from-date 2026-10-21 --date 2026-10-26
```

`--plan-only` reads server dates without downloading or writing. `--dry-run`
downloads and validates complete ERP files without staging or publishing.
`--from-date` explicitly replaces the requested inclusive range, even if the
planner considers its first date already saved. It does not change scheduled
latest-date planning. The example with `--from-date` performs real publication.
The SQL regression tests use a disposable schema and roll back all test writes;
they never delete or insert operational archive data. Normal execution without
these flags performs the validated replacement; do not invoke all of main's
reports just to test this worker.

## Validation on 2026-10-26

The new refresh tests and the existing raw-history parser tests passed (26 tests).
SQL cases ran against disposable schemas with full rollback. The live service-role
plan correctly returned October 22 through 26 for both companies' latest saved
date of October 21. Browser roles were verified unable to call the new RPCs, and
the security advisor reported no findings for this feature. No live archive days
were replaced during setup/validation.

Email regression tests cover successful summaries, partial failure, worker
timeout, SMTP errors/stalls, retained progress and notification-free verification
commands. The updated worker suite passed all 18 tests. These tests mock delivery
and do not send real email. The transfer ZIP was rebuilt and its two Python files
were verified byte-for-byte against the repository sources.

The broader existing MRN suite has one unrelated failure:
`MRNTests.test_overflow_reopens_with_dates_without_invalid_post` reports
`Missing VIEWSTATE`. It fails identically when the new entrypoint preflight is
removed in memory. Its implementation and test were left unchanged.
