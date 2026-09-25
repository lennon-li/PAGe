# IMPORTANT REVIEW STATUS — SUPERSEDED FOR PROMOTION

An independent audit after this checkpoint found two governance defects in the
`m2-v2-b-phase-nested-selected-v1` promotion evidence:

1. inner validation season `v` was not excluded from every upstream timing
   feature used to fit the inner training correction; and
2. the 5% B epidemic gate was chosen with full-panel development knowledge
   rather than selected strictly inside outer training folds.

Therefore the reported "11/11 outer folds select timing at +2" result is **not
valid promotion evidence**. The B0/B1 baseline results remain valid, and the
outer-held-out B timing posteriors remain useful exploratory features because
the held-out season itself was excluded from their timing library. Subsequent
C1/C2/C3 work must use a repaired nested selection/gating contract before any
production promotion.

---

# M2-v2 B timing and baseline findings — 2026-09-23

## Scope

This checkpoint evaluates whether Influenza B needs and can support a causal timing state, and establishes the first +1/+2 B forecasting baselines before any pooled A/B curve model is fitted.

The current conclusion is deliberately asymmetric:

- **Do not promote a universal B-M0 ignition detector.**
- **Use B1 as the always-available B forecast baseline.**
- **Allow B timing only after a conservative causal epidemic-activity gate.**
- **Use B timing as a soft phase correction at +2 only; do not use it at +1.**
- **Do not promote a discrete B passage lock yet.**

## 1. Provisional retrospective B ignition target

No expert B ignition labels currently exist. A first-pass programmatic target was therefore built for evaluation only.

Procedure:

1. fit the same retrospective k=8 GAM used for peak geometry;
2. estimate a low pre-peak baseline as the 5th percentile of fitted pre-peak positivity;
3. define the ignition level at 8.888451% of the baseline-to-peak excursion;
4. take the **last upward crossing** of that level before the retrospective peak.

The excursion fraction comes from the median baseline-adjusted fitted level at the existing expert Influenza-A ignition labels.

As a validation of the rule family, applying this same rule back to the 11 expert-A seasons gives:

- MAE versus expert A ignition: **0.611 weeks**;
- median absolute error: **0.61 weeks**;
- bias: **+0.142 weeks**;
- max absolute error: **1.40 weeks**.

For B, the provisional ignition-to-peak durations are:

- median: **11.94 weeks**;
- range: **9.13–15.48 weeks**.

This is much more plausible than a simple first fraction-of-peak crossing, which is corrupted by early low-level B blips in weak seasons.

**Status:** provisional evaluation target only. It is not frozen scientific truth and must not enter runtime features.

## 2. B-M0 strict LOSO diagnostic

A 36-spec B-specific threshold grid was evaluated using the existing M0 detector family and the provisional B ignition target.

Grid changes relative to A are scale/window changes only:

- `p_thr`: 0.0005 / 0.001 / 0.002;
- `prev_thr`: 0.00025 / 0.0005 / 0.001;
- `p_sum_thr`: 0.010 / 0.020;
- `n_consec`: 4 / 5;
- `w_min = 18`, `w_max = 40`;
- other detector structure unchanged.

Strict LOSO result across 11 B seasons:

- MAE: **1.968 weeks**;
- median absolute error: **1.320 weeks**;
- max absolute error: **5.634 weeks**;
- seasons >2 weeks absolute error: **5/11**;
- explicit detector misses: **0/11**;
- mean bias: **+0.076 weeks**.

The worst case is low-amplitude 2018-19 (+5.63 weeks). Low-signal seasons are materially less stable than epidemic seasons.

**Decision:** do not promote B-M0 as the operational B timing activation clock.

## 3. Causal B timing-availability gate

The independent review identified weak B seasons as the main timing risk. The conservative operational gate is therefore based on observed B activity, not retrospective season class:

- origin week >=18;
- trailing 4-week B positives >=40;
- trailing 4-week maximum B positivity >=5%.

This gate opens in exactly the six seasons whose retrospective B peak exceeds 5% and stays closed in all five low-signal seasons.

Among the six activated seasons:

- median gate-to-peak lead: approximately **4.0 weeks**;
- range includes enough pre-peak lead for +1/+2 forecasting while avoiding background-circulation timing fits.

The 5% threshold is an exploratory conservative gate motivated by the independent review’s epidemic/low-signal split. It is not yet a production-frozen constant.

## 4. Gated M1-B prototype

The existing peak-relative M1-v2 architecture was reused with B-specific fitting and a B amplitude grid:

`0.005, 0.010, ..., 0.250`

The A default remains unchanged at `0.08–0.44`.

Why this matters: six of 11 B seasons peak below 8%, so the A amplitude support is invalid for B.

Under the conservative 5% timing gate:

- timing-active seasons: **6/11**;
- overall candidate-independent truth-ledger availability: **17.1%**;
- season-balanced conditional peak MAE: **1.337 weeks**;
- conditional RMSE: **1.434 weeks**;
- nominal 90% point-truth coverage: **94.4%**.

A simple activation-plus-training-median-duration baseline scores **1.963 weeks** conditional MAE on the same activated seasons/origins.

Thus gated M1-B improves conditional timing MAE by approximately **32%** versus the simple duration baseline.

This is useful evidence that B timing contains information once a real B epidemic is visible. It does **not** justify running B timing during low-level background circulation.

## 5. B passage diagnostic

A conservative diagnostic passage rule was checked on the six epidemic B seasons using the B passage posterior:

- fast branch: `P(peak passed) >= 0.95` plus immediate decline;
- sustained branch: posterior >=0.20, two consecutive declines, >=8% drop from running maximum.

Result:

- false-early confirmations: **0/6**;
- confirmed by peak+2: **3/6**;
- mean delay among confirmations: **2.5 weeks**.

**Decision:** this is safe but too slow. Do not promote a discrete M1-C B passage lock yet. M2 may consume the causal B passage posterior probability as a soft feature, but no B locked-peak state should be considered governed at this stage.

## 6. B0 and B1 +1/+2 baselines

A candidate-independent ledger was created for all B origins from week 13 onward with two observed history points and an in-season +1/+2 target. Row existence is independent of timing activation.

### B0 — persistence

`p_hat(t+h) = stabilized p_B(t)`

### B1 — state/growth model

Quasi-binomial LOSO model:

`logit p(t+h) = logit p*(t) + horizon + growth_1 + growth_2`

where:

- `p*(t)` uses a 0.5 pseudocount;
- `growth_1` is one-week stabilized logit change;
- `growth_2` is two-week average stabilized logit change.

Test volume / denominator regime are retained as provenance but are **not** predictive coefficients in the frozen B1 prototype. Including test volume improved exchangeable LOSO slightly but failed chronological robustness because the surveillance-volume regime changed substantially over time.

### Exchangeable strict LOSO

Season-balanced MAE in percentage points:

| Horizon | B0 | B1 | Relative improvement |
|---|---:|---:|---:|
| +1 | 0.494 | **0.447** | **9.6%** |
| +2 | 0.851 | **0.681** | **19.9%** |

B1 beats B0 in **9/11 seasons** at both horizons.

### Expanding-window chronological replay

Starting once at least three prior seasons are available:

| Horizon | B0 | B1 | Relative improvement |
|---|---:|---:|---:|
| +1 | 0.377 | **0.325** | **13.7%** |
| +2 | 0.640 | **0.541** | **15.5%** |

This establishes B1 as the current always-available B baseline.

## 7. Strictly nested B2 timing correction

The key question was whether B timing improves B1 after strict upstream nesting.

For every outer season `o`:

- outer test timing features use an M1-B library excluding `o`;
- each training season `r` receives timing features from a library excluding **both `o` and `r`**;
- low-signal seasons never open the 5% timing gate and therefore fall back exactly to B1.

Timing features come from the B passage posterior:

- posterior mean peak time / weeks-to-peak;
- posterior `P(peak passed)`;
- posterior width.

### First joint B2 fit

A model that refit common growth coefficients together with timing features degraded +1 and slightly perturbed low-signal rows. This architecture was rejected.

### Timing-only correction

B2 was reformulated as a correction on top of B1:

- unavailable timing rows are **identically B1**;
- timing correction is fitted only on timing-active rows.

Without inner model selection:

- +1 worsened by ~5.9%;
- +2 improved by ~6.2%;
- low-signal rows were exactly unchanged.

### Nested horizon-specific model selection

For each outer fold and horizon, an inner leave-one-season-out selector chose between:

- B1;
- B1 + timing correction.

The selector was unanimous across all outer folds:

- **+1: reject timing in 11/11 folds**;
- **+2: select timing in 11/11 folds**.

Final strict outer result:

| Horizon | B1 MAE pp | Selected B2 MAE pp | Relative gain |
|---|---:|---:|---:|
| +1 | **0.447** | **0.447** | 0% — exact B1 |
| +2 | 0.681 | **0.634** | **6.9%** |

At +2 in the six epidemic B seasons:

- B1 MAE: **0.986 pp**;
- selected B2 MAE: **0.899 pp**;
- relative improvement: **8.8%**.

In all five low-signal seasons, selected B2 is **exactly B1** at both horizons.

The +2 per-test NLL gain is positive but small (~0.00026 overall); MAE is the more interpretable operational signal under the current denominator-regime uncertainty.

## 8. Current B architecture decision

### Do not promote

- universal B-M0 activation;
- B timing during low-signal circulation;
- a discrete B passage lock;
- B timing at +1;
- use of A timing as B timing.

### Retain

**B1** as the default B forecast at both horizons.

### Add conditionally

For **+2 only**, once the causal B epidemic gate opens:

- compute strictly type-B timing posterior features;
- apply the timing-only B2 correction;
- otherwise return exact B1.

This is the first B timing use that survives strict nested selection.

## 9. Remaining governance work before package integration

This work remains prototype-level because two scientific contracts are not frozen:

1. **B ignition truth** is provisional/programmatic, not an expert/frozen truth spec.
2. **B denominator observation model** changes between historical shared-denominator proxy and modern type-specific ORVT reporting.

Before production integration:

- freeze or explicitly retire B-M0 rather than leaving ambiguous activation semantics;
- version the 5% B timing-availability gate if retained;
- formalize the B measurement/denominator regime;
- run the selected B2 architecture in a strict chronological model-selection replay, not only the simpler B1 chronological replay;
- decide whether a separate B M1-C lock is needed at all for +1/+2 M2, since the soft passage posterior already provides useful +2 information.

## 10. Artifacts

### Provisional B-M0

`artifacts/m0-b-provisional-loso-v1/`

### B0/B1

`artifacts/m2-v2-b-baselines-v1/`

Key files:

- `candidate_independent_ledger.csv`;
- `loso_predictions.csv`;
- `summary.csv`;
- `per_season_metrics.csv`;
- `chronological_predictions.csv`;
- `chronological_per_season.csv`;
- `chronological_summary.csv`.

### Gated M1-B

Conservative epidemic-gated diagnostic:

`artifacts/m1-b-gated-5pct-prototype-v1/`

### Strict nested B2

`artifacts/m2-v2-b-phase-nested-v1/`

### Strict nested selected B2

`artifacts/m2-v2-b-phase-nested-selected-v1/`

Key files:

- `strict_nested_selected_predictions.csv`;
- `outer_selection_decisions.csv`;
- `inner_selection_scores.csv`;
- `per_season_metrics.csv`;
- `summary.csv`;
- `signal_stratified_summary.csv`.

## 11. Scripts

- `scripts/run_m0_b_provisional_loso_v1.R`
- `scripts/run_m1_b_gated_prototype_v1.R` (defaults to the reviewed 5% epidemic gate; override with `PAGE_B_TIMING_GATE_P` for sensitivity runs)
- `scripts/run_m2_b_baselines_v1.R`
- `scripts/run_m2_b_phase_nested_v1.R`
- `scripts/run_m2_b_phase_nested_selected_v1.R`

The 5% gated M1-B result is reproducible directly from `run_m1_b_gated_prototype_v1.R`; the gate is an explicit script parameter via `PAGE_B_TIMING_GATE_P`.

## 12. Review of delegated phase-ratio experiment

A delegated implementation also produced `evaluate_m2_b2_phase_ratio_v1.R` and `artifacts/m2-v2-b2-phase-ratio-v1/`. Its posterior-weighted historical-shape ratio forecasts improve persistence across several development gate/lookback settings, particularly at +2.

Those results are **exploratory only** and are not used for the B2 promotion decision here because:

- the gate/lookback candidate family was informed by the same 11-season development set;
- candidate choice was not nested inside each outer fold;
- its provisional epidemic ledger differs from the candidate-independent all-origin B0/B1 ledger used above.

The strict nested `m2-v2-b-phase-nested-selected-v1` result therefore supersedes the phase-ratio experiment for model-selection claims. The phase-ratio construction remains a useful future C1/C2/C3 candidate because it directly propagates the B timing posterior through historical shape drift.
