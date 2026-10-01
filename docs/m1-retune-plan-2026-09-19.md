# M1 retune plan — 2026-09-19 (rev 6)

Status: **Cause of the regression is NOT identified. Stage 1 replaced by a
crossed code x data replay against a recovered v16 input snapshot. Anchors
corrected for season scope and truth convention; `peak_incumbent` UNFROZEN.**
Owner: Ming (page-59). Auditor: Jax / `gpt-5.6-sol`. Implementer: TBD; Ming reviews.

Audit trail in §6. Revs 1-3 were each rejected on audit, and rev 5 was
adjudicated **null** on cause. All rejections were correct and the defects were
the author's.

**Rev 6 withdraws three claims rev 5 asserted as settled.** D-32 is no longer
refuted; the multi-template peak derivation is not a new change; and the `tau`
saturation hypothesis was a misread column. Two of those three were the
author's errors, found by delegated workers. Treat the remaining causal
language in this document as suspicion, never conclusion.

Do not begin Stage 1 until Stage 0's Gate A and Gate B (§1.8) both pass.

## 0. Why this exists

M1 was tuned for peak-timing accuracy only. Forecast accuracy was never an
acceptance criterion. But `m1_logit` feeds M2 as a mandatory offset at
coefficient 1, so M1's forecast defects propagate into the shipped forecast at
unit gain.

- M1 forecast MAE 9.253 pp season-balanced (9.347 pooled), 8.93 pp post-peak. A plain GAM on observed
  weeks alone gets 1.34 pp post-peak and beats M1 in 10 of 11 seasons.
- 49 of 635 forecast rows exceed 40% positivity; max 97.9% against an actual of
  14.1%. Observed positivity never exceeds 36.2% in the record.
- `LAMBDA_DELTA` is 164,672.9 against a documented default of 0.20. Max `|delta|`
  is 8.6e-05 against bounds `[-0.4, 0.262]`. Dilation is mathematically
  forbidden, so `tau` absorbs all timing variation and `a` inflates when it
  cannot. Confirmed not deliberate.
- `peak_passed` fires before the true peak in 7 of 11 seasons.

### v16 is a working counterexample, and the gap is a regression

`align_multi_cache.rds` (archive `seasonal-archive-20260818`) holds the v16-era
alignment for 10 of the 11 seasons. It is genuine **leave-one-season-out**:
`n_train = 9` on every one of its 334 rows, and each `ref_list` entry's
`ref$dat` contains exactly the other nine seasons. The current run is also
LOSO, so this is a LOSO-to-LOSO comparison.

Signed final peak error at the **latest common forecast-available origin**,
under the two-interval convention:

| season | v16 err | current err | | season | v16 err | current err |
|---|---:|---:|---|---|---:|---:|
| 2012-13 | 0.00 | -1.82 | | 2018-19 | +1.95 | -3.58 |
| 2013-14 | 0.00 | **+4.60** | | 2019-20 | -1.81 | -1.40 |
| 2014-15 | +0.20 | **+4.09** | | 2022-23 | -1.02 | -2.05 |
| 2016-17 | -0.11 | +3.65 | | 2023-24 | +0.10 | +2.97 |
| 2017-18 | -1.16 | -3.06 | | 2024-25 | -0.05 | -0.50 |

**Mean absolute final peak error: v16 0.640 weeks, current 2.736 weeks** — a
**2.096-week gap**, ratio **4.28x**, v16 better in **9 of 10** seasons. Under
§1.1's full interval rule the pair is **0.6350 / 2.7314** (gap 2.0964, ratio
4.30x); that pair is the frozen reference. `loso_walkforward.qmd` records the
locked design target at Peak MAE 1.275 weeks, so v16 beat the documented spec
and the current model is more than twice as bad as it.

**Rev 5 quoted "0.766 / 2.912". Both numbers are withdrawn.** They mix a
10-season v16 mean with an **11-season** current mean, while Gate V is defined
on the 10 shared seasons; and they apply parabolic decimals to seasons §1.1
declares to be interval truth. The direction and the ~4x ratio survive every
convention tested; the constants do not.

Note also that the current error is **bidirectional** — +4.60 and +4.09 against
-3.58 and -3.06. This is variance, not bias. Any candidate cause must explain
scatter in both directions, and any aggregate mean can conceal a factor that
moves seasons in opposite directions.

M1 has therefore **regressed roughly 4.3x in its core task**, and a known-good
configuration exists. This is recovery, not construction.

An earlier revision of this section asserted the opposite ("not a refinement of
a working capability; building the capability"). That was written before the
v16 comparison and is withdrawn.

**What is NOT a regression.** Across all 10 seasons v16's `a` ranges -1.988 to
**6.441** and its maximum forecast is **0.9871**. The amplitude pathology and
impossible forecasts are present in v16 too. An earlier revision implied they
were new, generalising from `fresh_deploy_wf_cache.rds`, which covers only
2025-26 and is the cleanest slice. Withdrawn.

**What IS a regression:** final peak error (0.6350 -> 2.7314 weeks) and state
un-latching. On a common stateless passage rule, v16 reverts TRUE->FALSE
**once** (2024-25); current reverts **34 times across 8 of 11 seasons**. Keep
this measurement separate from the latched rule proposed in §1.6, under which
reversions are impossible by construction and so cannot be evidence.

**What this kills.** `delta_on` is TRUE for 169 of v16's 334 origins, yet
`|delta|` still maxes at 0.013 — the `LAMBDA_DELTA` scale problem was present in
v16, which nevertheless achieved 0.766 weeks. The hypothesis that lambda causes
the pathology is not merely unproven; it is contradicted by a working
counterexample. Rev 4's Stage 1 is void.

**D-32's refutation is WITHDRAWN. It is a live candidate.**
`fresh_m1_alignment_tuning_v7.rds` holds v16's full 20-spec grid with peak MAE
per spec:

| k_ref \ slope_weight | 8 | 12 | 16 | 20 | 30 |
|---|---:|---:|---:|---:|---:|
| **25** | **1.316** | 1.339 | 1.384 | 1.448 | 1.547 |
| **30** | 1.339 | 1.373 | **1.366** | 1.465 | 1.589 |
| 40 | 1.337 | 1.381 | 1.370 | 1.430 | 1.597 |
| 50 | 1.344 | 1.391 | 1.380 | 1.442 | 1.609 |

D-32's pin (30, 16) costs **0.050 weeks** against the optimum (25, 8), and the
entire surface spans **0.293 weeks**.

Rev 5 concluded from this that the pin cannot produce a 2.1-week regression.
**That inference is invalid: the surface was measured under v16 code and does
not bound behaviour under current code.** On the current tree, the same
25/8 -> 30/16 switch moves the final estimate by **2 weeks in 2013-14 (31->29)
and 1 week in 2019-20 (28->27)**, with per-origin movements up to 3 weeks. That
is an order of magnitude more than the grid predicts.

It does not establish direction: the 2013-14 move is *toward* truth and the
2019-20 move is *away*. Two deliberately probed seasons cannot estimate a
10-season mean. **B is live and unproven**, and rev 5's derived claim that "the
cause is structural, not a hyperparameter setting" is withdrawn with it.

### Dead hypotheses — do not re-litigate

| # | hypothesis | why it died |
|---|---|---|
| 1 | `LAMBDA_DELTA` scale bug | v16 has the identical defect — `delta_on` TRUE on 169/334, `delta` in `[-0.0061, +0.0127]` — and scored 0.6350 |
| 2 | Multi-template weighted-mean peak derivation is new | **Not new.** Introduced at commit `47bcdf0` (2026-03-28), before the cache; v16's own artifact shows the same construction (96/334 rows where the upper quantile sits below the point estimate) |
| 3 | M1 `tau` saturates at 6.0 | Misread column. That is `training_rows$tau`, an **M2 time-since-peak feature clamped to `[-6, 6]`**. M1's shift is `m1_train_preds$m1_tau`, range -4.657 to +5.761 |
| 4 | v16 quantised the peak, damping jitter | Rounding current estimates to integers **worsens** MAE (2.7314 -> 2.8224) and leaves jumps intact (max 8.38 -> 8) |

Hypotheses 3 and 4 were the author's. Hypothesis 2 was a delegated worker's and
was accepted by the author before being traced to git history.

### Live candidates — none established

| id | candidate | measured share of the 2.096 wk gap |
|---|---|---|
| **B** | `k_ref` 25->30, `slope_weight` 8->16 | unknown; only candidate with demonstrated non-zero movement under current code |
| **C** | `anchorWeek` 19->20.5 and legacy integer -> fractional timing | composite; the isolated rounding component contributes **none**, the timing/anchor component is unmeasured |
| **A'** | changed *inputs* to the multi-template weights and timing coordinates (not the reduction itself) | unknown |
| **D** | `buffer_weeks` 5->0 | **exactly zero** of peak-location error; state-machine only |

**The cause is not identified.** M0 ignition is cleared for the two probed
seasons: a replay reproduced v16's `iWeek_hat` and `iWeek_true` exactly.

### `buffer_weeks` is a state fix, not an accuracy fix

v16 ran `buffer_weeks = 5`; the lag from `peak_weekF` to first `peak_passed` is
exactly 5 in 7 of 10 seasons. `pipeline_training.R:710` passes `5L` while every
other path defaults to `0L`. But `buffer_weeks` is applied only *after*
`peak_weekF` and its bounds are computed, so it cannot move the peak estimate.
In isolation, restoring it cuts stateless reversions 34 -> 18 and **plateaus
from buffer 3 onward**, never approaching v16's 1.

Restore it for reproducible state behaviour. Do **not** credit it with any of
the 2.096-week recovery, and do not present `buffer = 5` as restoring the v16
state machine.

### Lead-time accuracy today

Measured against the §1.1 truth:

| lead (weeks before peak) | origins | within 1 week |
|---|---:|---:|
| 1-2 | 22 | 13.6% |
| 3-4 | 22 | 18.2% |
| 5-6 | 21 | 23.8% |
| 7-8 | 13 | 15.4% |
| >8 | 12 | 0% |

Accuracy rises with lead to 5-6 weeks then falls. Bucket sizes are 12-22, so
this is a signal rather than an established fact. An earlier revision quoted
4.5% / 30.0% / 0% for the first three buckets using the legacy integer-argmax
truth; withdrawn.

## 1. The objective

### 1.1 Peak truth — decimal, human-first

**The program proposes, the human confirms or changes.** For each season the
harness presents the argmax, the parabolic suggestion, the strongest rival bump
and its height relative to the peak. The annotator returns **week(s), never a
decimal**:

- **one week** — "this is the peak week"; the decimal comes from parabolic
  interpolation on that week and its two neighbours;
- **two consecutive weeks** — "this is a two-week plateau"; the truth is the
  **interval** `[w1, w2]`. Distance is zero anywhere inside it and the distance
  to the nearest edge outside it. Rev 4 clamped a parabola to the span instead,
  which collapsed a declared 2024-25 plateau to 32.083 — one edge — on the
  strength of a single three-point fit. Interval truth preserves what the
  annotator actually asserted.

**Authoritative positivity field: `p = pos_flua / test_flu`.** This is what
PAGe fits on (`realtime_sources.R:155-156`). It is NOT the CSV's
`fluAPercentPositive`, which is a different quantity differing by up to 0.13 pp.
Rev 4 used the reported field without declaring it and five truths plus the
anchor moved as a result.

**API work IS required.** `timing_labels_v2` expands a singleton to `(w-1, w)`,
finalization resolves to the higher observed week as an integer, and
`score_peak_timing_v2()` scores that integer. It neither stores nor scores a
decimal or an interval. Rev 4's "no new machinery" claim was false. Stage 0 must
add a truth artifact that stores `(lo, hi, kind, source, provenance)` per
season.

The human resolves exactly what the algorithm cannot — which wave is the
epidemic peak, and whether a spike is real or a reporting artifact. Sub-week
timing is left to interpolation, which uses curvature the annotator cannot
eyeball.

**Labels confirmed 2026-09-19** (rival % is the strongest bump at least 3 weeks
from the argmax, as a fraction of the peak):

| season | label | truth `P_s` | rival | |
|---|---|---:|---|---|
| 2012-13 | 26+27 | [26, 27] | wk 29 at 89% | bimodal |
| 2013-14 | 27+28 | [27, 28] | wk 30 at 65% | |
| 2014-15 | 27 | 26.800 | wk 30 at 93% | bimodal |
| 2016-17 | 28 | 28.114 | wk 31 at 72% | |
| 2017-18 | 32 | 32.155 | wk 27 at 91% | bimodal |
| 2018-19 | 31 | 31.051 | wk 27 at 89% | bimodal |
| 2019-20 | 29 | 28.814 | wk 26 at 84% | |
| 2022-23 | 21 | 21.020 | wk 18 at 88% | bimodal |
| 2023-24 | 26 | 25.902 | wk 29 at 61% | |
| 2024-25 | 32+33 | [32, 33] | wk 29 at 79% | |
| 2025-26 | 25+26 | [25, 26] | wk 22 at 53% | |

The five bimodal seasons are the ones where a changed label would move the
anchors in §1.5; the other six are unambiguous.

**Fallback: three-point parabolic interpolation** about the observed argmax,
with `v_-1, v_0, v_+1` the positivity at the argmax and its two neighbours:

```
delta = 0.5 * (v_-1 - v_+1) / (v_-1 - 2*v_0 + v_+1)
P_s   = w_0 + delta
```

Preconditions — **all** must hold, else `P_s = w_0` with a recorded reason code:

1. Both neighbours exist, are finite, and are the **immediately consecutive**
   observed weeks `w_0 - 1` and `w_0 + 1`. A gap in the series disqualifies
   interpolation; it does not get silently bridged.
2. The argmax is **not** at the first or last observed week. Zero occurrences in
   the 11 closed seasons; 2026-27 is in progress.
3. Locally concave: `v_-1 - 2*v_0 + v_+1 < -eps`, with `eps` fixed at 1e-9.
4. **No tie at the argmax.** If two or more weeks share the maximum,
   `P_s = w_0` at the earliest tied week and interpolation is skipped entirely.
   (Rev 2 said "earliest tied week" *and* interpolated, which could return the
   plateau midpoint — the opposite of earliest. Defect, now fixed.)

`|delta| <= 0.5` follows algebraically from precondition 3 for a true interior
maximum, so no clipping is applied; a computed `|delta| > 0.5` indicates a
violated precondition and falls back to `w_0` rather than manufacturing a
boundary vertex.

**Bimodal and shoulder cases are not solved by interpolation and must not
pretend to be.** A season whose argmax sits on the shoulder of a second wave
satisfies every precondition above and still returns an epidemiologically wrong
answer. 2018-19 (argmax week 31, second-highest week 27, four weeks apart) is
the worked example. Therefore:

- The fallback is computed and stored for **every** season, including labelled
  ones.
- Before the sweep, every season where `|label - fallback| > 1.5` weeks is
  reviewed by a human, and the adjudication plus rationale is recorded in
  provenance. This is a check for coordinate and data-entry error, not a
  licence to pick whichever performs better.
- Truths are frozen before any candidate is scored. No averaging, no switching
  after seeing results.
- A season whose strongest rival bump (at least 3 weeks from the argmax)
  reaches **85% or more** of the peak is flagged BIMODAL and must be labelled by
  a human; it is never scored on the fallback alone. At 85% this flags 5 of 11
  seasons. The threshold is a design choice, not a measurement: at 60% it flags
  10 of 11 and is useless.

Both label and fallback are **decimal**, as is the estimate (`peak_weekF` is
already a continuous weighted mean across templates).

**Rejected alternative.** A value-weighted centroid of the argmax and its better
neighbour was rejected on measurement: positivity sits on a large baseline, so
when the two values are close the mass ratio is near 1 and the answer is the
midpoint regardless of the curve's shape. Its offset was ~0.48 weeks in all 11
seasons. In 2025-26 (34.4, 36.2, 34.6 — essentially symmetric) it returns 25.49
where the answer is ~25.0. Mean absolute agreement with the smoothed GAM peak:
parabolic 0.755, argmax 0.791, centroid 0.921 — the centroid is worse than not
interpolating. Parabolic is chosen for the symmetric-season behaviour; the
0.04-week gap to argmax is noise on n=11.

### 1.2 Peak score — bounded lead bonus over a fixed actionable window

For season `s`, over post-ignition origins `w` with lead `l = P_s - w`:

```
d_s(w) = |peak_hat(w) - P_s|                      # weeks, continuous
k_s(w) = exp( -d_s(w)^2 / (2 * kappa^2) )         # in (0, 1]
q(l)   = 1 + rho * l / H                          # bounded lead bonus
S_s    = sum_{0 < l <= H} q(l) * k_s(w) / sum_{0 < l <= H} q(l)
peak_score = mean_s S_s
```

**Frozen constants:** `kappa = 1.0`, `H = 8` weeks, `rho = 1.0`.

`kappa = 1.0` encodes "a one-week peak error is meaningfully wrong"
(`d = 1` gives `k = 0.607`). `rho = 1` caps the earliest-to-latest weight ratio
at 2:1. `H = 8` is the actionable lookback: a peak forecast more than two months
out does not change any decision, and the measured per-season maximum lead is
5-12 weeks (median 7), so `H = 8` truncates 2016-17, 2017-18 and 2018-19.

Rev 2 used an unbounded linear weight `q(l) = l`, which in principle lets the
farthest, least identifiable origins dominate: for leads 1..12 the farthest half
carries 73% of the denominator, so perfect estimates in the final four origins
contribute only `(1+2+3+4)/78 = 0.128`. The audit was right that this is a real
hazard and the bounded form is adopted.

In this dataset the hazard is mild rather than acute — measured on the
incumbent, unbounded gives mean 0.2117 against bounded 0.1980 — because the
actual lead range is 5-12 weeks, not the long-lookback regime where the
concentration bites. The bounded form is adopted anyway: it costs nothing and
guards the general case.

Properties: no credit at or after the peak; the same accuracy is worth more
earlier; every oscillating origin penalised continuously; bounded in [0, 1],
higher better; no hard threshold. Missing or non-finite peak estimates
contribute `k = 0` at their lead weight and remain in the denominator.

Hard lock curves at several tolerances are retained as **diagnostics** only.

**Measured on the incumbent** under the §1.1 truths (this is `peak_incumbent`):

| season | S_s | | season | S_s |
|---|---:|---|---|---:|
| 2012-13 | 0.349 | | 2019-20 | **0.626** |
| 2013-14 | 0.107 | | 2022-23 | 0.061 |
| 2014-15 | 0.455 | | 2023-24 | 0.069 |
| 2016-17 | 0.114 | | 2024-25 | 0.383 |
| 2017-18 | 0.147 | | 2025-26 | 0.058 |
| 2018-19 | **0.001** | | **mean** | **0.2155** |

Per-season spread is 0.001 to 0.626 — the metric discriminates strongly and sits
well away from both floor and ceiling.

Prior revisions quoted 0.198 (legacy integer-argmax truth) and 0.2185 (reported
percentage field, clamped-parabola plateaus). Both are withdrawn. 0.2155 is
measured on the authoritative `pos_flua/test_flu` field with interval truth for
the four two-week labels. Anchors must be measured under the exact definitions
they anchor — that error has now been made twice.

### 1.3 Forecast score — season-balanced, scored raw

MAE within each `season x horizon` cell, horizons averaged equally within a
season, then the 11 seasons averaged equally. The pooled figure is descriptive
secondary only. Rev 1 pooled all rows, which gave longer seasons and
better-covered horizons more influence while the peak component weighted seasons
equally, making "50/50" meaningless.

**Scoring uses the RAW forecast, not the clamped one.** Clipping a pathological
98% prediction to 50% improves its apparent MAE and hides exactly the severity
the clamp exists to signal. The clamped value is evaluated separately as the
operational output. The ledger stores raw prediction, clamped prediction, and a
clamp-activation flag for every row. (Rev 2's wording would have scored the
clamped value — a defect that would have rewarded extreme forecasts.)

**M2 offset semantics, stated explicitly since it is the defect under repair:**
the value supplied to M2 as the coefficient-1 offset is the **clamped** logit,
in every fit, evaluation and runtime path, and the exact value passed is stored
per row. Scoring M1 on raw while M2 consumes clamped is deliberate — M1 is being
measured on its true behaviour while the pipeline is protected from it.

Prespecified guardrails reported alongside pp-MAE, not selected on: **logit-scale
error** and **Bernoulli NLL**. Unit-gain propagation into M2 happens on the logit
scale and governed M2 evaluation uses NLL, so a pp-MAE-only objective could
improve the point loss while leaving the offset pathology intact.

### 1.4 Missingness and failure

"Over all origins with a forecast" is unsafe: a spec can improve its MAE by
failing on the hard origins. The denominator must also distinguish failures the
spec caused from rows where no truth exists at all.

**Two disjoint classes**, measured on the incumbent:

| class | reason codes | rows | counted against the spec |
|---|---|---:|---|
| structurally absent | `out_of_season`, `NA/NaN/Inf in 'y'` | 50 | no |
| spec-caused failure | `alignment_prediction_missing`, `aligned_week_outside_template_support` | 41 | yes |

Structurally absent rows leave the expected key set entirely — there is nothing
to predict and nothing to score. Spec-caused failures stay in the key set, in
the denominator, and are penalised.

- Scoring starts from the **complete expected key set** `season x origin x
  horizon`, constructed before any filtering, minus structurally absent rows.
- Every attempted origin materialises a row with a status. Failures are counted
  by reason and never removed by `na.rm = TRUE` before denominators are fixed.
- **Coverage is lexicographically prior to accuracy.** A candidate must have
  spec-caused failure coverage no worse than the incumbent's frozen rate,
  **globally and within every season x horizon cell**. A candidate failing this
  is ineligible regardless of its scores. This closes the gaming channel at the
  gate rather than trying to price it.
- **Failed-row loss is candidate-independent:** a spec-caused failure is scored
  at `max(incumbent error on that key, persistence-baseline error)` plus a fixed
  surcharge. It never references the candidate's own surviving rows.
  Rev 4 used `max(persistence, the spec's own cell MAE)`, which is gameable: for
  a cell with errors 0 and 100 and persistence 10, emitting both gives MAE 50
  while failing the hard row gives surviving MAE 0, penalty 10, total 5.
- Disqualification ceiling: incumbent rate plus **2 percentage points**,
  computed on the **eligible** denominator (structural rows removed). The
  incumbent is 41/676 = **6.07%**, not the 5.6% rev 4 quoted against 726.
  Rev 4's flat 10% would have permitted ~67 failures, enough to abandon a whole
  hard season.
- Missing peak estimates contribute `k = 0` at their lead weight, per §1.2.

### 1.5 Scalarization — fixed anchors, 50/50

```
J = 0.5 * (peak_score - peak_incumbent) / Delta_peak
  - 0.5 * (forecast_mae - mae_incumbent) / Delta_mae
```

**Frozen anchors:**

| anchor | value | basis |
|---|---:|---|
| `peak_incumbent` | 0.2155 | canonical y/N + interval truth, §1.2 |
| `mae_incumbent` | 9.253 pp | season-balanced per §1.3 (pooled is 9.347) |
| `Delta_peak` | 0.10 | ~half the incumbent's score; moves it into the range of its own better seasons |
| `Delta_mae` | 1.0 pp | a tenth of current error; the post-peak GAM gap is 7.6 pp, so 1 pp is a real but not heroic step |

So a spec gaining 0.10 of peak score and 1.0 pp of MAE scores `J = 1.0`.
Incumbent scores 0. These are immutable once this document is signed off;
changing them after seeing results starts a new cycle.

Rev 1's sweep-relative z-scores are withdrawn: they made the exchange rate
depend on grid composition, so appending unrelated bad specs could reverse the
ordering of two good ones.

A Pareto plot and alternate fixed anchors are reported as sensitivity analyses.
Selection happens under this one preregistered rule.

### 1.6 Hard constraints

**1. Amplitude.** Structural clamp at **50%** enforced at prediction time, so no
absurd value leaves the model under any spec. Forecasts above **40%** are
counted and reported per spec as a soft quality signal and do **not**
disqualify. The 40% rate is computed against the fixed expected denominator of
§1.4, not against emitted rows.

One threshold cannot serve as both safety rail and accuracy metric; a single
hard cap at 40% would disqualify a spec for one borderline data-poor
early-season row, which is how the M2 zero-degradation gate became
near-unpassable. The record maximum is 36.2%, set in the most recent season
(2025-26), so a bound near the record fits a sample that has not stopped
growing. A ceiling relative to the season's own running maximum was rejected:
early in a season it is brutally tight exactly when M1 has least data.

Raw prediction, clamped prediction and clamp activation are all stored; scoring
is on raw per §1.3.

**2. Peak passage.** Scored and constrained **separately** from peak location.
These are separable but not independent: both derive from the same per-template
peak weeks — location as the weighted mean, passage from the 97.5% weighted
quantile (`m1_multi_template.R:288-301`, `m1_peak_status.R:46-53`). Reducing
bias and spread together improves both; optimising the mean alone guarantees
nothing about the gate.

To be explicit, because confusing these would make the objective
self-contradictory: **estimating the correct peak date at an earlier origin is
rewarded; estimating an earlier peak date is not.**

**The passage rule is frozen, not deferred.** `peak_passed` becomes TRUE at
origin `w` when all three hold:

1. `last_obs >= peak_weekF_hi + buffer_weeks` with `buffer_weeks = 1`;
2. condition 1 has held at **2 consecutive origins** (`persist2`);
3. once TRUE it **latches** and never reverts.

Condition 3 is new and is not a tuning choice: Task B found the state un-latches
in 6 of 11 seasons, which is incoherent regardless of the gate's timing.

Acceptance limits, both achievable on Task B's measurement of `persist2`
(2/11 early, worst case 1-2 weeks):

- season-level false-alarm rate **<= 2/11**;
- maximum early firing **<= 2 weeks** in any season.

`buffer_weeks`, the persistence count and the latch are part of the spec and are
recorded per row, so the rule that produced any `peak_passed` is always
reconstructible.

**Defect to fix in Stage 0:** `pipeline_training.R:710` passes
`buffer_weeks = 5L` while every other path defaults to `0L`. Training and
evaluation have used different gates, and `peak_passed` is not reproducible
without recording which ran. Task B's early-fire counts must be re-derived once
this is settled, before §1.6.2's limits are applied to anything.

**3. Convergence.** Per §1.4.

### 1.7 Ledger requirements driven by later stages

Stage 3 proposes template voting and upper-bound stability. **Per-template peak
estimates and per-template weights are therefore required ledger fields, not an
optional future extension.** Without them Stage 3 forces a full refit.

### 1.8 Stage 0 gates — both must pass before any sweep

**Gate V — the v16 regression gate.** No stage advances unless it is no worse
than v16 on every one of these, all measured values, not invented thresholds:

| quantity | v16 | gate |
|---|---:|---|
| mean abs final peak error | 0.766 wk | `<= 0.766` |
| seasons where v16 is better | — | `<= 3 of 10` |
| state un-latch events | 1 | `<= 1` |
| `peak_incumbent` (§1.2) | 0.2155 (current) | must increase |

Gate V is deliberately harsher than a threshold I could choose, because it is
anchored to a configuration that demonstrably worked. A stage that cannot beat
v16 has not earned the compute for the next one.

Two caveats recorded so they are not rediscovered: v16's cache covers 10
seasons, not 2025-26, so the gate is computed on those 10; and v16 is NOT better
on amplitude — its `a` reaches 6.441 and its max forecast is 0.9871 — so Gate V
constrains peak behaviour only. Amplitude is governed by §1.6 independently.

**Gate A — row-level reproduction.** Four aggregate numbers can all match under
a wrong season join, a horizon off-by-one, compensating row drops, or duplicated
rows. Required:

1. Bind to hashes of the frozen prediction artifact, surveillance snapshot,
   fold/season declaration, M0 artifact, and code provenance — a source-tree
   hash, not a parameter hash (§2).
2. Assert the complete expected key set before filtering. Verify
   `target_weekF = origin_weekF + h`, unique keys, first and last origin per
   season, and exact counts at each gate: requested, emitted, truth-available,
   forecast-available.
3. Compare row-for-row against the frozen ledger on keys, availability,
   unavailable reason, point forecast, continuous peak estimate, peak bounds,
   state, and passage flag. Aggregates are secondary.
4. Reproduce per-season x horizon MAE and denominators, not only 9.35 pp.
   Reproduce the **identities** of all 49 rows above 40%, not only the count,
   including the known maximum and its row key.
5. Reproduce the full origin-by-origin `peak_passed` sequence and peak-bound
   trajectory, not only first-fire week. This catches the 2013-14 oscillation
   and state un-latching.
6. Verify peak truth independently: label where present, parabolic fallback
   otherwise, every precondition in §1.1, and the label/fallback discrepancy
   review. Assert MMWR/`weekF` conversion, M1 `newWeek` conversion,
   `anchorWeek`, and fractional-versus-rounded timing mode.
7. Confirm LOSO isolation: the held-out season must not enter its reference
   templates, learned alignment hyperparameters, ignition labels, or any
   data-derived normalisation.

**Gate B — quantitative discrimination and sentinels.** Rev 1's metric was
proposed without ever being evaluated on the incumbent, and was inert on all 11
seasons. Rev 2's Gate B was qualitative and contained an invalid test. Both are
replaced by:

*Quantitative checks*, on a pilot set of at least 12 diverse specs (incumbent,
historical 25/8, and corner specs spanning each axis):

- spread in `peak_score` across the pilot set `>= 0.5 * Delta_peak` (i.e. >=
  0.05), so the component can move `J` by at least a quarter-unit;
- no more than 3 of 11 seasons at the floor (`S_s < 0.01`) for the *median*
  pilot spec — guards against aggregate spread produced by one lucky corner;
- no single season contributing more than 40% of the between-spec variance in
  `peak_score`, where contribution is the **leave-one-season-out drop**:
  `1 - Var_{-s}(peak_score) / Var(peak_score)` across pilot specs;
- spread in `forecast_mae` across the pilot set `>= 0.5 * Delta_mae` (i.e.
  >= 0.5 pp);
- no more than 3 of 11 seasons at the forecast floor for the pilot spec at the median of `J`,
  where floor means a season x horizon MAE below 0.5 pp;
- the same leave-one-season-out variance check for `forecast_mae`;
- effective realised weight by lead: no single lead value may carry more than
  **35%** of the total realised weight, and at least **4 distinct lead values**
  must each carry >= 5%.

*Sentinel trajectories* with known expected ordering, scored before any real
spec: an early-accurate trajectory, a late-only-accurate one, a persistently
wrong one, and one with missing origins. The metric must rank them
early-accurate > late-only > wrong, and must not rank the missing-origin
trajectory above the wrong one.

Rev 2 also required that the 50/50 weighting change the ranking relative to
either component alone. **That test was logically invalid and is withdrawn** —
when the two components agree, a sound combined objective *should* preserve
their ranking. Two-component influence is instead demonstrated only on pilot
pairs that actually trade peak against forecast performance.

If any check fails, the objective is not fit to select and the sweep does not
start.

### 1.9 Selection optimism

Effective sample size for selection is **11 seasons**, not 635 rows.

- Season is the resampling unit. Paired candidate-minus-incumbent results by
  season; never row-level uncertainty.
- **Nested selection assessment:** for each held-out season, the *entire
  data-adaptive staged procedure* is repeated using only the other seasons —
  stage sizing, grid refinement, boundary expansion and tie-breaking included —
  and the resulting spec is scored on the held-out season. Selecting from a
  candidate set that was itself designed using all 11 seasons does not measure
  selection optimism and does not satisfy this requirement.
- Report leave-one-season-out winner stability, selection frequencies, and
  worst-season degradation.
- One-standard-error / simplest-on-a-plateau rule rather than raw maximum when
  candidates are indistinguishable.
- Predeclare grid, anchors, tie-breaker, missingness rule and boundary-expansion
  rule. Any post-result change starts a new cycle.
- No unbiased performance claim comes from the same 11-season sweep that
  selected the winner. Preserve the untouched prospective holdout for one final
  locked comparison.

The earlier finding that 0/205 M2 specs beat the trivial baseline in every
season argues for modelling heterogeneity and capping worst-season harm, not for
searching harder until something dominates all 11.

## 2. API and artifacts

Three distinct objects, separated:

**(a) Origin-level ledger** — the irreducible artifact. One row per
spec x fold x season x origin x horizon, including expected rows that produced
nothing:

- keys: spec identity, outer fold / held-out season, season, origin `weekF`,
  target `weekF`, horizon, expected-row indicator;
- forecast: **raw** and **clamped** probability and logit point forecasts,
  clamp-activation flag, interval bounds, logit spread, and the exact value
  supplied as M2's offset;
- peak at every origin: continuous point estimate, lower/upper bound,
  **per-template peak estimates and weights** (§1.7), raw alignment-scale
  values, passage threshold and rule identity, `peak_passed`, state, timing mode;
- truth: target `y` and `N`, target positivity, peak label, parabolic fallback,
  which was used, fallback reason code, truth-definition version;
- availability: attempted/emitted/scorable flags, reason code, optimizer
  convergence code, objective value, fallback use, count and identity of valid
  templates, non-finite diagnostics;
- alignment: `tau`, `delta`, `a`, `b`, `delta_on`, ignition estimate/lock,
  `anchorWeek`, coordinate system.

**(b) Derived metric tables** at season and season x horizon level, from (a).

**(c) Ranking**, from one immutable `objective_spec`.

Stated limits: a metric needing a horizon or forecast not emitted in the
original run cannot be recovered from the ledger. "Adding a metric later
requires no refit" holds only for functions of stored fields.

**Run identity.** A parameter-only spec hash does not detect changed code — the
failure mode already hit this session, where a pinned library was bypassed by
`devtools::load_all()` and the working tree ran instead. Cache lookup keys on:
canonical parameter serialisation and spec ID; source-tree or package commit
hash and artifact schema version; data snapshot hash and season/fold
declarations; upstream M0, reference-template, learned-hyperparameter and
manual-label identities; preprocessing/calendar version; all fixed behavioural
arguments including CI level, passage buffer, persistence rule, timing mode,
horizons and RNG scheme; dependency versions where they affect numerics.

Objective version belongs to the **ranking** identity, not the fit identity.

**`seed_from` splits into two operations.** Appending explicitly declared new
grid rows and reusing exactly compatible fits is sound. Automatically narrowing
around the prior winner is not sound after an objective change — the rescored
winner may differ and local refinement can miss remote Pareto-optimal regions.
Grid planning consumes the newly ranked full sweep, preserves the incumbent and
diverse finalists, and records boundary decisions.

**`m1_score()`** takes an immutable `objective_spec` and returns every candidate
with explicit eligibility reasons and per-season components. It never silently
drops failed specs and never breaks ties by input order.

## 3. Stages

Acceptance for every stage is the Stage 0 harness. Every data-dependent stage
consumes the same 11 seasons and adds adaptivity; all sit inside §1.9.

**Stage 0 — objective, harness, ledger, label API.** Deliverables: §1, §2, the
decimal peak label change, the `buffer_weeks` reconciliation, and the
label/fallback discrepancy review. Gates A and B must both pass.

**Stage 1 — crossed code x data replay.** Rev 4's lambda fix is void and rev
5's bisection design is void (see §0). v16 reached 0.6350 weeks *with* the
lambda problem present, so lambda is not the lever.

Rev 5's rule — "if current code cannot reproduce v16, the difference is in
code" — is **invalid**. A replay attempt changed code *and* data
simultaneously: v16's April input snapshot `data/flu_testing_data.csv` is
absent from the repo, and the September ORVT CSV differs from the cache's
observed series in **21% of observed rows** (up to 2.08 pp). Non-reproduction
under those conditions attributes nothing.

**The confounder is breakable.** v16's exact input is recoverable from inside
the artifact: each `ref_list` entry embeds `ref$dat` for its nine training
seasons with the authoritative `y` and `N`. Verified independently, twice:
4,689 embedded rows, **521 unique `season x weekF` keys**, every season in
**exactly 9** folds, **zero** disagreements in `y`/`N`/date, 52 weeks per
season (53 for 2014-15). That is a ninefold internal cross-check of an exact
snapshot, and it carries raw counts rather than a reconstructed ratio.

Provenance: the cache was written **2026-04-16 12:24:28**. The last commit
before that is **`741bc73` (11:46)**; `00ab9b4` (23:13) added `t_peak_median`,
which the cache lacks. Primary candidate tree `741bc73`, fallback `aafd0be`.

1. **Gate — reproduce row-for-row.** Replay `741bc73` on the recovered input
   with v16's configuration and compare all 334 rows on `tau, delta, a, b,
   t_peak, t_peak_lo/hi, peak_weekF, peak_passed, fallback_reason, n_train,
   anchorWeek` and fold membership. **Do not proceed on a failed gate** — a
   tree that cannot reproduce the cache cannot attribute a difference to code.
2. **2x2 cross.** {v16 code, current code} x {v16 data, September data}, with
   configuration, timing mode, folds and origin schedule fixed. The
   off-diagonal cells separate the code effect from the data effect.
3. **One factor at a time on v16 data:** code, then timing/anchor, then
   `25/8 -> 30/16`. Compare full origin trajectories and `fallback_reason`
   identity, not only final MAE, and report **per season** — the error is
   bidirectional and a mean can hide a factor that moves seasons opposite ways.

**No pre-registered expectation is recorded, deliberately.** Four hypotheses
have now been advanced with confidence and refuted (§0), two of them the
author's. The adjudicated verdict on cause is **null**. Success is either one
factor reproducing most of the 2.096-week gap with consistent per-season
evidence, **or a sustained null** — the latter is a valid and preferred result
over another unsupported nomination.

No sweep runs until Stage 1 reports. A full grid search is the wrong instrument
for recovering a known-good configuration.

**Stage 2 — constrain amplitude to phase.** Penalty on implied peak amplitude
plus the §1.6 clamp. Sized from Stage 1's residual overshoot count, not today's
49.

**Stage 3 — stabilise the peak state.** Task B: `peak_passed` plus 2 consecutive
declining weeks gives 0/11 early fires at +4 weeks median latency; `persist2`
gives 2/11 early at much lower latency. Since §1.2 values earliness, latency is
not free. Attack the CI instability directly (template vote, upper-bound
stability across origins) rather than only adding delay. The §0 non-monotonicity
finding is the primary target here.

**Stage 4 — full retune of `k_ref` / `slope_weight` and the alignment
hyperparameters** on §1.5. Not a revert to 25/8: those were optimal for peak
timing alone, under the `LAMBDA_DELTA` bug. D-32's "flat M1 surface, 0.16-0.18
weeks over 25 specs" was measured on peak timing with dilation disabled; treat
as unverified until re-measured. That the flatness is *caused by* the bug is a
hypothesis, not a finding.

**Stage 5 — post-peak routing.** `forecast_post_peak_gam()` exists, works, has
zero callers. Post-peak it beats M1 1.34 vs 8.93 pp in 10 of 11 seasons, without
the template covariate (which hurts: 2.37 vs 1.34). Do not wire it until the gap
is re-measured after Stages 1-4. Fix the latent `s(eta_ref, k = 2)` bug before
quoting any with-template number. Routing cannot be judged without re-evaluating
M2.

**Stage 6 — intervals.** Last. M1's cover 23.4% against nominal 95%; M2's cover
0.8%.

## 4. Scope boundaries

- `PAGe/R/m2_subset_correction.R` and `manuscript/**` belong to page-46
  (oracle). No edits from this workstream.
- M2 breadth (reversing the trim, freeing the offset coefficient from 1) is
  deferred until M1 is frozen, with one exception: testing a free offset
  coefficient may proceed in parallel, being the most direct fix for unit-gain
  propagation.
- Production continues on v2.1 throughout. Nothing here touches the production
  path until an explicit promotion decision.

## 5. Frozen constants — SIGNED OFF 2026-09-19

Confirmed by the principal. These are immutable for this cycle; changing any of
them after seeing results starts a new cycle and invalidates the nested
selection assessment in §1.9.

| item | value | §|
|---|---|---|
| `kappa` | 1.0 | 1.2 |
| `H` (actionable lookback) | 8 weeks | 1.2 |
| `rho` (lead bonus) | 1.0 | 1.2 |
| `peak_incumbent` | **UNFROZEN — must be recomputed** | canonical y/N + interval truth, §1.2 |
| `mae_incumbent` | 9.253 pp | 1.5 |
| `Delta_peak` | 0.10 | 1.5 |
| `Delta_mae` | 1.0 pp | 1.5 |
| failed-row penalty | **fixed surcharge, candidate-independent — see §1.4** | 1.4 |
| false-alarm ceiling | <= 2/11 seasons | 1.6 |
| max early firing | <= 2 weeks | 1.6 |
| bimodal review trigger | rival bump >= 85% of peak | 1.1 |
| M1 scoring | raw forecast | 1.3 |
| M2 offset | clamped logit | 1.3 |

Previously settled: 50/50 weighting; human-label-first decimal peak truth with
parabolic fallback; 50% hard clamp and 40% soft count; peak detection timing in
scope; `LAMBDA_DELTA` is a bug; Stage 4 is a full retune.

### Rev 6 unfreezes and corrections

Two entries above are no longer signed off, and both block the sweep.

1. **`peak_incumbent` (was 0.2155).** Measured under a truth convention this
   document contradicts. Recompute from the provenance-bound ledger under the
   final interval rule and the declared 10-season scope. **Blocked on a
   prerequisite:** §1.2 does not define lead/window weighting for an
   *interval-valued* peak, so the peak score is not executable until it does.
   Specify that first, then recompute.

2. **Failed-row penalty (was `max(persistence err, spec's own cell MAE)`).**
   This table contradicted §1.4, which had already rejected that rule as
   gameable and specified a candidate-independent loss. The signed table was
   never updated. §1.4 governs; a fixed surcharge must be named explicitly.

Three further corrections, not constants but binding on the harness:

3. **Season scope.** Gate V and every reported pair use the **10 shared
   seasons**. An 11-season figure may appear only as an explicitly labelled
   development anchor and may never be substituted for the gate.

4. **Terminal origin.** "Last origin" is ill-defined across the two sides: v16
   runs to eval week 52-53, current's last *available* origin is week 42-51,
   and a literal last origin returns NA for 10 of 11 current seasons. Freeze a
   common origin key set; use the **latest common forecast-available origin**
   for the historical diagnostic. For a prospective gate, use a fixed terminal
   schedule and treat a spec-caused missing estimate under §1.4's missingness
   rule — do not move the endpoint earlier until a forecast appears.

5. **`iWeek_true` is not truth.** In the v16 artifact it equals
   `canonical label - 1`, an intentional offset
   (`scripts/fresh_run/03_m1_loso.R:6-8`). Record it as
   `manual_label_legacy`. It must not validate M0 or enter a truth table.
   Carry `iWeek_hat`, canonical label, legacy offset, timing mode and
   coordinate transform as **distinct** fields.

6. **2013-14 is fallback-dependent in v16.** 17 of its 33 origins (51.5%) carry
   `delta_unstable_profile`, all late-season, all still returning finite
   estimates. Stop treating 2013-14 as clean evidence about the primary
   alignment path. Gate A and Stage 1 must reproduce and compare
   `fallback_reason` row-for-row and report results **stratified by fallback**.
   This is 24/334 rows overall and v16 still wins 9/10 seasons, so it qualifies
   the baseline rather than erasing it.

## 6. Audit history

**Rev 5 adjudicated NULL on cause** — `docs/m1-sol-adjudication.md`. Three
workers ran in parallel: Argie (`docs/m1-argie-findings.md`), a reproduction
worker (`docs/m1-v16-repro-findings.md`), and Sol adjudicating both.

Verdict: the regression is real and robust (v16 better in 9/10 seasons under
every truth convention tested) but **no cause is identified**. Rev 5's two
confident claims — D-32 refuted, multi-template derivation as the new
structural change — were both wrong. Rev 5's headline constants were wrong.
Rev 5's Stage 1 design was invalid.

Corrections folded into rev 6: headline `0.766/2.912` -> `0.6350/2.7314`
(§0); D-32 un-refuted (§0); four dead hypotheses tabulated, two of them the
author's (§0); `buffer_weeks` bounded to state-only (§0); Stage 1 replaced by
the crossed replay on the recovered v16 input (§3); `peak_incumbent` unfrozen
and the failed-row penalty reconciled with §1.4 (§5); season scope, terminal
origin, `iWeek_true` semantics and 2013-14 fallback stratification (§5).

Two process notes worth preserving. **Delegation caught what solo work did
not**: Argie found the author's `tau` column error; the reproduction worker
un-refuted D-32; Sol killed Argie's primary hypothesis via git history and
recovered the v16 input from `ref_list`. **And every worker return needed
verification** — Argie's CI claim ("4-6 weeks wide") was overstated by ~6x
against an actual v16 median of 0.709 wk, though its qualitative core
(132/690 zero-width vs 0/334) held.

**Rev 1 rejected** — `docs/audits/m1-plan-audit-sol-2026-09-19.md`. Decisive
finding, independently reproduced before acceptance: the proposed
lead-time-at-hard-lock score was **0.000 on all 11 seasons** at the proposed
1-week tolerance (and at 0.5 wk; 1 of 11 nonzero at 1.5 wk). The 50% peak weight
would have been inert and the sweep would silently have become forecast-only.
Also accepted: grid-dependent z-scores, pooled-row forecast weighting, the
`buffer_weeks` inconsistency, ledger/metric/ranking conflation, weak run
identity, unaddressed selection optimism.

**Rev 2 rejected** — `docs/audits/m1-plan-reaudit-sol-2026-09-19.md`. Four
defects *introduced while fixing rev 1*: unbounded linear lead weighting risked
a new degeneracy; earliest-argmax tie handling contradicted the subsequent
interpolation; Gate B's mandatory rank-change test was logically invalid; and
scoring the clamped forecast would have rewarded extreme predictions by
truncating their errors.

**Rev 3 rejected** — `docs/audits/m1-plan-audit3-sol-2026-09-19.md`. The
decisive defect: **both frozen anchors were measured under metrics the plan
itself supersedes.** `peak_incumbent` was computed against the legacy integer
argmax rather than the §1.1 truth (0.198 vs the correct 0.2185), and
`mae_incumbent` was the pooled figure rather than the season-balanced one §1.3
declares (9.35 vs 9.253). Since the anchors define what the 50/50 trades, this
would have silently miscalibrated the entire sweep. The §0 lead-time table had
the same fault and its headline contrast did not survive correction. Also:
the persistence substitution could reward failure; the 5% threshold disqualified
the incumbent; the forecast-side Gate B checks and the bimodality review trigger
were not executable as written; and `H = 8`'s truncation claim was wrong.

**Standing lessons, both earned:**

1. No objective is authorised for a sweep until it has been evaluated on the
   incumbent and shown to discriminate (rev 1).
2. No constant is frozen until it has been measured **under the exact
   definitions it anchors** (rev 3). Reusing a number computed under a
   superseded definition is the same class of error as reusing a stale artifact.
