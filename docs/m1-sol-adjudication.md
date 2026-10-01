# Adjudication: M1 peak regression and rev 5

Date: 2026-09-19  
Role: adjudicating reviewer  
Decision: **cause not identified; rev 5 is not executable as written**

## Bottom line

The regression is real, but the evidence does not identify its cause. On the
10 shared seasons and rev 5's own interval truth, the matched-origin comparison
is **0.6350 weeks for v16 versus 2.7314 weeks for current**, a **2.0964-week
gap**; v16 is better in 9 of 10 seasons. The packet's two-interval convention
gives the essentially identical 0.6399 versus 2.7364 result. Neither comparison
supports a causal nomination.

The strongest live candidate is B (`k_ref`/`slope_weight`), because it is the
only candidate with a controlled, nonzero movement of final peak estimates
under current code. That result covers only two selected seasons and moves one
toward truth and the other away from truth. It cannot be assigned any measured
share of the 10-season gap. C remains a genuine composite code/pipeline change,
but only its final rounding component has been isolated, and that component
worsens rather than repairs current MAE. A's proposed reduction is not new: the
same weighted mean and weighted quantiles produced v16. D changes passage state
only and carries exactly zero of the peak-location accuracy gap.

Accordingly, the causal verdict is **null**, not “B” or “C”. Confidence that
the regression exists is high; confidence in any causal allocation among A, B,
and C is low.

## 1. Ranked adjudication of A--D

The ranking below is by evidence for carrying any of the 2.096-week gap, not by
plausibility.

### 1. B — `k_ref = 25 -> 30`, `slope_weight = 8 -> 16`

**Adjudication:** live, highest-ranked, but not established as the cause.  
**Measured share of the aggregate gap:** unknown.  
**Confidence:** high that D-32's prior refutation is invalid; low that B
explains the regression.

The old 20-spec surface cannot bound behavior under current code. On current
code and the substituted September data, the controlled 25/8 -> 30/16 switch
moved the final estimate by two weeks in 2013-14 (31 -> 29) and one week in
2019-20 (28 -> 27), with maximum origin-level movements of three and one weeks.
Those are large enough to invalidate the claim that this pin can only matter by
0.050 or at most 0.293 weeks.

They do not establish direction. Against rev 5 truth, the 2013-14 movement
reduces error by two weeks, while the 2019-20 movement increases error by about
one week. Two deliberately probed seasons cannot estimate a 10-season mean or
an interaction with timing mode. Rev 5 must withdraw both “D-32 is refuted” and
“the cause is not a hyperparameter setting.”

### 2. C — `anchorWeek = 19 -> 20.5` and legacy integer -> fractional timing

**Adjudication:** live as a composite change; the visible output quantisation
is not the cause.  
**Measured share of the aggregate gap:** the isolated final-rounding component
accounts for **none**; the internal timing/anchor component is unknown.  
**Confidence:** high for the rounding bound; low for the unsplit composite.

Rounding the current model's final estimates to integers increases its
10-season rev-5-truth MAE from **2.7314 to 2.8224 weeks** (+0.0910), rather than
moving it toward v16's 0.6350. Rounding also leaves the large trajectory jumps:
the share above five weeks remains 2.1%, and the maximum changes only from 8.38
to 8 weeks. Integer output alone therefore does not explain v16's stability.

The full timing change is larger than output rounding. Legacy mode rounds
template-coordinate evaluations internally, while fractional mode carries
fractional ignition and reference coordinates. `anchorWeek` also participates
in fitting, even though a pure, consistently applied coordinate translation
would cancel in `peak_weekF = t_peak - anchorWeek + iWeek_hat`. Those effects
have not been separated on common data. M0 ignition matched v16 exactly in the
two probed seasons, which rules out an M0 shift there but not all of C over all
10 seasons.

### 3. A — multi-template peak derivation

**Adjudication:** not a newly introduced structural change; possible
amplification site, not an identified cause.  
**Measured share of the aggregate gap:** zero attributable to adoption of the
weighted-mean reduction; any interaction share is unknown.  
**Confidence:** high that the reduction and quantile construction are shared;
medium on their interaction with B/C and data vintage.

Git history places the weighted mean of per-template peaks and weighted
quantile bounds in the original multi-template implementation (commit
`47bcdf0`, 2026-03-28), before the v16 cache. The v16 artifact independently
confirms the same construction: its weighted upper quantile is below its
weighted-mean point estimate in 96/334 rows. Thus the answer to “is the
weighted-mean-of-peaks reduction new?” is **no**.

The current zero-width-bound count (132/690 versus 0/334 in v16) is a real
state-gating defect, but those bounds do not enter the point estimate. The
median-width evidence is only 0.709 versus 0.436 weeks with overlapping
distributions, and v16's bounds already fail to bracket their point estimate.
This can contribute to passage instability; it does not explain the final
peak-location regression. Weight transfer among templates is where current
jitter appears, but the evidence has not shown whether B, C, code outside the
reduction, or data vintage changed that transfer.

### 4. D — `buffer_weeks = 5 -> 0`

**Adjudication:** confirmed state-machine defect; not an accuracy cause.  
**Measured share of the peak-location gap:** exactly **zero**.  
**Confidence:** high.

`buffer_weeks` is used only after `peak_weekF` and its upper bound have been
computed. It cannot change the peak estimate. In the isolated counterfactual,
restoring buffering reduces stateless TRUE->FALSE reversions from 34 to 18 and
plateaus by buffer 3; it does not approach v16's one reversion. D should be
fixed for reproducible state behavior, but it must not be credited with any of
the 2.096-week accuracy recovery, and `buffer = 5` alone must not be presented
as recovering the v16 state machine.

## 2. The code/data-vintage confounder

**It can be broken. Confidence: high.** The deleted v16 CSV is not necessary
for the 10 shared seasons. Every `ref_list` entry in `align_multi_cache.rds`
contains `ref$dat` for the other nine seasons, including calendar keys and the
original `y` and `N` fields. Their union has:

- 4,689 embedded fold rows and 521 unique `season x weekF` keys;
- 52 weeks for nine seasons and 53 for 2014-15;
- each season present in exactly nine fold references; and
- zero disagreements across repeated keys in `y`, `N`, or date.

This is a ninefold cross-check of a recoverable, exact 10-season v16 input
snapshot. It contains the authoritative count numerator and denominator, so it
is stronger than reconstructing positivity from `forecast_df`.

The separating experiment is a fixed-spec crossed replay, not a sweep:

1. Deduplicate the embedded `ref$dat` union after asserting the counts above;
   hash the reconstructed input and keep it private.
2. Identify and hash the exact source tree that produced the cache. The absent
   `t_peak_median` narrows it to before `00ab9b4`, but that is not by itself an
   exact provenance claim.
3. First reproduce v16 row-for-row on the reconstructed v16 input. Do not
   proceed from a source tree that cannot reproduce it.
4. With configuration, legacy timing, fold declarations, and origin schedule
   fixed, run the 2 x 2 cross: v16 code/current code by v16 data/September data.
5. On the v16 data, switch one factor at a time: code, timing/anchor, then
   25/8 -> 30/16. Compare the full origin trajectory and fallback identity, not
   only final MAE.

That design estimates code, data, B, and C effects and exposes interactions.
The current reproduction's failure cannot be called a code effect because it
changed both code and data.

## 3. Required corrections to rev 5

### 3.1 The five packet corrections

1. **MAE-side season scope — BLOCKS Gate V and Stage 1. Confidence: high.**
   Replace the 10-row table's `0.766 / 2.912` headline. Under rev 5's own truth
   and the 10 shared seasons, the frozen pair is **0.6350 / 2.7314**, not a
   mixture of 10- and 11-season means. The gap is **2.0964 weeks** and the ratio
   is 4.30x. If the packet's two-interval convention is retained instead, label
   it separately as **0.6399 / 2.7364**. Gate V's MAE ceiling must use the same
   declared convention as its table.

2. **Truth convention and `peak_incumbent` — BLOCKS the objective and Gate V.
   Confidence: high.** Remove all `0.766 / 2.912` constants from interval-truth
   claims. Unfreeze `peak_incumbent = 0.2155`; recompute it from the
   provenance-bound ledger under the final interval rule and declared season
   scope. The plan must also define lead/window weighting for an interval-valued
   peak before that score is executable. Use a separate 10-season matched
   baseline for Gate V and, if desired, an explicitly labelled 11-season
   anchor for the development objective; do not substitute one for the other.

3. **Terminal-origin mismatch — BLOCKS an executable comparison, though it
   does not overturn the observed regression. Confidence: high.** Do not call
   current's last non-NA estimate the “last origin.” It occurs at weeks 42--51,
   whereas v16 extends to weeks 52--53. Freeze a common origin key set. For the
   historical diagnostic, the latest common forecast-available origin per
   season yields the same **0.6350 / 2.7314** and 9/10 result because v16 is
   nearly static. For a prospective gate, use a fixed terminal schedule and
   treat a spec-caused missing estimate under the plan's missingness rule; do
   not move the endpoint earlier until a forecast appears.

4. **`iWeek_true` semantics — BLOCKS Gate A/Stage 1 provenance, not the
   regression conclusion. Confidence: high.** Rename or explicitly map the v16
   field as `manual_label_legacy = canonical_label - 1`; it is an intentional
   coordinate offset, not independently observed truth. It must not validate
   M0 or enter a truth table. Record `iWeek_hat`, canonical label, legacy
   offset, timing mode, and coordinate transform as distinct fields.

5. **2013-14 fallback dependence — material correction, not a standalone
   rejection of the v16 baseline. Confidence: high.** Seventeen of 33 v16
   origins (51.5%) use `delta_unstable_profile`; all are late-season and still
   return finite estimates. Rev 5 must stop treating 2013-14 as clean evidence
   about the primary alignment path. Gate A and the bisection must reproduce
   and compare `fallback_reason` row-for-row and report results stratified by
   fallback. The issue is 24/334 rows overall and v16 still wins 9/10 seasons,
   so it does not by itself erase v16 as the reference.

### 3.2 Other claims that must change

- Withdraw “D-32 is refuted” and the derived statement that the cause must be
  code rather than configuration. B is live but unproven.
- Replace Stage 1's “if current code cannot reproduce v16, the difference is
  in code” rule with the crossed replay in Section 2.
- Remove the `tau = 6` saturation hypothesis and its preregistered expectation;
  that column is an M2 time-since-peak feature, not M1 shift.
- Do not list weighted-mean multi-template peak derivation as a new candidate
  change. It is shared with v16. Investigate changed inputs to its weights and
  timing coordinates instead.
- Update the state evidence to the common stateless definition: v16 has one
  TRUE->FALSE event; current has 34 events across 8/11 seasons. Keep this
  separate from the proposed latched rule, under which reversions are impossible
  by construction.
- Reconcile the frozen passage policy with the buffer experiment. Buffering is
  a state-policy choice, not a peak-accuracy repair, and buffer 5 alone leaves
  18 reversions in the isolated current trajectory.
- Fix rev 5's internal failed-row contradiction. Section 1.4 specifies a
  candidate-independent loss, but the signed constants table still freezes
  `max(persistence error, spec's own cell MAE)`, the rejected gameable rule.
  The signed table must match Section 1.4 and specify the fixed surcharge.

Until these changes are made, rev 5 should not be handed to an implementer and
no sweep should start.

## 4. Minimal next action and owner

**Action:** one fixed-spec, 10-season crossed reproduction using the recovered
v16 input; no tuning and no production change. The first acceptance check is
row-level reproduction of `align_multi_cache.rds` under the historical source
tree, including peak point/bounds, passage state, fallback reason, and fold
membership. Only after that passes should the 2 x 2 code/data cross and the
one-factor B/C switches run.

**Owner:** the reproduction worker who produced `docs/m1-v16-repro-findings.md`
should run it, because that worker already has the bounded replay harness. Ming
should review the preregistered factor order and outputs but should not revise
the causal hypothesis during execution; the adjudicating reviewer should sign
off on the row-level reproduction before the cross proceeds.

**Success criterion:** either (a) one isolated factor reproduces most of the
2.096-week matched-origin gap across the 10 seasons, with consistent
per-season/trajectory evidence, or (b) the result remains distributed or
interactive and the recorded verdict stays null. Outcome (b) is a valid and
preferred result over another unsupported nomination.
