# Rev 4 audit of the M1 retune plan

Date: 2026-09-19  
Scope: strict re-audit of the four rev-3 blockers, independent numeric
reconstruction, and adversarial review of new rev-4 material  
Verdict: **not fit to hand to an implementer.**

## 1. Status of the four rev-3 blocking items

1. **Complete passage rule — CLOSED.** Rev 4 freezes the operative rule:
   `buffer_weeks = 1`, two consecutive qualifying origins, then latch forever.
   That is enough to replace the previously deferred rule. The implementation
   should still state that a missing/non-finite upper bound breaks persistence
   and that “consecutive” means consecutive distinct weekly origins, not two
   horizon rows, but these are local contract details rather than a missing
   design choice.

2. **Finalize peak truths and recompute both anchors — NOT CLOSED.** The forecast
   anchor reproduces, but the peak truths and `peak_incumbent` silently use the
   source CSV's rounded `fluAPercentPositive / 100` rather than canonical
   positivity `pos_flua / test_flu`. The plan never declares this change of
   measurement field. Under canonical `y/N`, five displayed truths do not
   reproduce and the peak anchor is 0.2194, not 0.2185. The existing timing-v2
   API also does not store or score these decimal truths, contrary to the “no
   new machinery” claim.

3. **Non-rewarding failed-row contribution and correct denominator — NOT
   CLOSED.** `max(persistence error, surviving-row cell MAE)` is not circular if
   the cell MAE is explicitly computed first from successful rows, but it is
   still endogenous and gameable: selectively failing on a row whose candidate
   error would exceed both quantities lowers the score, and doing so also lowers
   the surviving-row MAE used to penalize the failure. The denominator is also
   internally inconsistent: after removing 50 structural rows, the incumbent
   rate is 41/676 = 6.07%, not 41/726 = 5.65%.

4. **Deterministic forecast-side Gate B and unlabelled bimodality review — NOT
   CLOSED.** The 85% bimodality trigger is now deterministic. Gate B is not:
   “a season contributing 40% of between-spec variance” has no specified
   decomposition (the variance of a mean contains cross-season covariance),
   “the median pilot spec” has no declared ordering, and the effective-weight
   check says “distributed” without a pass threshold. Since “any check fails”
   stops the sweep, these are executable gates with undefined outcomes.

## 2. Independent numeric verification

I reconstructed the figures from the frozen
`m2_tuning.rds$m1_train_preds` (726 rows) and
`flu_testing_data_orvt_20260916.csv`, rather than copying the plan's summaries.

### Peak truth and `peak_incumbent`

**Does not reproduce as written.** With canonical positivity
`p = pos_flua / test_flu`, three-point interpolation gives:

| season | Rev 4 | canonical `y/N` |
|---|---:|---:|
| 2017-18 | 32.167 | 32.155 |
| 2018-19 | 31.052 | 31.051 |
| 2022-23 | 21.015 | 21.020 |
| 2023-24 | 25.903 | 25.902 |
| 2024-25 | 32.083 | 32.049 |

The other six rows agree at the displayed precision. All eleven Rev 4 values
reproduce if, and only if, interpolation is instead run on the CSV's rounded
one-decimal percentage field, `fluAPercentPositive / 100`. For example,
2024-25 uses rounded values 23.1%, 23.8%, 23.3%, producing 32.083; the count
ratio values produce 23.132%, 23.847%, 23.261%, producing 32.049.

The same distinction moves the anchor:

- rounded reported percentages: `peak_incumbent = 0.2185196839`, which rounds
  to Rev 4's **0.2185**, and every displayed per-season `S_s` reproduces;
- canonical `y/N`: `peak_incumbent = 0.2194073525`, or **0.2194**.

The numerical difference is small, but this is a frozen truth definition and
anchor. The source field and rounding are therefore not an innocuous display
choice. Rev 4 repeats the exact stale-definition class of error it says it has
closed.

There is a second implementation mismatch. `timing_labels_v2` accepts one or
two integer inputs, but it does not compute or preserve the proposed decimal
truth. A singleton is expanded to `(w-1, w)`
(`PAGe/R/timing_labels_v2.R:24-32`); finalization selects the higher observed
week as an integer (`PAGe/R/timing_workflow_v2.R:78-92`); and
`score_peak_timing_v2()` scores that integer observed week
(`PAGe/R/timing_pipeline_v2.R:316-333`). Thus §1.1's “no API change” and “no new
machinery” claims are false even before choosing the positivity field.

### Forecast anchor

**Reproduces.** Complete-case raw M1 errors give:

- season/horizon-balanced MAE = `9.2530443271` pp;
- pooled MAE = `9.3472831166` pp;
- 635 finite M1 forecasts.

Under the natural non-circular reading of Rev 4's failure rule—compute each
cell's MAE from successful rows first, then impute failures—all 41 persistence
errors are below their corresponding successful-row cell MAE. Every penalty is
therefore exactly that cell mean, so adding the failed rows leaves each cell
mean, and hence the **9.253 pp** anchor, unchanged. The number is right; the
penalty's incentive properties are not.

### Lead-time table

**Reproduces exactly.** Against the Rev 4 rounded-field truths, the five buckets
are:

| lead | correct / origins | within 1 week |
|---|---:|---:|
| 1-2 | 3/22 | 13.6% |
| 3-4 | 4/22 | 18.2% |
| 5-6 | 5/21 | 23.8% |
| 7-8 | 2/13 | 15.4% |
| >8 | 0/12 | 0% |

The same bucket counts happen also to hold under canonical `y/N`; none of the
small truth shifts crosses a one-week classification boundary.

### Structural versus spec-caused failures

**The 50/41 split reproduces exactly:** 36 `NA/NaN/Inf in 'y'` plus 14
`out_of_season` rows are structural; 22 `alignment_prediction_missing` plus 19
`aligned_week_outside_template_support` rows are spec-caused. The associated
5.6% claim does not follow the plan's own denominator rule: structural rows are
said to leave the key set, so the applicable rate is 41/676 = **6.07%**.

## 3. Adversarial audit of new Rev 4 material

### §1.1 label protocol and the 85% trigger

Human choice of the epidemic wave is appropriate. A local parabola is also a
reasonable sub-week estimator for a labelled, isolated local maximum. The
two-week rule is not implementable as written, however: it does not say which
of the two labelled weeks is `w_0`, and the fallback preconditions are stated
only for the global argmax, not for a human-selected rival wave or plateau.

Clamping the unconstrained vertex to the labelled span is mathematically a
projection and is value-continuous; it does **not** create a jump
discontinuity. It does create a kink and a pile-up at the endpoints, and it can
hide that the three-point fit placed its maximum outside the human-declared
plateau. The current 2024-25 result illustrates the weakness: a two-week
“32+33 plateau” becomes 32.083, very near the first edge, solely from one
three-point fit. For a genuine two-week plateau, either score distance to the
labelled interval or use a predeclared point such as the midpoint. If a
parabola is retained, freeze the centre-selection rule, fitting window,
preconditions, and out-of-span reason code.

The 85% trigger is a deterministic but empirically chosen cliff. The observed
rival ratios include 83.9% and 88.4%, so almost indistinguishable seasons fall
on opposite sides. “60% flags ten seasons” does not justify 85% rather than
80%, 83%, or 90%. This arbitrariness is harmless only if the trigger is triage
and **every** closed season is human-confirmed anyway—which §1.1 already says.
If it decides whether an unlabelled season may use the fallback, it materially
changes truth assignment and needs either a sensitivity band/automatic review
near the threshold or, more simply at n=11, mandatory human review for every
season. As written, the universal human-first rule makes the 85% branch
redundant, while the fallback language implies that it is not universal.

### §1.4 failed-row penalty

It can still be gamed. Consider a cell with successful errors 0 and 100 and a
persistence error of 10 on the second key. Emitting both gives MAE 50. Failing
on the hard key makes the surviving-row MAE 0 and the failed-row penalty 10,
giving MAE 5. The `max()` prevents a failed row from looking better than the
spec's **surviving average**; it does not prevent failure from looking better
than the forecast the spec would have emitted.

This is not algebraically circular if “own cell MAE” explicitly means a
pre-penalty complete-case statistic. It is circular if it means the final cell
MAE. Rev 4 should say which. Even under the first reading it is endogenous: a
spec changes its own penalty by changing which rows survive.

Use a penalty independent of the candidate's surviving errors—for example a
frozen per-cell incumbent/worst-acceptable loss plus a failure surcharge—and
rank coverage separately before accuracy. At minimum require no worse coverage
than the incumbent globally **and within every season/horizon**, so 10% of the
whole ledger cannot be concentrated in one hard season.

### Raising disqualification from 5% to 10%

Keeping the incumbent eligible is a legitimate design requirement; calling any
threshold below its rate “badly calibrated” is not. The revision observes a
6.07% eligible-denominator failure rate, then rounds the ceiling all the way to
10%, nearly doubling permitted failure without an operational rationale. A
global 10% cap would allow roughly 67 failed eligible rows and could allow a
candidate to abandon most or all of a hard season while remaining eligible.

A defensible rule is baseline-relative and stratified: candidate failure rate
no greater than the incumbent's frozen rate plus a small declared tolerance,
an absolute ceiling, and per-season/per-horizon minimum coverage. The incumbent
itself can be retained as a comparator even if it fails a deployment-quality
gate; anchors do not logically require eligibility.

### §1.6 frozen passage rule

The rule is coherent as a conservative sequential state machine. Latching is
appropriate for a one-way operational switch; `buffer = 1` and `persist2`
directly address the observed one-origin oscillations. I independently applied
the combined rule—not the separately reported Task B variants—to distinct
weekly origins. Against Rev 4's truths it fires early in **2/11** seasons, with
worst early firing **1.052 weeks**, and thus meets both stated safety limits on
the incumbent. Latching does not change first-fire timing.

The missing guardrail is latency. The combined rule's median lag is +2.10
weeks, with a worst lag of +7.72 weeks. A candidate may therefore satisfy both
hard constraints by almost never switching in time to obtain the post-peak
forecast benefit. Freeze a late-fire/never-fire limit or, preferably, evaluate
the routed forecast policy's downstream MAE/NLL so safety and lost benefit are
measured together.

## 4. New defects introduced or exposed in Rev 4

- The peak labels and anchor silently use rounded reported percentages rather
  than canonical `y/N`; five displayed truths and the 0.2185 anchor fail under
  the canonical field.
- “No API change/new machinery” is false: the existing timing-v2 path resolves
  and scores an integer observed week, not the proposed decimal parabolic truth.
- The two-week parabolic rule omits the centre-selection and guard rules.
- The failed-row rule remains selection-gameable, and its “own MAE” ordering is
  not explicit.
- The failure-rate denominator contradicts the structural-row exclusion.
- Gate B introduced undefined variance-attribution and median-spec tests, plus
  a qualitative effective-weight gate with no cutoff.
- The frozen passage constraints regulate earliness but permit arbitrarily late
  or never firing, which can nullify the intended routing benefit.
- The document still contains the stale statement that bounded incumbent score
  is 0.1980 (§1.2), despite later replacing the bounded anchor with 0.2185.

## 5. SUGGEST — highest-value improvements beyond defect repair

1. **Decouple alignment from probability forecasting before spending the full
   M1 sweep.** M1's scientific value may be phase/peak alignment; forcing its
   probability forecast into M2 at coefficient 1 creates the documented unit-
   gain failure. Run a preregistered baseline in which M1 enters as a learned
   coefficient/covariate (or the offset coefficient is freed) and compare it
   with the proposed M1 retune. This is the most direct test of whether the
   expensive retune is solving the right layer.

2. **Use interval truth for adjudicated plateaus.** A `32+33` label naturally
   means `[32,33]`; score zero distance inside the interval and distance to the
   nearest edge outside it. That preserves the human claim instead of inventing
   an unstable decimal point. Retain a parabolic point only as descriptive
   provenance.

3. **Make coverage lexicographically prior to accuracy.** First require common,
   stratified coverage at least as good as the incumbent; then compare peak and
   forecast utility on the fixed expected keys with a candidate-independent
   failure loss. This removes the strongest gaming channel instead of trying to
   price it with the candidate's own surviving mean.

4. **Select the passage policy on end-to-end decision loss.** For each frozen
   gate, replay the actual routed M1/post-peak forecast and report early-switch
   harm, late-switch opportunity loss, MAE and NLL by season. Timing error alone
   cannot tell whether `buffer1 + persist2` is the best operational trade.

5. **Add a hard worst-season degradation limit to selection.** Rev 4 reports
   worst-season effects but does not constrain them. With only 11 seasons and
   pronounced heterogeneity, require a fixed maximum degradation versus the
   incumbent in forecast MAE/NLL and report how often the nested selector picks
   each spec. This is more protective than another aggregate sensitivity plot.

## 6. Verdict and blocking items only

**No. Rev 4 is not fit to hand to an implementer.** Blocking items:

1. Choose and declare the authoritative positivity field, recompute/freeze all
   decimal truths and `peak_incumbent` from it, and provide an artifact/API path
   that actually stores and scores the decimal truth.
2. Make the one- and two-week label-to-decimal algorithm deterministic,
   including the two-week centre/window, guards, and out-of-span behavior; or
   adopt interval-valued plateau truth.
3. Replace the endogenous failed-row penalty with a candidate-independent,
   non-rewarding rule and fix the eligible denominator and stratified coverage
   constraints.
4. Fully define Gate B's variance contribution, median-spec ordering, and
   effective-weight pass threshold.

