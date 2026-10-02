# M2-v2 Flu-B timing and numeric-baseline findings — 2026-09-23

## Status

This is an exploratory design/implementation checkpoint, not a frozen Flu-B production timing contract.

The main result is architectural:

- Flu-B peak-aligned shape contains useful timing information.
- The A-style ignition detector does **not** transfer well to B.
- A simpler B-specific design is preferable: **causal activity availability + short recent-history window + B-specific M1 amplitude support**.
- B passage confirmation is not yet safe/reliable enough to expose.
- For numeric +1/+2 forecasting, plain persistence remains the baseline to beat; the first growth model does not improve it.

## 1. Provisional retrospective B ignition target

There are no governed expert B ignition labels yet.

Rather than invent an absolute B positivity cutoff, the provisional target transfers the geometry of the existing expert A ignition labels:

1. fit the same restrained retrospective k=8 GAM;
2. before the peak, define the low baseline as the 5th percentile of fitted positivity;
3. for each expert-labeled A season, measure the expert ignition location as a fraction of the baseline-to-peak excursion;
4. take the median fraction across A seasons;
5. for B, define provisional ignition as the **last upward crossing before the B peak** of that transferred excursion fraction.

The transferred fraction is **0.088885** (about 8.9% of the baseline-to-peak excursion).

When applied back to A, this purely geometric rule reproduces the expert A ignition labels with:

- MAE: **0.611 weeks**;
- bias: **+0.142 weeks**.

For B, k=5/6/8/10 ignition sensitivity exceeds one week in only 2/11 seasons, although B peak truth itself is smoothing-sensitive in 6/11 seasons.

This makes the transferred rule useful as an **exploratory evaluation target**, but it is not yet expert-reviewed B truth.

## 2. A-style M0-B transfer fails

A strict LOSO test retained the existing M0 detector family/selector but used a small B-specific threshold/calendar grid.

Result against the provisional B ignition target:

- mean absolute error: **3.004 weeks**;
- median absolute error: **2.874 weeks**;
- maximum absolute error: **8.635 weeks**;
- misses: **1/11**;
- bias: approximately **-1.78 weeks** (early).

The main failure is 2018-19, where the provisional detector fires roughly 8.6 weeks early. 2022-23 is missed.

Conclusion: **do not promote an A-shaped M0-B ignition detector** simply for architectural symmetry.

## 3. M1-B has genuine timing signal if the history window is sensible

M1-v2 was generalized so each library carries an explicit regularly spaced amplitude-integration grid.

- Influenza-A default remains exactly `0.08 ... 0.44` by 0.02.
- B experiments use a lower grid (`0.005 ... 0.25` by 0.005) because 6/11 B retrospective peaks are below 8%.
- Inner calibration/passage libraries inherit the same amplitude grid.

### Oracle-activation diagnostic

Using the provisional retrospective B ignition only as an **upper-bound diagnostic**:

- origin-level peak MAE: **1.317 weeks**;
- season-balanced peak MAE: **1.259 weeks**.

A leave-one-season-out median ignition-to-peak-duration comparator has MAE **2.118 weeks**.

Thus the peak-aligned B shape model contains substantial timing information beyond a constant duration rule.

### Causal provisional M0 activation

Feeding the weak M0-B detections directly into M1-B degrades performance:

- origin-level MAE: **2.514 weeks**;
- season-balanced MAE: **1.924 weeks**.

Again, the bottleneck is activation, not the peak-relative shape library.

## 4. Activity availability is more useful than a formal B ignition state

A causal B activity gate was explored using the last four observed weeks. Gate candidates combine:

- a recent maximum positivity floor;
- a trailing positive-count floor.

These gate results are **descriptive sensitivity analyses only**. No threshold is selected from held-out performance.

When M0-B is retained only as an early history anchor and an activity gate controls whether M1-B is exposed, conditional season-balanced peak MAE is stable at roughly **0.91–1.02 weeks** across a broad candidate grid.

This suggests low-signal abstention is more important than precise B ignition detection.

## 5. Simpler candidate: activity gate + short lookback, no M0-B

A more first-principles B timing candidate removes M0-B entirely:

1. wait until the causal activity gate is satisfied;
2. expose B timing only from that origin onward;
3. feed M1-B a short fixed lookback immediately preceding the gate rather than a putative ignition date.

Exploratory candidate family:

- positivity gate: 1.5% or 2.0%;
- trailing positive count: 40;
- lookback: 4 or 6 weeks.

The strongest simple candidate in the descriptive audit is:

- 4-week gate window;
- max positivity >=2%;
- trailing four-week positive count >=40;
- 4-week M1 history lookback.

It is available in **10/11 seasons** and gives approximately:

- origin-level M1-B MAE: **1.05 weeks**;
- season-balanced M1-B MAE: **1.00 week**.

The only unavailable season is 2018-19, whose retrospective B peak is only about 1.2% positivity. That is an appropriate `timing_unavailable` case rather than a detector failure.

Representative season-balanced errors under this candidate:

- 2012-13: ~1.02 weeks;
- 2013-14: ~1.40;
- 2014-15: ~0.58;
- 2016-17: ~0.74;
- 2017-18: ~0.43;
- 2019-20: ~2.32;
- 2022-23: ~1.73;
- 2023-24: ~0.43;
- 2024-25: ~0.52;
- 2025-26: ~0.84.

A 1.5% gate recovers 2018-19 but its timing error is materially worse there, so 1.5% and 2.0% should remain competing **training-fold candidates**, not be selected from these same held-out results.

### Denominator-regime sensitivity

Repeating the 2% / four-week-lookback diagnostic using only the 10 historical shared-denominator seasons gives season-balanced MAE **1.031 weeks**, close to the full-panel result.

Therefore the modern ORVT denominator transition is not the main driver of the timing gain. It remains important for the eventual M2 observation likelihood.

## 6. B passage is not ready

B passage was evaluated separately from B peak timing.

For the 2% / four-week-lookback timing candidate:

- the transferred A-style hybrid passage rule produces **one false-early confirmation** (2019-20);
- restricting to the conservative fast branch (`P(peak passed) >= 0.95` plus an immediate consecutive-week decline) gives **zero false-early confirmations**, but only **6/10 activity-eligible seasons** confirm by peak+2.

At a 1.5% gate, the conservative branch is still false-early-safe but confirms only **7/10 by peak+2**.

This does not meet the desired B passage acceptance bar.

Decision: **do not expose M1-C-B yet**. M2-v2 may consume B peak-phase location/uncertainty when timing is available, but B passage remains `unavailable/experimental` until a dedicated rule is validated.

## 7. B0/B1 numeric baselines

The numeric forecast ledger is candidate-independent and evaluated by strict LOSO, separately from timing availability.

### B0

Persistence:

`p_hat(t+h) = p_B(t)`

### B1

Persistence plus a learned logit-scale increment:

`logit p_hat(t+h) = logit p_B(t) + delta_hat(h, recent_growth)`

B1 is fit on the other seasons with season-by-horizon balancing. It does not consume M0/M1 timing.

### Results

On all forecastable weeks:

- B0 overall MAE: **0.541 percentage points**;
- B1 overall MAE: **~0.612 pp**;
- B0 h1: **0.405 pp**;
- B1 h1: **~0.463 pp**;
- B0 h2: **0.679 pp**;
- B1 h2: **~0.764 pp**.

On the provisional epidemic ledger (provisional ignition through peak+2):

- B0 overall: **1.091 pp**;
- B1 overall: **~1.208 pp**;
- B0 h1: **0.769 pp**;
- B1 h1: **~0.879 pp**;
- B0 h2: **1.413 pp**;
- B1 h2: **~1.538 pp**.

Persistence therefore remains the primary numeric hurdle. The first growth correction should not be promoted.

## 8. Current B timing contract for M2-v2 development

For the next structured M2 experiment, use three explicit B timing states:

- `timing_unavailable`: activity gate has not opened or signal is too weak;
- `timing_active`: activity gate is open and B M1-F peak posterior is available;
- `passage_unavailable`: current default for B; no B peak-passage lock is trusted yet.

When `timing_unavailable`, M2 must still issue B0/B1-style numeric forecasts. Timing abstention must never remove a row from the scoring ledger.

The **candidate family**, not a single chosen gate, should be frozen before the next nested experiment:

- p gate in {1.5%, 2.0%};
- four-week positive count >=40;
- M1 lookback in {4, 6} weeks;
- B amplitude grid 0.5%–25% by 0.5 percentage points.

Gate/lookback selection must occur inside each outer training fold if it is tuned at all.

## 9. What to implement next

The next M2-v2 experiment should compare, on one fixed +1/+2 ledger:

- B0 persistence;
- B1 persistence + growth;
- B2 = B0/B1 plus B M1-F phase/uncertainty when `timing_active`, with explicit fallback otherwise.

Only if B2 improves B0 under strict nesting should the partially pooled A/B curve family C2 be introduced.

This ordering matters: the current evidence supports B timing as potentially useful, but does **not** yet show that timing improves numeric +1/+2 forecasts.

## Artifacts

Authoritative exploratory script:

`scripts/evaluate_flu_b_timing_baselines_v1.R`

Compatibility entry point:

`scripts/b_timing_prototype_v1.R`

Primary artifacts:

`artifacts/m2-v2-flu-b-timing-baselines-v1/`

Supporting diagnostics created during development:

- `artifacts/m0-b-provisional-loso-v1/`
- `artifacts/m1-b-oracle-activation-v1/`
- `artifacts/m1-b-causal-m0-provisional-v1/`
- `artifacts/m1-b-passage-provisional-v1/`
