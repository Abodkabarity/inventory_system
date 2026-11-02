# Near Expiry: original receipt identity and corrections

Each alert is grouped by its own product, expiry and MRN receipt day. Its nested
product data also carries that original MRN date, number and expiry, even when
the current whole-product snapshot contains a newer receipt. Current stock and
sales remain whole-product facts. The grid shows the original receipt date
without an additional competing latest-receipt date; exports use the same date.

Discovery now reconciles historical alerts when the same nonempty MRN number,
product and normalized raw warehouse are present in the current source, but its
original expiry/date no longer qualifies. Quantity corrections and cancelled
receipts are included. A different MRN number or warehouse is not a correction.
Missing historical source rows remain durable evidence. Same-day withdrawals
retain their existing invalidation behavior.

Superseded alerts are atomically copied to the RLS-protected private
`stock_management_private.expiry_receipt_corrections` audit table with their
original payload and the matching current source facts. Review rows and notes
are retained unchanged. Audit failure rolls back the invalidation. No source MRN
rows, receipt dates, import scripts, public RPC permissions or bulk limits are
changed. Normal expiry cache revision triggers invalidate client caches.

The initial reconciliation corrected one stale alert: product `16-02-10592`,
MRN `107181`, actual receipt date `2026-10-30`. Its saved expiry `2026-06-01`
was absent from that source receipt, whose actual batches are 72 units expiring
`2028-06-01` and 28 units expiring `2028-12-01`. It therefore no longer qualifies
for Near Expiry; its original MRN date was never rewritten.

Verification:

```
node supabase/tests/stock_expiry_original_receipts_test.cjs
flutter test test/stock_expiry_test.dart test/stock_workspace_reopen_test.dart test/stock_workspace_memory_test.dart
```

The SQL test uses an isolated PGlite runtime via
`STOCK_CACHE_PGLITE_MODULE`, never production credentials. It checks original
dates, distinct receipt days, corrected expiry/date/status/quantity, durable
missing history, exact source/review preservation, audit rollback, idempotence,
unchanged function/view ACLs and caller RLS. Live verification found 267 retained
alert receipts, no mismatched original MRN identities and no new security
advisor findings.
