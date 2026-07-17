# Run M1 walk-forward for one season and collect predictions at target weeks

For each evaluation week, runs
[`run_alignment_prospective()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective.md)
and extracts M1's template-based prediction at each forecast target week
(weekF + h). Returns a tidy tibble suitable for joining to M2 training
data.

## Usage

``` r
m1_walkforward_predictions(
  seasonD,
  ref,
  hyper,
  ign_out = NULL,
  params = NULL,
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
  blend_alpha = 1
)
```

## Arguments

- seasonD:

  Data frame for ONE season (all weeks). Must have columns `weekF`, `y`,
  and either `N` or `neg`.

- ref:

  Output from
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md)
  (pre-computed from training data).

- hyper:

  Output from
  [`learn_alignment_hyperparams()`](https://lennon-li.github.io/PAGe/reference/learn_alignment_hyperparams.md).

- ign_out:

  Pre-computed output from
  [`run_ignition_weekly()`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly.md).
  If NULL, must supply `params` to run M0 internally.

- params:

  M0 detection params. Used only if `ign_out` is NULL.

- horizons:

  Integer vector of forecast horizons (default `c(1L, 2L)`).

- eval_weeks:

  Optional integer vector of weekF values to evaluate at. If NULL,
  evaluates from ignition lock through end of season.

- allow_scale:

  Passed to
  [`run_alignment_prospective()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective.md).

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

## Value

A tibble with columns:

- season:

  Season label

- eval_weekF:

  The weekF at which M1 was run (data up to this week)

- target_weekF:

  The weekF for which M1 predicts (eval_weekF + h)

- h:

  Forecast horizon (1 or 2)

- m1_p_hat:

  M1's predicted positivity at target week

- m1_p_lo:

  M1's lower PI at target week

- m1_p_hi:

  M1's upper PI at target week

- m1_tau:

  M1's shift parameter at eval_weekF

- m1_delta:

  M1's dilation parameter at eval_weekF

- m1_state:

  M1 state: "aligning" or "post_peak"
