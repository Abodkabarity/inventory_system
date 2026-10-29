# Automated STORE and branch MRN imports

Implementation prepared on 29 October 2026. Following the user's request to
activate it for the work-computer schedule, the database migration was applied
successfully on the same date. Function availability, source validation, service
role access and preservation of the last successful hourly status were verified.
No new security advisory findings were introduced. No receipt import was run.
No Git push or frontend deployment was performed.

The user chose manual ZIP transfer to the work computer. The package is
`exports/mrn_work_scheduler_20261029_v2.zip`; it contains only the two updated
Python scripts, Arabic installation instructions and file checksums. The
work-computer installation/first scheduled run cannot be confirmed until those
files have been copied there. The existing scheduler file and settings are kept.

## Files and activation order

1. Database step completed: applied
   `supabase/migrations/20261029081837_mrn_dual_archive_daily_hourly_sync.sql`.
   It depends on the existing two archive tables, extended columns, hourly state
   and Stock Management refresh functions. Do not apply this file a second time.
2. Deploy `automation/mrn_apg_sync.py` and `automation/mrn_apg_2026_hourly.py`
   together to the automation machine. They use existing dependencies and
   credentials; no credentials are included here.
3. Run the existing hourly job to replace today's complete snapshot. This imports
   actual ERP totals rather than backfilling from received quantities. The daily
   `main.py` entry point continues calling `append_missing_days` unchanged.

The Python files require the new SQL functions. Do not activate them against the
old backend; they fail rather than silently drop the new columns. Installing the
SQL does not restore old missing totals or deploy any frontend changes.

## Data handling

- Read `Total QTY` as `total_qty`, the exact `Bonus` column as `bonus`, and
  `Prepared By` as `prepared_by`. `Bonuse` is a different ERP column and is ignored.
- Preserve the original received and ordered quantities. Never calculate total
  from received quantity plus bonus, and never replace a missing total with zero.
- Route approved `store`, `main virtual`, `new virtual` rows to `mrn_apg_2026`.
  Route every other nonempty warehouse to `mrn_cd_apg_2026`.
- Normalize warehouse identities as before; keep raw names for database writes.
  No display prefixes are added to imported branch identities or restore backups.
- Reject missing/duplicated headers, malformed dates, empty item/warehouse,
  missing totals and invalid/infinite quantities before writing either table.
- Preserve identical repeated ERP detail lines; they are separate receipts.

## Daily and hourly consistency

Hourly imports back up both tables in pages of 5,000, retain the source workbook,
then call one `replace_mrn_apg_2026_archives_today` transaction. Both archives'
today snapshots are replaced, including removal of withdrawn receipts. An empty
STORE partition is valid when the day contains only branch receipts. A validated
zero-row day clears today's rows in both archives. Other dates remain unchanged.

Daily imports call one `sync_mrn_apg_2026_archives` transaction. They replace
yesterday and the latest saved receipt days covered by the complete source
export, and fill missing days. Existing older receipt days are preserved. Unlike
the old append-only latest-day merge, this also corrects missing totals/bonus and
removes withdrawn latest-day lines without accumulating duplicates. An absent
yesterday is rejected when saved yesterday rows exist in either archive, since
absence alone cannot prove a complete replacement. No approved rows anywhere is
also rejected by the daily importer.

Both RPCs share the existing advisory lock with hourly/daily/month importers.
They verify exact content and duplicate multiplicity after each table's write.
A failure in the second table rolls back the first table too. Atomic writes are
capped at 10,000 combined rows on both client and server; they are never split
into destructive partial replacements. This is separate from the 5,000-row bulk
read batch size. The complete source partitions and returned counts are checked
by Python as well.

New RPCs are service-role-only, use `SECURITY INVOKER`, and retain the existing
RLS. The internal table writer accepts only the two allowed archive names.
The new clients use distinct RPC names so an old function cannot report success
after discarding the extended fields. Existing legacy RPCs are retained for
compatibility; update all active script copies to use the new contract.

STORE counters on the existing hourly status card retain their STORE meaning;
branch counts are separate (`last_cd_rows`, `last_success_cd_rows`). Success is
recorded after MRN Overview/Near Expiry refresh. CD revision invalidation remains
handled by the existing CD table trigger.

## Validation

- 30 focused Python tests passed: parsing, routing, exact totals/Bonus vs Bonuse,
  duplicate lines, missing columns, zero totals, both backups, 5,001 backup rows,
  snapshot checks, one atomic RPC, download-only, refresh completion and the
  existing monthly import parser.
- `supabase/tests/mrn_dual_archive_import_test.cjs` runs the actual migration in
  isolated PGlite: exact payloads, rollback after a CD insert failure, retries,
  withdrawal/zero-day handling, 5,001 combined rows, month boundaries, untouched
  historical dates and role restrictions. No live database connection is used.
- `validation/check_saved_mrn_extended_import.py` checks the retained real ERP
  workbook offline, comparing imported totals/bonus with the source cells. It
  passed for 3,878 recent-week approved lines (3,713 STORE and 165 branches), and
  the retained 29 October snapshot (27 STORE and 7 branch lines). These are saved
  workbook counts, not a claim about the current live archive.
- The broader unchanged `test_mrn_main` suite has 11 passing tests and one existing
  failure: `test_overflow_reopens_with_dates_without_invalid_post` provides no
  bootstrap VIEWSTATE expected by current `main.py`. This change does not modify
  that login/bootstrap code or its fixture.

Run Python tests from `automation/`:

```powershell
python -m unittest test_mrn_apg_sync.ClientTests test_mrn_apg_hourly.HourlyTests test_mrn_dual_archive_2026.ParserTests -v
```

Set `STOCK_CACHE_PGLITE_MODULE` to the installed `@electric-sql/pglite` module
directory and run the SQL regression from the repository root:

```powershell
node supabase/tests/mrn_dual_archive_import_test.cjs
```
