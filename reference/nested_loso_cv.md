# Nested M1 -\> M2 leave-one-season-out cross-validation

For each held-out test season, builds a leakage-free reference curve on
training seasons, runs M1 walk-forward to generate stacking features,
trains M2, and evaluates on the test season. This is the composable
replacement for `loso_m1_m2_joint()` in `pipeline_bridge.R`.

## Usage

``` r
nested_loso_cv(
  allD,
  params,
  spec,
  test_seasons = NULL,
  exclude_seasons = NULL,
  horizons = c(1L, 2L),
  eval_window = 12L,
  k_deriv = 10L,
  k_ref = 25L,
  n_weeks = 52L,
  ref_method = "fs",
  manual_labels = NULL,
  flag_args = list(p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L, min_window =
    10L, w_min = 21L, w_max = 21L, d2_relax = -0.01),
  allow_scale = NULL,
  use_ci = TRUE,
  buffer_weeks = 0L,
  min_obs = 4L,
  curvature_ratio = 1,
  temperature = 0.25,
  rise_weight = 1,
  trough_weight = 0.1,
  peak_decay = 0.3,
  slope_weight = 0.5,
  slope_window = 4L,
  dynamic_temp = TRUE,
  dynamic_temp_pivot = 10L,
  top_k = NULL,
  blend_alpha = 1,
  method = "REML",
  n_cores = parallel::detectCores() - 1L,
  skip_m1 = FALSE,
  verbose = TRUE
)
```

## Arguments

- allD:

  Data frame with all seasons.

- params:

  M0 detection parameters.

- spec:

  M2 hyperparameter spec object.

- test_seasons:

  Character vector of seasons to hold out. If `NULL`, every season is
  tested.

- exclude_seasons:

  Character vector of seasons to exclude entirely.

- horizons:

  Integer vector of forecast horizons (default `c(1L, 2L)`).

- eval_window:

  Integer; max weeks post-ignition (default 12L).

- k_deriv:

  Integer; basis dim for derivatives (default 10L).

- k_ref:

  Integer; basis dim for reference curve (default 10L).

- n_weeks:

  Integer; reference curve period (default 52L).

- ref_method:

  Reference-curve method passed to
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md).

- manual_labels:

  Optional manual ignition labels.

- flag_args:

  Named list forwarded to
  [`flagIgnition()`](https://lennon-li.github.io/PAGe/reference/flagIgnition.md).

- allow_scale:

  Passed to M1 walk-forward.

- use_ci:

  Logical; peak CI control (default TRUE).

- buffer_weeks:

  Integer; peak buffer (default 0L).

- min_obs:

  Integer; minimum rows for alignment (default 4L).

- curvature_ratio:

  Numeric; delta curvature gate (default 1.0).

- temperature, rise_weight, trough_weight, peak_decay:

  Ensemble and alignment-loss controls.

- slope_weight, slope_window:

  Growth-rate similarity controls.

- dynamic_temp, dynamic_temp_pivot:

  Early-season temperature controls.

- top_k, blend_alpha:

  Template filtering and blending controls.

- method:

  GAM fitting method (default `"REML"`).

- n_cores:

  Integer; number of worker cores for M1 parallelism (default
  `parallel::detectCores() - 1L`).

- skip_m1:

  Logical; reuse supplied M1 predictions when supported.

- verbose:

  Logical; print progress.

## Value

A named list (same structure as `loso_m1_m2_joint()`):

- scores:

  Tibble with one row per test season: season, n, mean_nll, brier,
  rmse_p.

- predictions:

  Tibble of all per-observation predictions across test seasons.

- m1_preds:

  Named list of M1 test predictions per season.

- folds:

  Named list of fold objects for diagnostics.
