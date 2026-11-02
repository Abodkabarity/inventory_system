# Overview snapshot refresh: narrower distribution rows

Date: 2026-10-30 (Asia/Dubai).

## Scope

Migration: `20261030073230_stock_catalog_refresh_narrow_stock_rows.sql`.
Applied to the linked Inventory System project and recorded in migration history.

Only two expressions in `stock_management_private.refresh_catalog()` change:

- `order_branches` reads the branch quantity directly from the existing `ledger`
  CTE, keyed by both item code and normalized branch key.
- Its existing `max(coalesce(...,0))` aggregate retains the same numeric value.

Previously the join carried the complete per-product `branch_stock` JSON through
approximately 733,150 order rows to extract one branch's quantity. The effective
ledger already supplies exactly that quantity with one row per item/branch.
The grouped ledger, distinct latest orders, and grouped active branch identities
in `effective_stock_balances()` ensure that uniqueness.

No source rows or published snapshots are rebuilt by this migration. No filters,
date handling, numeric formulas, permissions, schedules, timeout settings, client
batch sizes, or branch presentation/export code change. Raw branch identities
remain raw; group 71 display formatting remains at UI/export boundaries.

## Verification

The migration was first run inside a rolled-back transaction. Reversing the two
substitutions reproduced the original function definition byte-for-byte. Full
snapshot and MRN-source row fingerprints, RLS policy definitions, other private
Stock functions, function OID, ACL, security mode and settings remained unchanged.
The same integrity checks passed immediately after deployment:

| Dataset | Rows | Full-row digest, before and after |
| --- | ---: | --- |
| Overview snapshot | 12,475 | `7c402bda2bf94629be88a993f09ede1b` |
| MRN snapshot | 9,757 | `befdd16cfb3fc86d493186a6f383dca8` |
| MRN source | 127,833 | `1e527ef669fb47237eecdc731e1db110` |

The live refresh state retained its previous completed timestamp. Performance
advisor counts stayed at 49 and security advisor counts remained unchanged.

Full output comparisons use four disjoint hash partitions of the eligible catalog.
Each partition compares every returned column and full JSON using bidirectional
`EXCEPT ALL`, under a single repeatable-read transaction. The probe replaces the
unchanged runtime metadata object with `{}` in both expressions. Temporary result
tables are rolled back; production snapshots are never replaced by the probe.

All four production comparisons passed: 3,167 + 3,141 + 3,083 + 3,084 = 12,475
products, with zero differences in either direction in every partition.

Local PostgreSQL/WASM tests cover duplicate daily orders, trimmed/case-normalized
branches, formulary overrides, negative/zero/null/missing stock and old order runs.
The export worker regression also checks Overview, MRN, MRN CD and Near Expiry
reference fields and branch labels.

## Measurements and limits

The existing daily job ran seven times successfully in the preceding week:
mean 201.82 seconds, range 190.72–237.22 seconds, with a 240-second job timeout.

The optimized full calculation SELECT returned 12,475 products in 92.74 seconds.
That is a calculation-only probe, not an exact before/after job benchmark: the
daily job also writes the snapshot and runs at a different time/load. The original
full SELECT probe exceeded the Management API gateway response window, so no
precise old SELECT timing is asserted. No timeout was increased to obtain a gain.

After deployment, a complete execution of the installed function against an
indexed temporary snapshot table produced all 12,475 products in **59.145 seconds**.
This is approximately 71% below the preceding daily-job mean (201.82 seconds),
and leaves much more room within the unchanged 240-second job timeout. It is a
single shadow benchmark under current load, not a peak-load guarantee or a new
published daily-job measurement. The next scheduled job will use the optimized
function normally. The live snapshot was left at its previous version.

## Re-run

```powershell
$env:STOCK_CACHE_PGLITE_MODULE = (Resolve-Path validation/stock_cache_sql_runtime/node_modules/@electric-sql/pglite).Path
node supabase/tests/stock_catalog_refresh_narrow_stock_test.cjs
node test/stock_reference_worker_test.cjs
node validation/stock_catalog_refresh_probe.cjs --parity --part 0
node validation/stock_catalog_refresh_probe.cjs --parity --part 1
node validation/stock_catalog_refresh_probe.cjs --parity --part 2
node validation/stock_catalog_refresh_probe.cjs --parity --part 3
node validation/stock_catalog_refresh_probe.cjs --shadow
```

`--shadow` copies the currently deployed function into a temporary schema and
redirects only the snapshot destination to a temporary table with the same
indexes/defaults. It executes the complete function and rolls back the transaction.
It cannot publish a new Overview snapshot.
The probe uses a separate advisory-lock key so it does not reserve the live
refresh lock. Temporary destination tables do not copy production triggers.

## Rollback

In a new migration, restore only the `order_branches` expressions:

```sql
-- Quantity expression:
max(coalesce((s.branch_stock->a.branch_key->>'stock')::numeric,0)) stock
-- Join:
left join stock s on s.item_code=c.item_code
```

Preserve all later function changes and all ACL/settings when preparing rollback.
Rolling back this optimization does not require restoring any business data.
