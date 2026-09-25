# M1-v2 calibration checkpoint — 2026-09-23

## Benchmark objective

Calibration work is evaluated primarily against the frozen M1-v1 active metric formula:

`primary_prepeak_integer_mae_season_balanced_early_weighted`

The immutable historical benchmark remains 1.1561215766545 on the old observed-argmax truth. M1-v2 does not beat that immutable target because the redesigned model targets a different latent peak truth.

For model development, both v1 and v2 are additionally compared with the same v1 metric formula against the current k=8 retrospective GAM peak truth.

## Calibration experiments

The uncalibrated 11-season current replay scores:

- active integer metric: 1.5288;
- native decimal metric: 1.3495.

### Feature calibration

A fully nested feature-calibration experiment considered only causal forecast-time features:

- elapsed weeks since M0;
- posterior 90% width;
- posterior skew proxy;
- current positivity;
- post-M0 running maximum positivity;
- current/runmax ratio;
- log running maximum as an amplitude proxy.

Calibration-model choice itself was nested by inner leave-one-season-out selection using the active v1 integer metric.

Result:

- nested scalar bias: 1.3732 active integer / 1.2462 native decimal;
- nested feature-selected: 1.4835 active integer / 1.2741 native decimal.

The feature selector overfit the very small inner calibration sample, often selecting a four-feature model. No causal feature model improved the active benchmark over the scalar correction.

Fixed-model outer-fold diagnostics likewise favored the intercept-only model for the active integer metric:

- intercept: 1.3732;
- width: 1.4344;
- elapsed: 1.4417;
- elapsed + width + runmax: 1.4357;
- larger feature models: worse.

Elapsed-only calibration improved native decimal error to 1.2195 but worsened the active integer benchmark, so it is not the preferred benchmark-aligned calibrator.

### Full-window calibration

A second strict nested experiment learned calibration from all inner primary origins with the same v1 early weights rather than only the first four origins.

Result:

- full-window intercept: 1.4078 active integer / 1.2537 native decimal;
- full-window elapsed: 1.4377 active integer / 1.2335 native decimal.

Both are worse on the active metric than the first-four-origin scalar correction.

Conclusion: the first-four-origin season-balanced mean signed bias is the preferred small calibrator.

## Preferred calibrator

For each outer historical training set:

1. For each inner season, fit M1-v2 on all other seasons.
2. Predict the first four primary origins beginning at that season's cross-fitted M0 integer activation origin.
3. Compute signed decimal peak error against the current retrospective GAM peak truth.
4. Apply the v1 early weight `exp(-(0.1 * elapsed_from_M0)^2)` within each season.
5. Normalize weights so every inner season contributes equal total mass.
6. Estimate one mean signed bias.
7. Runtime reporting offset = negative of that mean bias.

On the 11-season current replay this gives:

- uncalibrated active integer metric: 1.5288;
- nested scalar calibrated: 1.3732;
- uncalibrated native decimal: 1.3495;
- nested scalar calibrated native decimal: 1.2462.

On the same 92 legacy origins, when both models are judged against current GAM peak truth:

- frozen v1 predictions: 1.3403 active integer metric;
- nested-calibrated M1-v2: 1.3044.

Thus M1-v2 modestly beats v1 under the v1 metric formula when both are judged against the redesigned scientific target.

## Package implementation

Added to `PAGe/R/m1_v2.R`:

- `fit_m1_v2_bias_calibrator()`
- `m1_v2_apply_bias_calibration()`

The calibrator is bound by hash to the exact M1 historical library. It requires a historical activation table with one cross-fitted/causal M0 activation per training season:

- `season`;
- `activation_origin_week`;
- `activation_week_decimal`.

The calibrator does not generate M0 values and refuses data/truth that do not match the historical library.

Application is deliberately a reporting-location correction only:

- raw M1 posterior probabilities are unchanged;
- M1-C passage probabilities are unchanged;
- calibrated mean/median/MAP/q05/q95 are exposed separately;
- interval width is unchanged;
- a flag indicates whether the calibrated mean remains future of the release boundary.

This separation prevents a benchmark calibration step from being misrepresented as an independent posterior update.

## Verification

Focused M1-v2 tests now pass 31/31.

A real held-out 2025-26 smoke test trained the library and calibrator on the other ten seasons. The package learned:

- mean signed inner bias: +0.8365458 weeks;
- calibration offset: -0.8365458 weeks.

This exactly matches the independently generated nested replay artifact for outer holdout 2025-26.

At 2025-26 origin 21:

- raw M1 peak mean: 25.51;
- calibrated peak mean: 24.68;
- raw 90% interval: 24.25–27.25;
- calibrated reporting interval: 23.41–26.41;
- passage posterior remains separate and unchanged.

## Decision

Freeze calibration complexity here for M1-v2. Do not add feature-based calibration, more PCs, or AUC predictors unless a future governed experiment provides materially new evidence.

Next engineering work should replay all outer folds through the packaged calibrator API, integrate the calibrator into the governed M1 training artifact, and expose raw versus calibrated timing outputs explicitly to downstream M2.

## Full package-API replay

The complete 11-season outer LOSO replay was rerun using only the packaged APIs:

- `fit_m1_v2_library()`;
- `fit_m1_v2_bias_calibrator()`;
- `m1_v2_peak_posterior()`;
- `m1_v2_apply_bias_calibration()`.

This reproduced the exploratory nested results exactly:

- raw active integer metric: **1.52883**;
- calibrated active integer metric: **1.37325**;
- raw native decimal metric: **1.34945**;
- calibrated native decimal metric: **1.24615**.

All 11 outer-fold calibration offsets matched the previously generated nested artifacts to numerical precision.

Near peak, a location correction can move the calibrated mean behind the release boundary even while the raw future-conditioned M1-F posterior is still active. This is expected from a reporting calibration and is why `m1_v2_apply_bias_calibration()` exposes `calibrated_mean_is_future`. M1-C passage state remains authoritative; calibration does not alter passage probabilities or stopping logic.
