# Historical ledger reference

`public.stk_ledger_history` stores the ERP's raw **Actual Qty**, with explicit
`stock_date`, `report_from_date`, `report_to_date`, retrieval time and source
SHA-256. It does not adjust quantities by mismatch or pending transfers.

Run from the repository root, using the existing automation Python environment:

```powershell
python automation/stk_ledger_history.py --from-date 2026-01-01 --to-date 2026-01-01 --publish
```

Both dates must be equal: this command archives one dated ledger report, not a
period's movements. Omit `--publish` to download/validate only. The existing
`automation/main.py` login is reused with email disabled; the normal pipeline
and its live-table upload functions are not invoked. This is a manual command,
not a new recurring job.

Required environment variables: `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_HOST`,
`SUPABASE_DB_USER`, `SUPABASE_DB_PASSWORD`; optional `SUPABASE_DB_PORT`,
`SUPABASE_DB_NAME`, `SUPABASE_DB_SSLMODE`. Credentials are never logged.

APG and group 71 are downloaded separately. Group 71 membership is taken from
`branches.branch_group`; raw names remain unchanged in storage/import files.
Presentation/export consumers must use the shared `StoreBranchIdentityRegistry`
helpers to decorate group 71 names.

Downloads and their date/company/hash receipts are retained under
`outputs/stk-ledger-opening-YYYYMMDD/`. `--reuse-downloads` accepts a local source
only if its receipt matches both dates, company and file hash.

Rows for the same company/branch/item are summed, consistent with the live
ledger loader. Missing/invalid quantities and conflicting item names fail the
import. Explicit zero and negative source quantities are preserved. A source
row lacking a branch is preserved with `source_branch_missing=true` and must
be excluded from branch analysis. An absent product row is not a measured zero. Stock Management's availability
analysis separately supports an explicitly labelled zero-opening assumption for
omitted products under the requested business rule; see
[availability evidence](stock_supply_insights.md). It does not change this table
or turn the assumption into a measured balance.

All company data is staged in batches of 5,000 and committed in one transaction
after checking unique identities, row counts and quantity sums by branch.
A retry with identical data is a no-op; a different snapshot for an existing
date is rejected without changing that date. There is no truncation/replacement
of `stk_ledger` or other live tables. Access is restricted to the service role.

Example raw system balance query:

```sql
select stock_date, company, branch_name, item_code, actual_qty, imported_at
from public.stk_ledger_history
where branch_name = 'Al Noud - Ain'
  and item_code = '16-02-09130'
  and not source_branch_missing
order by stock_date;
```

The report date identifies the ERP filter; it is distinct from the import time.
This is a system reference, not a historical physical count. Reconstructing a
later balance still requires sales/outgoing movements/returns/adjustments as
well as incoming movements. Applying today's mismatch to a historical snapshot
would distort the historical position: use the mismatch valid at that time.
