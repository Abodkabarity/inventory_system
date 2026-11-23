# Supply demand model reuse

This maintenance keeps the existing demand model and every displayed supply
calculation. It reuses the immutable model result only while analyzing the same
product input. It does not store a model across products, requests or snapshots.

The existing JSON contracts and function signatures remain. Private helpers pass
the model separately from the page/export payload. Existing owners, execution
grants, volatility and search paths remain unchanged. New helpers and their
result type are unavailable to `anon` and `authenticated`; only the database
owner and `service_role` can execute them.

`fit_supply_demand` and `refresh_supply_insights` remain byte-for-byte unchanged.
The migration checks the reviewed function bodies before replacing anything.
This preserves model selection, validation, rounding, stock reconciliation,
receipts, missing-data rules and prepared snapshot publication.

## Reproduce the comparison

Use the owner's read/write SQL connection with `SUPABASE_DB_PASSWORD` and
`SUPABASE_DB_POOLER_URL` for the Inventory project. Neither secret belongs in
command arguments or output files.

```powershell
python tools/verify_supply_model_once.py `
  --originals supabase/maintenance/supply_model_once_baseline.json `
  --report .dart_tool/supply_equivalence_report.json
```

The verifier captures the exact production preparation inputs into temporary
tables under one repeatable-read snapshot. It compares the original and
candidate full JSONB values and their text representations for every product,
including model diagnostics, quantities, monthly charts, evidence and summaries.
An aggregate digest provides an additional check. It also compares result/error
behavior for 15 edge cases, verifies service access and denied client execution,
and checks unchanged model/preparation definitions and existing function grants.

Timing uses PostgreSQL function execution counters, excluding client/network
time, alternates old/new execution order by batch, and throttles between batches.
The candidate must reduce measured analysis time and model calls without a
single payload difference. The transaction is always rolled back and never
writes production business rows or the published supply cache. Use `--installed`
after deployment to repeat the comparison against the installed functions.

## Page verification

The change contains no Dart, UI, export, route or authorization edits. The latest
page test run passed 100 functional tests across supply insights, supply status,
timelines, Overview, MRN, Near Expiry, exports and date filters.

The existing `stock management desktop visual` golden test fails on the unchanged
baseline too (5.41%, 70,075 pixels). Rendering the baseline and the candidate
produces identical PNG files with SHA-256
`80B030C81504C9A19FCB5680C559E051480E07EA9E641219C0542F3E23A4BF95`.
The reference image was not updated to conceal that existing failure.

## Candidate measurement (2026-11-23)

All 12,637 products matched exactly, including JSON text representation. The
aggregate digest for both outputs was `08532a1f4ea5d4a98b69e547ab371d3e`. All 15
edge cases preserved results or error codes/messages. The pinned input digest
was `8a4bdc1f6509102eeec76a64c91e8ccb`. No production business rows were written.

Model executions fell from 20,013 to 12,496 (37.56%). Measured analysis function
time fell from 69,035.75 ms to 65,358.94 ms (5.33%). This measures the analysis
stage, not the entire refresh or overall server CPU: source preparation, I/O
and other jobs still consume time. It is a modest improvement, not a claim that
the full scheduled job or page load became 38% faster.

## Installed verification

After the atomic database deployment, the full comparison was repeated against
the installed functions. All 12,637 products and all 15 edge cases still matched.
Both the pinned input and output digests matched the candidate run too. Existing
function grants/ownership/settings were preserved, new helpers denied `anon`
and `authenticated`, and `service_role` successfully executed the normal entry.

The installed measurement was 73,819.60 ms for the original and 70,068.20 ms for
the optimized analysis (5.08% less time), with 20,013 versus 12,496 model calls.
The regular 11:22 Dubai scheduled supply refresh also completed successfully.
No new Supabase security/performance advisory findings appeared after deployment.

Reports contain only aggregate metrics/digests. Product input payloads and
rendering artifacts are excluded from the commit.
