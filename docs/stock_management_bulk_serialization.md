# Stock Management bulk response optimization

Applied to the Inventory System Supabase project on 30 October 2026:

- `20261030094656_stock_catalog_bulk_single_serialization`
- `20261030094953_stock_mrn_bulk_single_serialization`

## Result and scope

The two existing register RPCs now join receipt/reference/purchase data to page
rows before their final `jsonb_agg`. They no longer aggregate the complete page,
unpack it in `add_reference_columns`, and aggregate it again. Removing the
detail-only payload keys also uses one JSONB key-removal operation per row.

The shared helper remains unchanged for other page/detail/expiry endpoints.
The existing 5,000-row caps, offset/null behavior, totals, snapshot/reference
tokens, JSON fields, row order, security-invoker setting, search path, planner
setting, function OIDs and grants are preserved. No frontend deployment is
needed for these existing RPC signatures. No source, snapshot or review rows
are written and no refresh is triggered by these migrations.

Catalog reference quantities retain the latest approved receipt day across all
source warehouses. MRN vendor/expiry/count/ordered fields retain their existing
STORE/Main Virtual/New Virtual scope; reference and authoritative-total fields
retain the shared helper's all-approved scope. These aggregates intentionally
remain separate. Payload identities/dates remain the reference-enrichment keys;
source-column identities/dates remain the page/receipt/supply keys.

## Verification

- `supabase/tests/stock_bulk_single_serialization_test.cjs` performs 42 exact SQL
  old/new comparisons in isolated PGlite, plus independent expected-value
  assertions. It covers duplicate receipt lines and purchase assignments,
  case/whitespace normalization, pending/cancelled/undated receipts, blank
  latest references, negative/null/authoritative totals, unexpected warehouse
  scopes, empty/tail pages, nullable/out-of-range arguments, 5,000-row caps,
  version metadata, Inventory/View/branch/service/anon access and unchanged ACLs.
- `test/stock_reference_worker_test.cjs` passed for all four stock worksheets,
  preserving Total Qty, Bonus Qty, Reference, Purchase Status, a group 71 branch
  label and another-group branch label. Raw branch identities remain unchanged
  in SQL; existing registry formatting stays at presentation/export boundaries.
- Before publishing each RPC, a transaction-local candidate was compared with
  the original against the same repeatable-read production snapshot under an
  authenticated Inventory account. Every page matched with SQL JSONB equality
  and complete-response MD5 digests: all 12,475 Overview products and 9,756 MRN
  products, plus empty pages. The first pages also matched under a View account.
  Candidate transactions were rolled back; temporary candidate functions were
  not exposed through the Data API.
- After publishing, all five production pages were verified again with an
  explicit eight-second local statement limit. All completed and every response
  digest matched its original. Source MRN and both full snapshot-table digests
  were unchanged (127,826 source rows, 12,475 catalog rows, 9,756 MRN rows).
- Fingerprints for all other stock functions, RLS policies, role settings and
  authoritative branch metadata were unchanged. Both RPCs kept their OIDs,
  ACLs and settings; anonymous execution remains denied.
- Security/performance advisor findings were identical before and after.

## Server timing samples

Old and candidate times below come from consecutive calls in the same
repeatable-read transaction, under the same Inventory identity. Equality and
digest checks follow the timing interval. Post-publish times include digest
verification and were taken in separate read-only, eight-second transactions.

| Register | Offset | Rows | Old ms | Candidate ms | Post-publish ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Overview | 0 | 5,000 | 3,738.85 | 2,000.61 | 2,270.47 |
| Overview | 5,000 | 5,000 | 3,407.51 | 1,893.12 | 2,089.07 |
| Overview | 10,000 | 2,475 | 1,729.46 | 1,256.83 | 1,408.69 |
| MRN | 0 | 5,000 | 2,140.63 | 1,850.43 | 1,987.37 |
| MRN | 5,000 | 4,756 | 1,875.68 | 1,607.14 | 1,785.00 |

These are bounded server-side samples, not a browser latency or peak-load
benchmark. They show lower response-construction time for these pages, not a
guarantee that resource contention or all future timeouts are eliminated.
Import execution, background builders, API timeout settings and client cache
invalidation were not changed in this phase.

## Re-run the isolated checks

```powershell
$env:STOCK_CACHE_PGLITE_MODULE = (Resolve-Path validation/stock_cache_sql_runtime/node_modules/@electric-sql/pglite).Path
node supabase/tests/stock_bulk_single_serialization_test.cjs
node test/stock_reference_worker_test.cjs
```

The fixture `supabase/tests/fixtures/stock_bulk_serialization_baseline.sql`
captures the previously published definitions for comparison. A rollback would
restore only the two public register definitions from that fixture with
`CREATE OR REPLACE`, preserving grants. Do not apply the fixture wholesale:
its shared-helper definitions are test dependencies and were not changed.
No rollback has been applied.
