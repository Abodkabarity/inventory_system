# All-branches ranking study — approved account only

On 24 November 2026, the user explicitly requested publishing the study for
`94c7aa76-bc23-40e4-8c9a-f2cb9636c821` only. This approval extends that account's
Online Overview study view to active selling branches; it grants no other users
access. Navigation, route rendering, client requests and every server action
retain the exact-ID restriction. Server reads also require active Inventory status.

The default Ranking trial tab shows all 61 eligible selling branches. Online only
opens the unchanged original Online Overview page and its own original cache.
Its prepared data, ranking rules, jobs and server functions are not replaced.

The study uses the frozen 24 November capture of 8,922 Normal Purchase products:
completed May–October 2026 Online + Cash + Insurance sales after returns, current
Retail value, first approved positive MRN and the 23 November branch stock ledger.
Online sales and Cash + Insurance sales appear side by side for the same period.
A/B/C use the reviewed independent branch/Qty/value/premium paths, with recomputed
cutoffs and unchanged repeat-sales/MRN rules. S/N/M/T/Review are recomputed for
this network; STORE stock stays separate. The same-snapshot online control gives
a fair comparison. The study is rules-based, not a new machine-learning model.

PIXEL - AD and its confirmed renamed identity APG – PX are excluded until opening
is confirmed. LIWA remains active in the denominator but has no stock report;
missing balances stay unknown rather than being converted to zero for M/N.
The availability dialog uses all products in each A/B/C group, independent of
page filters. Details and exports retain authoritative group-71 name formatting.

The private all_branches_trial_private cache is already prepared and fully
reconciled. Reads reject changed branch rosters, stale generations, duplicate or
incomplete pages. Client batches and RPC limits are 5,000. Detail payloads load
only for the opened product. Exports cover the complete filtered/sorted result.
RLS has no client table policies; direct client table access is revoked. The
narrow authenticated SECURITY DEFINER adapter intentionally reads private prepared
data only after the account and current role checks; its search_path is empty.

This is a frozen study: Reload reads the prepared study, it does not recalculate
ranks against changing raw data. A new study capture requires explicit preparation
and verification. No training inputs, raw extracts, outputs, ZIP backups, local
preparation scripts, credentials, Recall code or unrelated changes are published.
The shared dashboard_theme.dart dependency contains presentation primitives only.

To stop the study rollout, disable AllBranchesTrialConfig.enabled in a separately
reviewed release; the original Online Overview entry remains available unchanged.
Keep the scoped publication manifest pinned to this exact reviewed release.
