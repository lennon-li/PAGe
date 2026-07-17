# Multi-template ensemble alignment and forecast

Aligns observed data to each training season's curve (from `eta_mat`
returned by `estimateRef(method = "fs")`), then ensembles the forecasts
weighted by alignment NLL via softmax.

## Usage

``` r
align_multi_template(
  currentD,
  eta_mat,
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
  temperature = 1,
  top_k = NULL,
  blend_alpha = 1,
  time_weights = NULL,
  trough_weight = 0.1,
  rise_weight = 1,
  peak_decay = 0.3,
  slope_weight = 1,
  slope_window = 6L,
  dynamic_temp = TRUE,
  dynamic_temp_pivot = 10L,
  gam_obj = NULL
)
```

## Arguments

- currentD:

  tibble/data.frame with `newWeek`, `y`, `neg`.

- eta_mat:

  Numeric matrix (`n_weeks` x `n_seasons`) of logit-scale per-season
  predictions from `estimateRef(method = "fs")`.

- g_ref_fun:

  Population reference curve function (logit scale). Used as the
  blending anchor when `blend_alpha < 1`.

- g_ref_mu_se:

  Population reference uncertainty function (fallback).

- hyper:

  List of alignment hyperparameters (TAU_BOUNDS, etc.).

- allow_scale:

  Logical or NULL. Passed through.

- use_weights:

  Logical; use `y + neg` as binomial weights.

- level:

  CI level (default 0.95).

- future_weeks:

  Numeric vector of future newWeek values.

- include_observed:

  Logical; include observed block in pred_df.

- fallback_when_unstable:

  Logical; refit with delta=0 if unstable.

- curvature_ratio:

  Numeric; delta gate coefficient.

- temperature:

  Numeric; softmax temperature for NLL weighting (default 1.0). Lower =
  more peaked (winner-take-all).

- top_k:

  Integer or NULL. If not NULL, pre-filter to top-K templates ranked by
  Spearman correlation with observed data.

- blend_alpha:

  Numeric 0–1. Blend each per-season template toward the population
  reference: `g_blend = (1-alpha)*g_ref + alpha*g_s`. Default 1.0 (pure
  per-season curve).

- time_weights:

  Numeric vector or NULL; pre-computed time weights.

- trough_weight:

  Numeric; alignment loss trough weight.

- rise_weight:

  Numeric; alignment loss rise weight.

- peak_decay:

  Numeric; exponential decay after peak.

- slope_weight:

  Numeric; strength of growth-rate-aware template weighting (default
  0.5). Higher values make templates with similar recent slope to
  observed data receive more weight. Set to 0 to disable.

- slope_window:

  Integer; number of recent weeks to compute slope over (default 4).

- dynamic_temp:

  Logical; if TRUE (default), scale temperature up when few observations
  available (wider ensemble early, sharper late).

- dynamic_temp_pivot:

  Integer; observation count below which temperature is inflated
  (default 10). Temperature is scaled by `pivot / n_obs` when
  `n_obs < pivot`.

- gam_obj:

  Optional fitted GAM used to estimate per-template uncertainty.

## Value

List with the same structure as
[`align_forecast_pipeline_dilate()`](https://lennon-li.github.io/PAGe/reference/align_forecast_pipeline_dilate.md)
output, plus:

- per_template:

  List of per-template alignment results.

- weights:

  Named numeric vector of softmax ensemble weights.

- template_names:

  Character vector of template season labels.
