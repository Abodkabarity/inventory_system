# Online Overview server

User-scoped rollout approved on 19 November 2026 for
`94c7aa76-bc23-40e4-8c9a-f2cb9636c821` only. Every client read/refresh RPC checks
`assert_access()` against that ID and the active Inventory role. System jobs retain
privileged service access. Never broaden this allowlist without explicit approval.

The isolated cache and trained model artifacts are already present in the linked
project. The release migration restricts access without rebuilding or changing
source data. These SQL files version the existing backend for review and maintenance.
If reinstalling it, run operational_branches, abcmt, other_branch_stock, server,
six_month_forecast, stock_breakdown, branch_availability in order and ALWAYS finish
with restricted_user.sql before committing the transaction. The server.sql baseline
also enforces the approved ID; restricted_user.sql remains the final explicit policy step.
The final result builder reads sources and publishes an atomic private generation.
Training scripts and artifacts remain local; Update data rebuilds prepared results
with the existing trained artifact rather than silently retraining it.

## Recorded-sales update, approved 20 November 2026

The same approved account now reads `get_local_online_overview_preview`, a single
restricted RPC serving prepared recorded-sales ranks, stock, monthly and 45-day
online sales, and branch availability. The `preview` name is an internal API name;
the exact-ID and active Inventory guard applies in all build modes.

`actual_sales_preview.sql`, `current_month_sales.sql` and `recent_sales.sql` version
the deployed reader. Migration `20261120104231` installs these idempotent definitions
and checks that the existing prepared snapshot and every transport page are ready.
It does not modify product ranks, source data, original caches or scheduled jobs.
Every response remains pinned to its base generation and approved online roster.
Other Retail stock remains a single aggregate, with no branch-level detail access.

The original read RPCs remain available with the same single-user restriction for
older clients. Current-month charts replace current-month history with signed daily
online delivery Qty, excluding insurance and future invoices. This display period
does not enter classification or stock-cover calculations.

The prepared recorded-sales snapshot is maintained separately from the original
cache. After a base snapshot rebuild, prepare a matching recorded-sales generation
and its exact transport pages before serving it. A stale generation is rejected.
Local preparation/verification code and training data remain outside this release.
