# Align and forecast using dilated reference curve

Align and forecast using dilated reference curve

## Usage

``` r
align_forecast_pipeline_dilate(
  currentD,
  g_ref_fun,
  g_ref_mu_se,
  hyper,
  allow_scale = NULL,
  use_weights = TRUE,
  level = 0.95,
  future_weeks = NULL,
  include_observed = TRUE,
  fallback_when_unstable = TRUE,
  curvature_ratio = 1,
  time_weights = NULL,
  trough_weight = 0.1,
  rise_weight = 1,
  peak_decay = 0.3
)
```

## Arguments

- currentD:

  tibble/data.frame with at least newWeek, y, neg.

- g_ref_fun:

  spline-like reference function on link scale.

- g_ref_mu_se:

  function(u) returning list(mu, se) from GAM.

- hyper:

  list with TAU_BOUNDS, DELTA_BOUNDS, WEEK_THRESHOLD_DELTA,
  LAMBDA_DELTA.

- allow_scale:

  logical or NULL; passed to fit_tau_delta().

- use_weights:

  logical; use y + neg as binomial weights.

- level:

  CI level.

- future_weeks:

  optional vector of future newWeek values; if NULL, uses (last_obs +
  1):52.

- include_observed:

  logical; whether to include observed part in pred_df.

- fallback_when_unstable:

  logical; if TRUE, refit with delta=0 when 2D tau/delta profile
  covariance is unstable.

- curvature_ratio:

  Numeric; gate coefficient for delta activation.

- time_weights:

  Numeric vector or NULL; pre-computed time weights. If NULL and
  `rise_weight > 1`, weights are computed from the reference curve via
  [`compute_align_weights()`](https://lennon-li.github.io/PAGe/reference/compute_align_weights.md).

- trough_weight:

  Numeric; weight for pre-rising-limb weeks (default 0.1).

- rise_weight:

  Numeric; weight for ignition-to-peak weeks (default 1.0, i.e. no boost
  by default).

- peak_decay:

  Numeric; exponential decay rate after peak (default 0.3).

## Value

list with tau, delta, a, b, pred_df, peak, nll, etc.
