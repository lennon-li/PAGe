# Run a complete nested LOSO fold

Orchestrates the five steps for a single held-out season: build fold -\>
M1 train -\> M2 train -\> M1 test -\> M2 eval. Returns aggregated
results; handles errors gracefully.

## Usage

``` r
nested_loso_run_fold(
  allD,
  test_season,
  params,
  spec,
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
  slope_weight = 8,
  slope_window = 6L,
  dynamic_temp = FALSE,
  dynamic_temp_pivot = 10L,
  top_k = NULL,
  blend_alpha = 1,
  method = "REML",
  parallel = TRUE,
  skip_m1 = FALSE,
  verbose = TRUE
)
```

## Arguments

- allD:

  Full multi-season data frame.

- test_season:

  Character scalar - the held-out season.

- params:

  M0 detection parameters.

- spec:

  M2 hyperparameter spec object.

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

- parallel:

  Logical; parallelize M1 walk-forward (default TRUE).

- skip_m1:

  Logical; reuse supplied M1 predictions when supported.

- verbose:

  Logical; print progress.

## Value

A named list:

- scores:

  One-row tibble of metrics.

- predictions:

  Tibble of per-observation predictions.

- m1_preds:

  M1 test-season predictions tibble.

- fold:

  The fold object from
  [`nested_loso_build_fold()`](https://lennon-li.github.io/PAGe/reference/nested_loso_build_fold.md).
