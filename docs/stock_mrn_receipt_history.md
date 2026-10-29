# MRN receipt history in the product dialog

MRN Overview still shows one row per product with its latest receipt-day totals.
The expandable **MRN receipt history** section loads all approved receipts for
that product, newest first, when opened. The closed header immediately shows the receipt count,
date range, number of receipt dates and total received quantity over that history.
The table adds the MRN date before the number, reference, warehouse, expiry,
vendor and ordered/received quantities. Vertical and horizontal scrolling keep
long histories inside a bounded area.

The small `receipt_history_summary` is included in the existing product-detail
response (including nested `mrn_details`). It aggregates only the requested
product using the approved-history index; it does not build or return history
rows or require another network request. The section uses this summary until
the complete history is expanded, then uses the newly loaded history totals.
The existing details cache revisions invalidate it on MRN imports. Publishing
the summary also bumps the receipt revision so existing cached details reload.

Rows remain separate by MRN date, MRN number, warehouse and expiry. Matching
source lines are summed; signed quantities and missing expiry dates are retained.
All approved warehouse routes are eligible. This history does not alter the
latest receipt cards, stock balances, charts or Near Expiry review grouping.

The new security-invoker RPC `get_stock_management_receipt_history` follows the
source table's RLS. Both server and client use 5,000-row bulk pages, with the
client using `StockManagementLoadConfig.batchSize`. Every page must match the
product, total and receipt-source revision; duplicate identities, truncated pages
or a changed import abort the result. Only a complete history is cached in the
existing account-scoped workspace memory, validated against server revisions.
Branch labels continue to use the shared identity registry and refresh when
group metadata arrives; group 71 names are decorated once at display time.

Validation: isolated SQL tests cover pagination beyond 5,000 rows, expiry splits,
returns, routing, revision tokens and RLS. Flutter tests cover lazy loading,
cache invalidation, incomplete/mixed/duplicate responses, retry, desktop/mobile
layouts and group 71 labels loaded after the table opens.
