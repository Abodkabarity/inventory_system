# Stock availability evidence and monthly chart context

Overview, MRN Overview and Near Expiry share a STORE-history column, a product
detail panel and Excel evidence fields. Raw stock, orders, sales, receipt totals,
expiry grouping, review notes and existing status calculations are unchanged.

The learned demand layer fits and evaluates a per-product statistical estimate
from historical monthly sales. It estimates STORE supply capacity, with an
explicit Estimated label. It does not establish a causal reason for reduced
sales, network-wide stockouts or lost sales. STORE transfers are not customer
sales. Branch availability must be independently verified before retail demand
is adjusted for stockouts.

## Evidence and classifications

- Use exactly one explicit STORE opening row dated January 1, 2026, with matching
  single-day report dates, company and a present raw branch. A missing raw row
  remains UNKNOWN in the source. Per the requested business rule, the analysis
  may assume zero **only** for an omitted item when a valid STORE opening report
  exists and there is no malformed raw opening row for that item. Such results
  are **Estimated**, never Verified. Duplicate, null or invalid rows still block
  classification. The raw opening table is never filled or rewritten.
- Require contiguous completed APG movement periods whose committed row count
  matches their expected count. Archived coverage stops at that confirmed cutoff.
  Recent rolling evidence can extend it provisionally through the earlier of its
  maximum date, the ledger day and yesterday in Dubai, only when rolling dates
  overlap the archive boundary. Never overlap or double count sources.
- Treat the opening as the closing balance on January 1. Nonzero movements on
  that date block classification until the opening boundary is settled.
- Apply signed movements once. Negative balances, inconsistent signs/modes,
  company mismatches and missing/nonunique current STORE balances block claims.
- Reconcile the reconstructed balance against current raw ledger Actual Qty.
  If the ledger date is later than the archive cutoff, bridge only those later
  dates from the rolling statement. The rolling source must reach that date;
  an inconsistent bridge blocks classification, not silently resets stock.
  The ordinary APG rolling uploader deliberately stores NULL company; this known
  source convention is normalized to APG only for rolling evidence, while
  explicit other companies still fail and archived company remains mandatory.
- A full empty day has zero opening and closing system balance without incoming
  stock or adjustments. Receipt/depletion/adjustment days are partial. Same-day
  incoming plus outgoing with a zero close interrupts a continuous empty spell.
  Daily data never invents intraday order or proves a physical count.
- A return requires prior observed availability (or earlier annual sales), a
  positive closing balance after zero, and matching positive approved STORE MRN
  Qty and statement MRN Qty on that day. Count the intervening full empty days.
  Adjustments and internal transfers alone cannot establish an MRN return.
  Rolling rows lack transaction types: their full positive quantity must match
  the approved physical STORE receipt sum before linking a return. If a receipt
  arrives before **any** same-item/date rolling row, it may provide provisional
  incoming evidence outside the archive only. All receipts on that date are
  summed, and the reconstructed endpoint must exactly match the current ledger.
  Virtual MRNs cannot trigger a physical STORE return. When the archive catches
  up, provisional receipts disappear from reconstruction and are counted once.
- The register highlights **Back in STORE** only for the latest recovery after
  at least 30 full days, returned within the last 30 calendar days, with positive
  current STORE stock and reconciled history. Older/shorter returns stay factual
  context in the detail panel. An initially zero opening can support an
  **at least** duration, never an invented earlier start date.
- History issues show **History incomplete**. A positive current ledger after a
  still-zero archived balance shows **Receipt needs checking** until history can
  confirm its date. Contradictory histories suppress durations/dates in Excel and
  UI; reconciled estimates show their opening/provisional basis explicitly.
  Pre-introduction empty periods are unknown until prior sales or positive stock
  establishes the product; they never become invented stockout durations.

Monthly comparisons show factual all-source net sales, prior-year same-month
sales, STORE stocked/empty/partial days. These scopes are labelled separately.
No sales/day estimate is produced by dividing retail sales by STORE-stock days.
Sales can be newer than the movement cutoff; both dates are retained separately.
The shared monthly chart in all three pages uses a pale rose month band with an
OUT label and the number of full empty STORE days when a month has at least 7.
An asterisk/Estimated legend qualifies inferred evidence. Hover/tap gives stocked,
empty and partial days. Historical bands remain when stock is available again;
zero/low sales alone and 2025 months without stock history receive no bands.
The chart's Excel export includes every plotted month, even absent sales rows,
plus available evidence days and basis, without changing sales amounts.

## Refresh, caching and access

`stock_management_private.refresh_supply_insights()` reads source tables without
modifying them, calculates the entire tracked catalog/MRN/durable-expiry union,
and atomically publishes one complete generation. An empty/incomplete build or
changed source version rolls back; readers retain the prior complete result.
The source version includes import progress, baseline import time, ledger and
rolling statement import times, catalog revisions and MRN revisions. An unchanged
version is a no-op. The service-only cron runs at minutes 7/22/37/52 each hour.
Failure is retained in `stock_supply_insight_state.last_error` with its attempt
time; it does not delete the last successful generation.

Registers join only thin summaries; monthly evidence loads with product details.
All existing 5,000-row caps, duplicate/completeness checks and snapshot dates are
preserved. Catalog and workspace cache versions include the insight generation;
changing insights does not force expiry-receipt rediscovery. Private source
tables remain private. New public cache tables match the existing Inventory and read-only View SELECT policies;
only service code can rebuild them. No new raw branch names are displayed.

## Verification

- `supabase/tests/stock_supply_insights_test.cjs`: real isolated PostgreSQL,
  exact/full/minimum gaps, same-day activity, adjustments, absent baselines,
  signs/companies, MRN matching, endpoint reconciliation, all read paths,
  lightweight batches, revisions, unchanged discovery, rollback and RLS.
- `test/stock_supply_insight_test.dart`: readable filtering/export values,
  no unverified claimed gaps, separate scopes and responsive evidence panels.
- Existing Stock Management, catalog, expiry, shared-dialog and cache tests.

Next learning stage: reconstruct and reconcile retail branch availability,
validate actual sale/return transaction types, create available-day demand
observations, and compare forecasts on later held-out periods. Only a model
that beats a simple benchmark and has adequate data coverage should estimate
lost sales. Inferred opening balances must be tracked separately from measured
opening balances, and unreconciled histories remain data-quality findings.

## First production verification — 23 October 2026

- 12,524 tracked products; no missing tracked identity or duplicate output.
- 41 recent MRN-linked STORE returns after long gaps, 69 verified empty STORE
  balances, 587 verified available balances, 11,827 histories needing review.
- Findings include 8,004 missing opening balances, 2,258 unreconciled balances,
  1,425 missing/nonunique current STORE balances, 140 incomparable endpoints and
  7 negative histories. Reasons overlap; they are not additive classifications.
- Source catalog/MRN payloads, durable expiry evidence and review rows remained
  byte-for-byte unchanged during the first rebuild. No unverified gap duration
  or return date was emitted in register summaries.
- Example 16-02-08876: 278 full empty days, return 8 October, linked received Qty
  2. Overview and MRN return the same cached evidence. All 118 current expiry
  rows carry a supply review summary.
- Thin register joins serialize evidence once. Measured server execution for
  5,000 Overview rows was about 1.85s (original without the new fields 1.77s),
  MRN 1.37s, and an Overview product detail about 24ms. These are server timings,
  not network or screen-render guarantees. Repeated unchanged refresh is a no-op.
- 85 focused Flutter tests passed, static analysis of 9 changed files had no
  findings, and the isolated PostgreSQL suite passed including equal payloads
  before/after the bulk-read optimization. Security advisors had no new findings.

The large unavailable-history population is a data-quality result, not proof
of stockouts. It must be investigated before those products enter demand-model
training. This delivery does not label a rule-based calculation as trained ML.

## Return-detection update — 23 October 2026

- Rebuilt all 12,524 tracked products through 22 October; 121 recent returns,
  1,662 available and 61 empty STORE balances have reconciled estimated evidence.
  10,680 histories still require review; no mismatch was suppressed to gain coverage.
- Actual example **16-01-02070 METROLAG** has no opening row. Recorded small
  transfers interrupt earlier gaps; the latest continuous gap is **30 June
  through 21 October (114 full days)**. Approved physical STORE MRNs 106632 and
  106633 total **232** on **22 October**, exactly matching current STORE Actual
  Qty 232. Their rolling movement has not arrived yet. The result is therefore
  Back in STORE / Estimated, not a claim of uninterrupted absence all year.
- Regression coverage includes omitted vs malformed/duplicate openings, known
  legacy APG NULL company, first introduction, already-available historical gaps,
  receipt-before-statement, two MRNs on one date, virtual receipts, endpoint
  mismatch and archive catch-up without double counting.
- 88 focused Flutter functional tests passed. Added desktop/compact chart checks
  and verified estimate labels in all register exports and missing-sales months
  in chart exports. The isolated PostgreSQL suite and static analysis passed;
  security advisor finding signatures were unchanged.

## Learned demand and continuous supply interruption — 23 October 2026

The main register signal, product cards and chart distinguish two measures:

- **Recorded zero balance:** original empty/stocked/partial day counts and
  MRN-linked raw returns, preserved for audit and exports.
- **Effective supply interruption (Estimated):** insufficient STORE cover for
  historical retail demand, including small transient arrivals. It may remain
  continuous while the factual balance briefly rises above zero.

### Demand estimator

`fit_supply_demand` accepts only observed monthly records in the calendar year
before the opening date (currently 2025). Missing months are not invented as
training zeroes; net negative sales are clipped to zero for demand fitting.
At least 6 distinct observed months and 3 positive months are required. A
missing, ambiguous or nonpositive baseline does not fabricate a model result.

Candidate estimators are expanding quantity / calendar days, trailing-three-
month quantity / calendar days, and median monthly daily rate. Method selection
uses chronological one-month-ahead errors after three warmup observations,
reserving the final two historical months from selection. Each prediction uses
only preceding observations. A more complex choice must improve the selection
MAE by at least 2%; ties retain the simpler baseline. The selected method is
then evaluated, unchanged, on the last two months with walk-forward refits.
Method, candidate selection errors, reserved-month error, benchmark error,
training window and sample counts are retained in the product evidence.
Finally the chosen method is fitted to all eligible historical records for
operational use. The suspected shortage year's reduced sales cannot lower the
pre-shortage baseline. This is a small statistical estimator, not a trained
causal stockout classifier or a claim of independent future accuracy.

### Supply policy

- Entry threshold: `max(1, ceil(learned_daily_qty * 7))`.
- Recovery threshold: `max(1, ceil(learned_daily_qty * 14))`.
- A below-entry opening starts an estimated interval after the opening date.
  A later depletion starts it after that movement day.
- Once in a shortage, small arrivals do not restart the clock. Recovery needs
  a positive real incoming movement with closing stock at or above the recovery
  threshold. An inventory adjustment alone cannot certify replenishment; after
  an adjustment, a small incoming movement cannot piggyback on the adjustment
  to certify recovery. A later substantial receipt must meet the threshold.
- Reconstructed-history and current-ledger checks must pass before fitting and
  classifying supply. No new inference bypasses existing source-quality issues.
- All intervals remain in details. The newest ongoing interval takes precedence
  over an older closed interval, even if the new interval is short. The chart
  draws connected brackets only for intervals of at least 30 days. Recent
  substantial recovery is highlighted for 30 calendar days; older intervals
  remain visible historically. The opening-boundary duration is a minimum.
- Bulk rows retain only a thin latest interval/rate/threshold summary. Full
  model validation, all intervals and monthly insufficient-cover days load with
  details. Model computation happens in the existing background cache rebuild,
  not while rendering or opening a product. Existing 5,000-row loading remains.

For METROLAG, the selected historical median estimates **0.558065 Qty/day**,
with entry below 4 Qty and recovery at 8 Qty (14 days of demand). Seven small
arrivals totaling 9 Qty do not end the estimated shortage. Physical MRNs totaling
232 Qty on 22 October restore cover. The continuous interval is **2 January–21
October**, **293 days / at least 9 months 20 days**. The separate raw zero-stock
spell is still 114 days. February's raw empty days remain 18; its estimated
insufficient-supply interval covers all 28 days. The model's reserved-month
average absolute error is **7.171 Qty/month**, compared with **21.05** for the
expanding mean benchmark; this is a historical check, not a future guarantee.

The chart uses one connected pale-rose band and a duration bracket for each
long interval. Hover/tap shows the affected month's insufficient-cover days.
The evidence table and Excel exports preserve raw zero days alongside effective
interruption days, duration, meaningful return, small-arrival count/quantity,
demand estimate, recovery threshold and explicit estimated scope. A very slow
seller can legitimately recover with one unit if that covers its normal demand.

Production refresh verified all 12,524 tracked products without missing cache
rows: 638 adequate supply, 189 limited supply, 225 recently restored, 792 without
sufficient demand training history, and 10,680 requiring stock-history review.
Overview and MRN return identical METROLAG learned evidence. No unverified
history emitted an effective interval. The isolated PostgreSQL suite and 91
focused Flutter functional tests passed; static analysis of 10 files reported
zero findings, and security advisor signatures had no new findings. The existing
unrelated desktop golden comparison remains excluded from the functional run.
# Network analysis in the shared dialog

The actionable sales/branch supply panel now precedes the legacy STORE evidence.
See [stock_network_sales_analysis.md](stock_network_sales_analysis.md) for its
learner, source validation, access model, cache policy and explicit limitations.

## STORE receipt routing and missing current stock (27 October)

Every approved receipt in `mrn_apg_2026` belongs to STORE supply, including
`main virtual`, `new virtual`, other warehouse values and missing routing names.
The supply-history refresh now uses this same source rule as network analysis.
Archived movements remain authoritative for balances; their receipts are not
added again. Provisional MRNs outside the archive still require reconciliation
and are not added when a same-day rolling statement row already exists.

When the only historical validation problem is a missing current STORE row,
the detail chart can retain estimated past shortage periods with the existing
"Stock history needs checking" label. The current balance stays unknown and the
summary remains unavailable. Duplicate ledger rows, missing opening evidence,
negative balances and invalid movements still prevent this chart fallback.
Receipt return markers still require matching movement evidence. No changes
were made to 5,000-row bulk limits or branch presentation/export identities.
Virtual receipts posted as `StockTransferTo` can match the full approved MRN
quantity on the same day, as rolling statements already do. A different amount
or posting date does not certify a return marker. This association changes no
movement quantities or opening/current balances.

