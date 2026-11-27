# Temporary Tibah Max files and Store preparation

Revised **26 November 2026**, including the explicit clear-on-failure request.
This supersedes the original single-Tibah design and the former retain-on-failure policy.
The additive backend is installed. On 27 November 2026 the user explicitly
approved publishing this Tibah update for a real trial. The release is isolated
from local Preparation monitor, mobile, Recall and Online Overview follow-ups.
The active authoritative branch `Tibah UPP` was created at the user's request;
Regular has not been created. Branch group/type/zone were left unspecified.

## Independent branches

The UPP action resolves the real registry name `Tibah UPP`; matching is
case-insensitive. The separate Regular action requires a future active
`tibah regular` registry entry and fails safely until it exists.
The importer resolves the exact raw registry name server-side, case-insensitively;
it does not accept client-provided branch scope or guess a branch group.

- **Upload tibah upp** replaces all Max for the UPP branch only, reason `UPP`.
- **Upload tibah regular** replaces all Max for the Regular branch only, reason
  `Regular`. Neither import deletes the other branch's Max or pending order.
- Each branch has an independent current upload ID, replacement conflict check,
  print snapshot and Store completion state. Both Store cards may coexist.
- A branch appears with the ordinary Store branches after its file is committed,
  independently of order days. It disappears only when Store confirms
  **preparation finished**. Opening or printing does not complete it. Another file
  for that branch makes it appear again; the other branch stays unchanged.
- Completion changes the preparation state only. Max remains until its branch's
  next upload, as in the preceding implementation; no extra deletion on
  completion has been authorized.

## Dedicated file format

CSV and XLSX use three required columns, in any order:

| Item Code | Item Name | Qty |
| --- | --- | --- |
| 00123 | Example product | 20 |

Keep codes as text in Excel. Item names from the file are stored in the staged
rows and Max records. Matching/validation uses Item Code; catalog/source rows are
never renamed. Store print metadata continues to come from calculated Daily Order.
Empty names, formula inputs, unknown/blocked codes, duplicate codes/headers,
negative/nonfinite Qty, and empty files are rejected.

For **both dedicated Tibah imports only**, the server always writes:

- `current_demand_30d = 0`
- `adjustment_type = 'INCREASE'`, including when Qty is zero
- `max_adjustment_30d = qty =` the uploaded Qty
- `reason = UPP` or `Regular` according to the selected dedicated action

The server ignores extra client demand/type/branch fields. Ordinary Max import,
its format, adjustment classification and other branches' records are unchanged.

After a file is selected, a separate `begin` request commits clearing **that
branch's old Max** and superseding its old Store request, before decoding or
validating the selected file. Canceling the picker changes nothing. The cleared
old data is **not restored** if parsing, validation, configuration, staging or
commit subsequently fails. Failed rows do not become a printable Store order.
The other branch retains its data throughout.

The file is decoded only after the server acknowledges clearing. `configure`
then sets the validated row count. Rows are staged with
`DataBatchConfig.batchSize` (4,000); only a complete validated file is installed
and becomes a pending Store request. A newer `begin` for the same type supersedes
an earlier attempt, and stale configure/stage/commit requests fail with `PT409`.
Changing the other type does not invalidate this upload. Error handling performs
no second delete that could erase a newer successful file. Writes are never
automatically retried after uncertain outcomes; refresh if a connection fails.
A server-unreachable clear request cannot guarantee a deletion occurred.

## Calculation and printing

This feature does not start Base/Final Reorder on upload. Their existing functions,
mathematics and schedules remain unchanged. A card first shows **Preparing**;
printing waits until the normal pipeline recalculates every uploaded code with
the file's Max for one run date. Triggers observe only the two exact Tibah names.

All allocations, including zero Qty, count toward preparation completeness. Only
positive final Qty is shown for Store preparation. Once ready, the print snapshot
is immutable; reads are pinned to the upload ID and validate row counts/duplicates.
A stale completion cannot finish a newer upload, and completing one branch never
completes the other. Store polls the compact headers every 15 seconds.

The Tibah branch card and detail dialog explain the activation window. Pending
cards say **Next calculation (~9 PM UAE)** and **Then until Store confirms**.
Ready cards say **Ready to prepare now** and **Until Store confirms completion**.
The dialog explains that a file uploaded after the current calculation waits
for the next cycle. The evening time is an approximate user-facing reference,
not an exact finish time, a promised date, or a new clock-based gate. The existing
19:50 source refresh and dependent calculation schedules remain unchanged.

UPP is purple; Regular is blue. Large labels appear before printing and on every
PDF page: **UPP MEDICINE / UPP GENERAL** or **REGULAR MEDICINE / REGULAR GENERAL**.
The branch, upload time in Dubai and short upload ID are included. Text remains
recognizable in grayscale. Branch presentation uses
`StoreBranchIdentityRegistry.displayName` and authoritative group 71 metadata;
raw registry names are preserved for all database identities.

**Current Demand = 0 is the saved Max record's comparison field.** It does not
force the calculated Daily Order demand to zero, and `INCREASE` does not guarantee
Final Reorder equals the uploaded Qty. Existing Demand, Min/Max, MOQ, formulary,
purchase-status and STORE allocation rules continue to apply.

## Temporary feature and later retirement

Do not retire this feature until the user asks. Its isolated integration points:

- Client switch: `TibahMaxConfig.enabled`, controlled by
  `--dart-define=TIBAH_MAX_ENABLED=false` when retiring it.
- Server controls: `tibah_order_private.branch_controls.enabled`, one row for
  `UPP` and one for `Regular`. Both must be disabled during retirement.
- The dedicated parser, dialog, RPC and print toolbar are separate files.

When explicitly asked to remove it, disable the client switch and both server
controls together. The two names then follow the ordinary Store/Max paths; the
special upload buttons and polling disappear. Do not delete real branches, Max
records or saved history as part of retirement without a separate instruction.
The ordinary Max importer never depends on the switch or the private schema.
Base and Final Reorder have no special branch calculation logic to undo.

## Backend and verification

Migration chain: `20261125101442_tibah_max_order_workflow.sql`,
`20261125103403_tibah_order_print_snapshot.sql`, then
`20261126065929_tibah_separate_branch_max.sql`, followed by
`20261126071113_tibah_clear_before_file_validation.sql`.
The old singleton control is unused legacy history; the two branch controls are
now authoritative. Legacy single-Tibah uploads are retained, never reassigned to
the new identities. No such uploads existed at the revision's installation.

`public.tibah_max_order` is an invoker wrapper around private privileged functions.
Every action checks an active `app_users` account and authorized role. Inventory
can stage/replace; only Store can complete; both can read. Private tables have RLS
and no client table grants. Informational advisor notices about no RLS policies
are expected for these intentionally default-deny private tables.

The hosted transactional SQL suite verifies early deletion despite an empty or
incomplete file, independent replacements and same-code
coexistence, fixed zero demand/INCREASE even with zero Qty, uploaded names,
independent completion/reappearance, frozen snapshots, pagination, concurrent
same-type conflict, permissions, feature disablement and unrelated Max hashes.
It also stages/commits 4,000 catalog rows under the actual 8-second authenticated
API statement timeout. All fixtures are rolled back; this is not a claim that an
end-user browser upload was exercised.

Dart tests cover both current headers, typed requests, CSV/XLSX, identifier
preservation, sparse cells, formulas, duplicate/invalid inputs, 4,000+1 staging,
write failures, replaced snapshots, responsive labels and retirement routing.
PDF previews are local test fixtures in `tmp/pdfs/tibah/`, not real orders.
Verification passed: 19 Dart tests, the separate feature-disabled routing test,
the hosted rollback suite and the final Flutter debug web build. The four PDF
variants were rendered and inspected; type/branch headings were checked on every
page. Static analysis found only pre-existing `avoid_print` informational notices.

Original functions verified unchanged:

- Base: `b88d3329ef46eb0221892eb9cd7b07bd`
- Final Reorder: `76fc0af66d37ed9325af819086fae5e3`
- Ordinary Max import: `997295e6e68b5c81aa0e01d3b8ff015f`

## Publication verification, 27 November 2026

The exact-name rollback suite `supabase/tests/tibah_live_branch_isolation_test.sql`
uses the real `Tibah UPP` identity and a temporary Regular branch. It verifies
same-SKU separation, independent replacement/clear/completion, failure behavior
and a 4,000-row file; all fixture rows are rolled back. The production branch
remains active, with no trial Max or private uploads created by these tests.
Only Tibah feature files, its reviewed integration and installed migration
history are included. Existing Online Overview/Recall publication guards remain.
