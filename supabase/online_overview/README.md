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
