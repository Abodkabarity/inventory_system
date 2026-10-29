# Sales and supply analysis

The user-facing wording uses plain English: “Sales & stock check”, actual Qty
sold with the expected Qty explained underneath, “Less than 1 day” for fractional
day cover, and a sentence explaining that the low-stock percentage is weighted
by estimated sales rather than a count of branches. Receipt Qty is explained as
the amount received on its date, separate from stock left today. Transfer text
names sending/receiving branches and Qty to keep, and explains zero-extra cases.
Only wording and displayed estimate precision changed; model and allocation
calculations remain the same. Full values remain available in Excel exports.

## Receipt scope correction and redistribution

Approved `mrn_apg_2026` rows are STORE supply regardless of their warehouse route,
including `main virtual` and `new virtual`, per the clarified business rule.
Migration `20261023114734_stock_network_mrn_source_scope.sql` removes the narrower
physical-warehouse filter from the network analysis. A missing receipt displays
an em dash, not zero. No warning is inferred from absence of a virtual receipt in
the physical STORE MRN movement subset. This supersedes the narrower receipt
scope and confirmation descriptions below; raw stock reconstruction is unchanged.
Verified ACCU-CHEK 16-02-09208 returns 100 Qty on 31 Aug 2026, matching the register.
Migration `20261023120533_stock_network_latest_receipt_metadata.sql` also keeps
newly approved receipts visible through the current Dubai date, independently
of the older sales/stock cutoff. A newer receipt is marked separately and never
added to historical stock cover. The suggested action asks to review that receipt
and update stock before ordering more.

`20261023115146_stock_network_branch_extra_redistribution.sql` adds latest-run
Daily Order evidence to the same guarded product endpoint. The new redistribution
planner combines `extra_qty_more_than_month` with branch demand learned by the
forecast model. The allocation policy is explicit and is not a separately trained
optimization model. It writes no transfers, orders, or reservations.

Donor quantity is bounded by both declared extra and physical stock remaining
above the maximum of learned 30-day demand, Daily Order demand, 90-day sales rate
scaled to 30 days, assortment base and reorder max. Missing 90-day demand retains
all stock. Zero recent sales alone does not prove the item is permanently unsold.
Receiver need is the larger of learned seven-day shortage and reorder quantity,
less pending receipt and final planned allocation quantities. These reservations
affect suggested need only, never actual stock totals. Non-formulary order text,
ambiguous branch rows, invalid units and mismatched source balances are excluded.

Latest Daily Order run must be the ledger day or the following morning; older or
future runs do not generate plans. Suggestions match order units and inventory
branch groups, rank receivers by cover then demand, and consume each donor's
surplus at most once. Pending planning, expiration/batch suitability and existing
transfer reservations still require review before physical execution.

The panel names donor and receiver branches, suggests Qty, shows donor balance
after the complete plan, explains the reason, and lists branch needs/extras and
excluded rows by name. The reported extra total includes matched source rows
that failed validation, while safe extra and transfer totals exclude them. Excel
export decorates authoritative group 71 names before worker processing. No bulk
loading limits are modified; the additional request is product metadata.

Live ACCU-CHEK case on 23 Oct: Daily Order declares MODERN extra 1 and YAHAR MAIN
extra 2. The matching evidence supports a provisional suggestion MODERN → ASHAREJ
1 Qty. YAHAR MAIN has Daily Order stock 3 versus physical ledger 4, so its extra
is reported but not spent. The discrepancy is shown rather than silently dropping
it or blocking the entire product analysis. All suggestions require human review.

The shared product dialog used by Overview, MRN Overview and Near Expiry loads
`get_stock_network_sales_evidence` only when the user first opens the collapsed
“Sales & stock check” section. All three pages start with this section closed.
Closing and reopening it in the same product dialog reuses the loaded result;
“Check again” explicitly reloads it. The panel
shows a practical result, evidence, suggested action, actual versus expected net
Qty, demand-weighted branch coverage risk, and the latest approved physical STORE
MRN. Original STORE gap reconstruction is retained under “Why this result?”.
The previous fallback label `History incomplete` is now `Review supply`; it is
never relabelled Healthy simply because the user does not want a history warning.

## Evidence and scope

- Active authoritative `branches` identities, including group 71. Raw identities
  are used for matching. The shared registry decorates UI/export labels, and
  labels refresh when metadata arrives. No planned reorder quantity is on-hand.
- Current `stk_ledger`, January opening `stk_ledger_history`, complete committed
  archive periods and non-overlapping rolling movements. NULL company in the
  legacy rolling APG source is normalized only in that source.
- A product omitted from a branch's current report is treated as an estimated
  zero only if that branch has a current report and no conflicting product row.
  Missing branch reports remain unknown. `current_assumed_zero` preserves origin.
  Missing opening rows use the agreed zero assumption only when a valid branch
  opening report exists. Malformed or duplicate product opening rows block audit.
- Branch history must reconcile exactly and remain nonnegative before it can
  support stocked-day learning. A mismatch in STORE does not suppress independent
  branch evidence. Historical shortage is never proved by sales alone.
- Latest MRN sums all approved physical STORE rows on the latest receipt day,
  rather than only the latest transaction in the older movement archive. An
  unposted MRN is shown separately, with a warning; it is not added to stock.
- The analysis cutoff is the earlier of global sales date, stock date and Dubai
  yesterday. Mismatched stock and sales dates prevent availability attribution.
  The import sources do not certify intraday shelf availability or sales upload
  completeness; the UI avoids causal certainty and asks for checks accordingly.

## Learner and validation

`StockBranchForecast` is a reproducible statistical learner, not a language model
or a supervised cause classifier. It compares expanding mean, recent 14-day mean
and a weekday model shrunk toward the branch mean. It fits each branch separately.
When reconciled stock history has at least 21 stocked observations and three
positive-selling days, only fully stocked, non-adjustment days are training inputs.
Otherwise a clearly identified observed-sales estimate is used. This fallback can
underestimate unserved demand and cannot establish that demand itself weakened.

On a 45-day window, the last three days are prediction targets. Methods are
selected with rolling-origin errors on days 16–10 before the cutoff, with earlier
days only in each fit. A more complex method needs at least 2% improvement.
The selected method is evaluated on the next seven days, not used for selection.
Final fits use eligible observations ending before the three target days. Sparse
validation falls back to the mean and a conservative error allowance. Changing
target-day sales cannot change the selected method, forecast or validation error.

An anomaly requires expected 3-day Qty >= 3, observed Qty below 65% of expected,
and a gap larger than both 3 Qty and the summed branch validation error allowance.
This allowance is not a calibrated confidence interval. Demand-share percentages
are weights, not probabilities. No forecast-accuracy percentage is advertised.

The explanatory decision layer is explicit policy, separate from the learner:

| Evidence | Result |
| --- | --- |
| Selling branches short, STORE has >=7 days of network demand | Distribution needed |
| Significant decline and audited availability deteriorated | Likely availability shortage |
| Network cover <7 days and material branch shortfall | Limited supply |
| >=35% expected demand in branches with <3 days cover | Branch stock shortage |
| Net decline accounted for substantially by returns, gross sales sustained | Returns reduced net sales |
| Decline with >=80% audited stocked-day support and sustained availability | Demand slowing |
| Decline without sufficient attribution evidence | Sales declining |
| Empty STORE, branch cover sufficient | Distributed to branches |
| Stable sales with insufficient audited demand support | Sales stable |
| Adequate evidence and no material risk detected | Healthy |

3/7-day thresholds and evidence-share gates are business policy, not fitted
parameters. These observations identify likely contributors, not causal proof.
Several factors may coexist; the headline prioritizes an actionable risk and
retains the evidence table. Insurance Basic/Thiqa/Other, Cash and Online comparisons
reuse the existing daily chart data only when cutoffs agree. They are descriptive
daily-rate comparisons, not separate causal predictions.

Seasonality across years, promotions, prices, substitutions and competitor effects
are not learned from the 45-day transaction window. Monthly historical STORE
analysis still provides longer-term context separately. This release does not
claim full lost-demand reconstruction, ML classification of causes, or automatic
learning from human review labels. Those need longer aligned daily observations
and reviewed labels before accuracy can be evaluated honestly.

## Performance, access, cache and exports

Evidence is aggregated per product through existing branch/item indexes; no bulk
register scan or 5,000-row loading configuration is changed. The RPC is read-only.
A private security-definer collector explicitly checks Inventory/View access; the
public entry point is an invoker with anon/PUBLIC revoked. No raw-table grants are
expanded. Existing security advisor findings are unchanged.

The client caches at most 32 analyses per Supabase client for two minutes, coalesces
requests, rejects in-flight account changes and clears on token changes. Refresh
analysis bypasses saved results. Changes during that two-minute freshness window
may require explicit refresh. Analysis errors never fail product detail loading.
Excel uses existing styled/bordered export helpers. Branch labels are decorated
before the worker boundary; export is blocked while identity metadata is missing.

Migrations:
- `20261023111043_stock_network_sales_diagnosis.sql`
- `20261023111930_stock_network_evidence_snapshot_alignment.sql`

Validation: SQL/WASM fixtures exercise role denial, View read access, group 71,
archive/rolling deduplication, full MRN day sums, inferred current zero, malformed
opening rejection and reconciliation failures. Flutter domain/widget tests cover
cause separation, distribution, weighted branch risks, returns, prediction leakage,
weekday selection, unknown/stale stock, pending MRN, and 1440/540px async branch
labels. 103 functional Stock Management tests passed, excluding the previously
known unrelated desktop golden discrepancy. Static analysis reported no findings.
Production MOUNJARO evidence query measured approximately 163 ms server execution
on the tested warm-cache run; this excludes network and is not a latency guarantee.

MOUNJARO 16-01-07790 audit through 22 Oct 2026: latest approved STORE MRN 50 Qty
on 22 Oct, not yet present in the archived movements; reported physical branch
stock 26 Qty; model suggests uneven branch cover. Only about 22% of expected sales
has sufficient audited stocked-day training, so receipt cover is explicitly an
observed-sales equivalent, not proof it meets all latent demand. Earlier claims
that 3 Oct / 6 Qty was the latest supplier receipt came from the older archive
alone and are superseded by the receipt-table check.
