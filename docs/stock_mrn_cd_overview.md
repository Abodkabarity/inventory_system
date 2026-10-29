# MRN CD Overview and reported total quantities

MRN Overview uses `mrn_apg_2026` as STORE receipts. MRN CD Overview uses
`mrn_cd_apg_2026`, with a distinct register row for each raw receiving warehouse
and product. Both registers group all approved receipts on that row's latest
receipt day. Earlier dates remain available in receipt history.

The new page appears directly below MRN Overview in Inventory and View menus.
Its Warehouse column is before Product, and its dialog/history is bound to the
selected warehouse. Stock and sales metrics retain the existing whole-product
scope. Products missing from the stock catalog remain visible with unavailable
stock data. Unknown warehouse names are preserved rather than guessed.

`total_qty` is the authoritative reported quantity. The UI does not reconstruct
it from `received_quantity + bonus`. Positive bonus quantities appear as a small
note beside Total Qty. This applies to STORE/CD registers, product receipt cards,
receipt histories and Near Expiry receipt-day groups/evidence. Excel includes
numeric Total Qty and Bonus Qty columns. Legacy internal received-quantity JSON
aliases are retained for compatibility, carrying the same total.

All CD RPCs use security invoker and the existing receipt/catalog RLS. A private
single-row revision tracks statement-level CD imports, including updates,
deletes and truncation. STORE/CD cache entries, details and histories are separate;
the receiving warehouse is part of every CD identity. Shared stock, catalog and
purchase-status revisions are included when validating CD cache reuse.

Bulk limits remain 5,000 through `StockManagementLoadConfig.batchSize`. Loads
verify counts, duplicate composite identities and matching revisions before
exposing the complete register. History uses the same limits and line identities.
Heavy branch/monthly data is requested only for the product dialog.

Branch labels, search, dialog labels and exports use
`StoreBranchIdentityRegistry.displayName`. Group 71 labels refresh after metadata
arrives; raw warehouse names remain unchanged in RPC parameters and cache keys.

Validation: `supabase/tests/stock_mrn_cd_total_qty_test.cjs`,
`test/stock_mrn_cd_test.dart`, existing MRN/expiry/dialog regressions, browser
worker exports and SQL reads of live quantities/warehouses.
