# Project instructions

## Bulk loading

- Use 5,000 rows as the default batch size for bulk data loading in new or
  modified features. Keep server RPC limits aligned with the client request.
- Stock Management's Overview, MRN Overview and Near Expiry must use
  `StockManagementLoadConfig.batchSize` from
  `lib/core/config/stock_management_load_config.dart` rather than separate sizes.
- Metadata-only requests, explicit small-page requests, writes and export-worker
  processing chunks are separate from bulk loading and retain suitable limits.
- Preserve completeness, duplicate and snapshot checks when changing batch sizes.

## Branch 71 names

For every new or modified feature in this repository, display branches whose
authoritative `branches.branch_group` is `71` with `71 ` before their name.
This is a persistent project requirement across conversations.

- Use `StoreBranchIdentityRegistry.displayName(rawBranchName)` from
  `lib/core/utils/store_branch_identity_registry.dart` for all branch labels:
  cards, tables, selectors, dialogs, tooltips, report titles, printouts, PDF,
  Excel, CSV, and other exported branch cells.
- For generic exported rows, use the registry's `exportValue` helper for branch
  fields. Decorate names before sending display rows to an export worker.
- Use `branches.branch_group` through the shared registry to identify the group;
  do not guess membership from a branch name or prefix every branch.
- Add the prefix once. Preserve the branch's name and leave other groups' labels
  as they are.
- Keep raw names for database writes, filters, identifiers, matching imports,
  grouping, and KPI calculations. Formatting is applied at presentation/export
  boundaries, so counts and product matching keep their original identities.
- Ensure labels refresh when registry metadata loads after the screen opens.
  Branch search should accept the displayed name, including `71`.
- When publishing a feature to master, include or verify its registry helper
  dependency. Do not strip this required formatting to make a build pass.
- Verify representative group 71 and other-group branches in affected UI and
  exports, including asynchronous worker exports when used.
