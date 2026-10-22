# View role

Set the intended user's `public.app_users.role` to `view` and keep `is_active`
enabled. A branch or zone assignment is not required. On sign-in, the role opens
Stock Management Overview with the Inventory Management drawer containing only:

- Stock Management: Overview, MRN Overview, Near Expiry
- Availability KPI
- Fill Rate KPI

Search, filters, product details, reload and report exports stay available.
Catalog rebuild, expiry note editing and marking/reopening reviews are excluded.
The role does not start Inventory Dashboard loaders, tracker badge queries or
inventory order subscriptions. Inventory and other existing roles keep their
navigation. Raw branch identities and the shared group 71 display registry are
preserved.

Apply `20261022120906_add_view_dashboard_role.sql` and
`20261022121419_harden_stock_refresh_role_checks.sql` before deploying the client.
It adds SELECT policies for stock workspaces and their cache revisions. The
existing Items Tracker role helper stays unchanged. The second migration makes
inventory refresh guards reject a NULL role as well. Expiry preparation reads
the persistent register for viewers without triggering discovery. Existing
scheduled/import refresh processes keep updating the register.

Verification:

```powershell
flutter test --no-pub --platform chrome test/view_drawer_test.dart test/view_kpi_branch_labels_test.dart
flutter test --no-pub test/view_stock_read_only_test.dart test/stock_expiry_test.dart
```

Run `supabase/tests/view_dashboard_role_test.sql` against a database with an
active view, inventory and category users and populated stock snapshots. It
impersonates these users inside a transaction, checks reads, mutation denials,
deactivation and role isolation, and rolls back.
