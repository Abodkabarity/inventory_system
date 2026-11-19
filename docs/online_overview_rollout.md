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


The published UI contains the current Online Overview, ABC/M/T/N/S ranks, product
details, Other branch stock, exports and Branch availability dialog. No ranking
logic changes are part of this rollout. The approved user's account must stay
active with the Inventory role. Access is checked independently by the server.
