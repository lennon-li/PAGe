# V3 M1-B1 implementation plan

Date: 2026-09-25
Status: REJECTED / DO NOT IMPLEMENT. Independent audit found the additive A-to-B lag-convolution assumption unsupported by the historical geometry, and the corresponding A-conditioned branch had already been tested and stopped. Retained only as an audit record. See `docs/v3-m1-b1-a-conditioned-review-2026-09-25.md`.

## Objective

Build the first joint-information timing challenger for Influenza B:

- `M1-B0`: B-only raw M1-v2 posterior mechanics (already benchmarked)
- `M1-B1`: the same B likelihood/library, augmented by strictly causal A timing context

The purpose is to answer one question before any M2 work:

> Does causal A timing information improve B peak timing beyond B-only M1, under strict chronological expanding-window replay?

M1-A remains frozen M1-v2 machinery and is not replaced by this work.

## Constraints

1. Frozen v2 package code is read-only.
2. No B ignition labels are used as supervised truth; the transferred B rule remains only an activity/activation marker.
3. B peak truth is the supervised timing target.
4. 2018-19 remains an explicit no-meaningful-B-peak season and is excluded from B peak-timing scoring.
5. Every test season is trained only on strictly earlier seasons.
6. Every origin uses only A/B observations available through that origin.
7. No future A/B data, retrospective peak truth, or completed-season normalization enters runtime features.
8. The first M1-B1 candidate must be low-dimensional and auditable.

## Baseline to preserve

Existing benchmark:

`artifacts/v3-m1-chronological-baselines-v1/`

B-only raw benchmark headline:

- season-balanced MAE ~1.87 weeks
- early-weighted MAE ~1.84 weeks
- 2022-23 is the dominant failure case (~5.25 weeks)

All M1-B1 folds, origins, truth, scoring, and B-library construction must be identical to M1-B0 so the comparison is paired.

## Candidate design

### Core B likelihood

Reuse frozen functions without modification:

- `fit_m1_v2_library()`
- `m1_v2_peak_posterior()`

For each test origin, obtain the B-only candidate peak posterior on the existing candidate grid.

### Causal A context

At the same test origin, compute an A peak posterior using the fold-specific A library and frozen M1-v2 mechanics.

Allowed A-derived runtime summaries:

- posterior mean/median/MAP A peak week
- probability A peak has passed by the current origin
- probability A peak occurs within 1, 2, or 3 weeks of the current origin
- posterior spread / uncertainty
- causal observed A decline indicators already available through the origin

No A retrospective peak truth may be used at test time.

### Historical A-to-B lag prior

Inside each chronological training fold only, estimate the empirical distribution of:

`B_peak_weekF - A_peak_weekF`

using completed prior seasons with meaningful B peaks.

Keep this prior deliberately simple:

- robust center: median lag
- robust scale: MAD with a fixed lower bound to avoid degeneracy
- optional leave-one-season-out sensitivity inside training data only

Do not fit a regression with multiple covariates in this first candidate.

### A-conditioned prior over B candidate peaks

For B candidate peak `T_B`, combine the current-origin A posterior with the training-fold lag distribution:

`p_Acond(T_B) = integral p_A(T_A | data_A<=t) * p_train(T_B - T_A) dT_A`

This is a convolution of the A peak posterior with the historical A-to-B lag prior.

Then combine with the B-only posterior by a single pre-specified tempering strength:

`p_B1(T_B) proportional to p_B0(T_B) * p_Acond(T_B)^alpha`

Initial candidate strengths must be a tiny fixed grid, for example:

- `alpha = 0` (exact B0 baseline)
- `alpha = 0.25`
- `alpha = 0.5`
- `alpha = 1.0`

`alpha` must be selected inside each chronological training fold only. The outer test season is never used to choose alpha.

If training data are insufficient to identify a stable lag prior, automatically fall back to `alpha=0`.

## Inner selection of alpha

For each outer chronological test season:

1. Consider only strictly earlier seasons.
2. Build inner chronological pseudo-test folds from those earlier seasons.
3. Require the same minimum prior-season count used by the outer benchmark where possible.
4. Evaluate alpha candidates with season-balanced early-weighted MAE.
5. Tie-break toward smaller alpha.
6. Freeze selected alpha before generating any prediction for the outer test season.

This avoids choosing A-conditioning strength from the outer test result.

## Fallback behavior

M1-B1 falls back exactly to M1-B0 when:

- A posterior cannot be constructed at the B origin;
- fewer than 3 training seasons have meaningful paired A/B peaks for lag estimation;
- lag scale is invalid after robust lower-bound handling;
- the selected alpha is zero;
- numerical normalization fails.

Every fallback reason is logged.

## Leakage protections

Required automated tests:

1. **Future perturbation:** modifying A or B weeks after origin `t` leaves the M1-B1 posterior at `t` unchanged.
2. **A-truth perturbation:** modifying held-out A retrospective peak truth does not change test-origin M1-B1 predictions.
3. **B-truth perturbation:** modifying held-out B retrospective peak truth changes scoring only, never predictions.
4. **Fold isolation:** all lag-prior seasons and alpha-selection seasons are strictly earlier than the outer test season.
5. **Baseline identity:** `alpha=0` reproduces M1-B0 posterior summaries exactly to numerical tolerance.
6. **No-event separation:** 2018-19 may inform chronology but must not be forced into B peak-timing training/scoring as a finite B peak target.

## Outputs

Write a separate artifact tree:

`artifacts/v3-m1-b1-a-conditioned-v1/`

Required files:

- `outer_fold_ledger.csv`
- `inner_alpha_selection.csv`
- `lag_prior_by_outer_fold.csv`
- `per_origin_predictions.csv`
- `paired_origin_comparison_vs_B0.csv`
- `per_season_metrics.csv`
- `summary_metrics.csv`
- `future_perturbation_checks.csv`
- `truth_perturbation_checks.csv`
- `source_manifest.csv`
- `benchmark_config.csv`

## Promotion decision

M1-B1 is not promoted merely for better pooled MAE.

Evidence required before proceeding to M2-B timing integration:

- lower season-balanced early-weighted MAE than M1-B0;
- no unacceptable new worst-season degradation;
- improvement is not entirely due to one season;
- outer-fold alpha selection is stable/interpretable;
- all leakage tests pass;
- fallback behavior is deterministic and auditable.

If M1-B1 does not beat B0 robustly, stop and retain B-only M1-B0. Do not escalate automatically to a more complex shared latent-phase model.
