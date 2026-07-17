# Run M1 walk-forward for multiple seasons (parallelized)

Calls
[`m1_walkforward_predictions()`](https://lennon-li.github.io/PAGe/reference/m1_walkforward_predictions.md)
for each season, optionally in parallel via
[`furrr::future_map()`](https://furrr.futureverse.org/reference/future_map.html).

## Usage

``` r
m1_walkforward_multi(
  allD,
  ref,
  hyper,
  params,
  seasons = NULL,
  horizons = c(1L, 2L),
  eval_weeks = NULL,
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
  parallel = TRUE,
  verbose = TRUE
)
```

## Arguments

- allD:

  Multi-season data frame.

- ref:

  Output from
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md).

- hyper:

  Output from
  [`learn_alignment_hyperparams()`](https://lennon-li.github.io/PAGe/reference/learn_alignment_hyperparams.md).

- params:

  M0 detection params.

- seasons:

  Character vector of seasons to process.

- horizons:

  Forecast horizons (default `c(1L, 2L)`).

- eval_weeks:

  Optional; if NULL, determined per season from ignition.

- allow_scale:

  Passed through.

- use_ci:

  Passed through.

- buffer_weeks:

  Passed through.

- min_obs:

  Passed through.

- curvature_ratio:

  Passed through.

- temperature, rise_weight, trough_weight, peak_decay:

  Ensemble and alignment-loss controls passed through.

- slope_weight, slope_window:

  Growth-rate similarity controls.

- dynamic_temp, dynamic_temp_pivot:

  Early-season temperature controls.

- top_k, blend_alpha:

  Template filtering and blending controls.

- parallel:

  Logical; use parallel via furrr (default TRUE).

- verbose:

  Logical; print progress (default TRUE).

## Value

A tibble (stacked across seasons) with the same columns as
[`m1_walkforward_predictions()`](https://lennon-li.github.io/PAGe/reference/m1_walkforward_predictions.md).
