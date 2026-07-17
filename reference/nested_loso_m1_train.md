# Run M1 walk-forward predictions on training seasons

Generates M1 stacking features for all training seasons in a fold. Calls
[`m1_walkforward_multi()`](https://lennon-li.github.io/PAGe/reference/m1_walkforward_multi.md)
using the fold's reference curve and hyperparams.

## Usage

``` r
nested_loso_m1_train(
  allD,
  fold,
  params,
  horizons = c(1L, 2L),
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
  parallel = TRUE,
  verbose = TRUE
)
```

## Arguments

- allD:

  Full multi-season data frame.

- fold:

  Output of
  [`nested_loso_build_fold()`](https://lennon-li.github.io/PAGe/reference/nested_loso_build_fold.md).

- params:

  M0 detection parameters.

- horizons:

  Integer vector of forecast horizons (default `c(1L, 2L)`).

- allow_scale:

  Passed to
  [`m1_walkforward_multi()`](https://lennon-li.github.io/PAGe/reference/m1_walkforward_multi.md).

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

- parallel:

  Logical; run M1 seasons in parallel (default TRUE).

- verbose:

  Logical; print progress.

## Value

Tibble of M1 walk-forward predictions for training seasons (columns:
season, eval_weekF, target_weekF, h, m1_p_hat, ...). Can be empty if no
ignition detected.
