# Overview for ordinary zone managers

The existing Overview page, table, cards, filters and product dialog are reused
without changing their design. Ordinary zone managers receive only Overview.
The Needs Distribution metric card is hidden for ordinary zones; the other four
cards fill the wide-screen row. Main and other roles retain the original card.
The permanent Main exception keeps its existing full-network, four-page workspace.
The shared View month details action is disabled for all roles at the user's
request. Chart selection, the selected month's numbers and exports remain intact.

Every new RPC derives the current effective branch set from the authenticated,
active zone manager's authoritative assignments and accepted, unexpired handovers.
No client zone, branch, user ID or cache key can broaden that scope. Permanent Main
users are rejected by the scoped endpoints and keep using their original endpoints.

The isolated `zone_overview_private` cache combines the current prepared stock
and order maps with only the allowed branches' sales. STORE is counted
once. Net quantities, returns, current-month daily sales, completed-month history,
cover, growth, annual and branch totals, distribution and exports use this scope.
Catalog and STORE facts are shared once; zonal metrics and detail arrays remain
separate. Product references use approved STORE receipts only.

Generic catalog fields and STORE evidence are whitelisted. Global demand models,
other branches' stock/sales, unknown future payload keys and unrestricted detail
or history RPCs are never copied to a zonal response. STORE empty-period evidence
is retained separately, and demand estimates use the zone's own daily sales.

Header, batch, detail and image reads recheck role, activity and the live branch
set. Batches/details pin the prepared version and return PT409 if the scope or
generation changes. Old-scope previews and global cache fallback are disabled.
The zone cache namespace is separate from the unchanged default/global namespace.
Returned authoritative branch-group metadata feeds the shared `71 ` label registry.

Historical preparation is resumable in bounded SKU chunks using existing source
indexes. Its compressed per-product branch histories are rebuilt only when annual
sales revisions, eligible products, needed branches or the calendar month change.
New generations become active atomically. Failed/partial builds preserve the last
complete generation. No page request performs historical preparation.

Preparation uses a separate maintenance function and its own minute job,
`zone-overview-preparation`. Each call prepares one shared batch of 500 SKUs;
this maintenance chunk is separate from the shared client bulk-loading setting.
All matching scopes reuse the same source batch. A complete refresh therefore
takes multiple job passes; the last complete generation remains readable during
preparation. A 35-second statement timeout bounds each scheduled invocation.
It skips while the existing Overview refresh is queued/running, uses advisory
locking, caps parallelism and memory, and never changes an existing source table,
global snapshot, policy, function or scheduled job. Only the new private cache and
maintenance metadata are written. Clients have no direct access to those tables.

Scoped demand totals, recent/baseline averages and daily charts use the same net
daily rows and cutoff. They do not reuse potentially older global branch demand
maps after a branch activation or sales correction. This affects only the new
zone cache; Main and the global snapshot retain their existing calculations.

Images use the separate read-only `zone-stock-product-gallery` endpoint. It checks
the caller's scoped SKU access before signing existing archived photos or reading
public product photos. It accepts no upload and does not create archive records.
The existing image endpoint and Main image behavior are unchanged.

Tests are in `test/zone_overview_access_test.dart` and
`supabase/tests/zone_scoped_stock_overview_test.cjs`. Existing Main/global cache,
retention and product-dialog regression tests also run. The database suite covers
forged versions, forbidden roles/direct reads/writes, delegation expiry, signed
returns, all sales channels, STORE references, 5,000-row caps and atomic failures.

Verification on 2026-11-24: all seven ordinary zone accounts read 12,584 unique
products in complete pinned batches. For each account, 100 stock samples matched
the source, and eight product dialogs contained exactly its authorized branches
with matching daily totals. Main read its original page and was denied by the
new scoped path. All 55 baseline global/Main function definitions and the 18 old
job definitions remained unchanged. Idle maintenance took about 51 ms; reading
all batches took 2.36–2.65 seconds per account inside PostgreSQL, excluding network
and client rendering. Flutter regression checks, the focused scoped dialog test,
isolated database tests, image tests and a debug web build passed.

The additive backend, scoped image endpoint and new job are installed. The user
authorized this scoped Flutter release to master on 2026-11-24, together with
hiding the shared month-details action. Publication uses a clean worktree; local
guides, images, training data, Recall and unrelated edits are excluded.
