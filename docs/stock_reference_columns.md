# Reference columns in Stock Management

Overview, MRN Overview and Near Expiry show a selectable text **Reference** column
immediately after the product, with the same values in their Excel reports.
Sorting and Excel-style filtering treat references as text, preserving zeros.
Missing references display as a dash and export as an empty text cell.

- Overview: all distinct nonempty references on the latest approved MRN date.
- MRN Overview: references on the row's displayed latest receipt date.
- Near Expiry: references for the exact product, MRN date and expiry date.

Multiple references are joined with ` · ` in a stable order. All approved
warehouse routes are eligible. There is no fallback to an older reference or
another expiry/date when the selected group has no reference.

The server enriches complete pages using one set-based query, preserving row
order, quantities, review identities and the 5,000-row server/client limit.
Product details use the same scopes. The helpers are security invoker and
follow receipt-table RLS. Raw branch names and group 71 presentation rules are
unchanged.

MRN receipt revisions invalidate Overview register/detail caches as well as
the existing MRN/Near Expiry caches. Overview also checks `reference_version`
against its metadata response on each batch, rejecting an import change during
loading without weakening existing count, duplicate or snapshot checks.

Validation covers all list/detail RPCs, leading zeros, multiple references,
date/expiry separation, empty/null cases, RLS, cache revisions, unchanged KPIs,
sorting/filtering/row opening in all three grids and typed native/worker exports.

## Purchase Status

All three grids also include **Purchase Status** immediately before their sales
columns, and the shared product dialog places it beside Reference. Excel exports
include the same text before sales. The payload field is `purchase_status_items`.

The status-only `availability_kpi_purchase_status` projection already joins
`purchase_status_items.status_id` to `purchase_status_options.id` and returns
`purchase_status_options.name`. This is independent of Item Report's `item_status`
and the legacy `purchase_status_items.purchase_status` text. A missing assignment,
null ID or missing option displays **Not assigned**. Inactive assigned options
retain their real names. Normalized duplicate codes do not duplicate stock rows.

The lookup runs within the existing page/detail enrichment, with no per-product
network request or new table permissions. A lightweight fingerprint of the status
projection invalidates cached registers and details after assignments, option
renames or removals. MRN discovery retains its receipt-only cache key. The shared
5,000-row bulk limit, stock quantities, receipt scopes and branch formatting stay
unchanged.
