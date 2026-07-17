# Internal: fit tau & delta for one season, given reference curve

Internal: fit tau & delta for one season, given reference curve

## Usage

``` r
fit_tau_delta(
  currentD,
  g_ref_fun,
  tau_bounds,
  delta_bounds,
  allow_scale = NULL,
  week_threshold_delta,
  lam_delta,
  use_weights = TRUE,
  curvature_ratio = 1,
  time_weights = NULL,
  trough_weight = 0.1,
  rise_weight = 1,
  peak_decay = 0.3
)
```
