# Reopening Stock Management pages

Overview, MRN Overview, MRN CD Overview and Near Expiry immediately display the
last complete in-memory register when returning to a page in the same session.
The existing server revision check continues in the background; a thin progress
bar remains visible, and export/review actions wait for validation. Changed
revisions load and validate a complete replacement before it is displayed.

Only complete, previously validated registers can be previewed. They remain
scoped to the Supabase client and session, with separate STORE and MRN CD keys.
Expiry preview keys include search, review state and urgency. Explicit refresh,
review writes and session changes invalidate the relevant memory as before.
Failed validation removes the preview from the page and cache. Partial batches
and mixed snapshots never become previews. A full browser reload starts with
empty session memory and still loads normally.

The MRN dashboard's expiry summary now shares the existing receipt-discovery
revision check and caches its metadata-only result. Reopening MRN no longer
unconditionally calls receipt discovery through the generic page API. The bulk
batch remains `StockManagementLoadConfig.batchSize` (4,000); the summary requests
one row, independently of bulk loading.

Regression coverage includes actual page disposal/recreation, a delayed server
response, unchanged and changed revisions, denied permissions, query/warehouse
isolation, account changes and review-write invalidation:

```
flutter test test/stock_workspace_reopen_test.dart test/stock_catalog_memory_cache_test.dart test/stock_workspace_memory_test.dart
```
