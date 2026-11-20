## Online Overview — single-user publication approval (2026-11-19)

- The user explicitly approved publishing Online Overview ONLY for user ID
  `94c7aa76-bc23-40e4-8c9a-f2cb9636c821`. This narrow approval supersedes the
  debug-only/local-only restriction below only for that user's rollout.
- Enforce the ID in navigation, route rendering and every server read/refresh
  RPC, alongside active Inventory authorization. Never expose it to other users
  or broaden access without explicit approval. System maintenance jobs retain
  privileged service access. Use a clean publication worktree and include only
  the reviewed feature, dependencies and scoped migration. Keep training data,
  artifacts, credentials and unrelated workspace edits out of the release.
- Local publication guards must permit only the exact reviewed scoped release
  and keep rejecting the original unrestricted local branch and future unreviewed
  feature changes. Existing wider publication-hold instructions still apply.


On 20 November 2026, the user explicitly approved publishing the latest Online
Overview update to master for this SAME account only. This includes the recorded
six-month sales trial, plain rank reasons, the redesigned guide with examples
inside their rank cards, online-only current-month charts and performance work.

Release/profile/debug builds use the prepared recorded-sales register. Navigation,
route rendering and every server action retain the exact user ID plus active
Inventory requirement. Other users do not see the feature and cannot read its RPCs.
The newer Overview stock-column change on master is preserved.

A has independent routes through sales in at least 70% of open online branches,
top 35% by Qty, top 15% by current-Retail value, or the existing AED 1,000 premium
repeat-sales rule. B uses top 60% by Qty or top 30% by value after A; C covers the
remaining sales products. Repeat-sales conditions, MRN age handling and S/N/M/T
precedence remain as reviewed. The page explains all rules with current examples.

Current-month charts use signed daily online sales, replacing current-month
history. Ranking and stock cover keep their existing completed-month periods.
Prepared 5,000-row transport pages are copied exactly from the reviewed register;
the client validates completeness, duplicates, order and generation while loading
up to two pages concurrently. Charts wait for fresh detail responses, while the
dialog immediately shows already-loaded rank facts.

The release uses the already-prepared private snapshot. Its base generation must
match the original cache; a mismatch fails closed and requires preparation of a new
matching snapshot. Training scripts, saved input data and local artifacts are not
part of this release. The migration checks readiness and reapplies the unchanged
single-user server guard without rebuilding or changing source data.
