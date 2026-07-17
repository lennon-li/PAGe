# Learn tau/delta bounds and penalty from historical seasons

Fits \\(\tau, \delta)\\ for each historical season to empirically derive
the alignment search bounds (`TAU_BOUNDS`, `DELTA_BOUNDS`), the week at
which `delta` becomes estimable (`WEEK_THRESHOLD_DELTA`), and the ridge
penalty coefficient (`LAMBDA_DELTA`). Bounds are the empirical quantile
range (controlled by `robust_q`) plus a buffer. The penalty is
calibrated from the median curvature of the NLL surface with respect to
`delta`.

## Usage

``` r
learn_alignment_hyperparams(
  theD,
  g_ref_fun,
  tau_range_init = c(-12, 12),
  delta_range_init = c(-0.35, 0.35),
  robust_q = c(0.05, 0.95),
  buffer_tau = 1,
  buffer_delta = 0.05,
  obs_cuts = seq(12, 44, by = 4),
  rel_sd_target = 0.25,
  lambda_scale = 0.2,
  h_delta = 0.01
)
```

## Arguments

- theD:

  Data frame of aligned historical seasons with columns `season`,
  `newWeek`, `y`, and `neg`.

- g_ref_fun:

  Reference curve function on the logit scale.

- tau_range_init, delta_range_init:

  Numeric vectors of length 2; initial search bounds for the
  optimisation over historical seasons (defaults `c(-12, 12)` and
  `c(-0.35, 0.35)`).

- robust_q:

  Numeric vector of length 2; lower/upper quantile probabilities used to
  derive empirical bounds (default `c(0.05, 0.95)`).

- buffer_tau, buffer_delta:

  Numeric; extra margin added to each side of the empirical bounds
  (defaults 1.0 and 0.05).

- obs_cuts:

  Integer vector; observation-week cutoffs used to assess when `delta`
  stabilises (default `seq(12, 44, by = 4)`).

- rel_sd_target:

  Numeric; relative SD threshold below which `delta` is considered
  stable across seasons (default 0.25).

- lambda_scale:

  Numeric; fraction of the median NLL curvature used as `LAMBDA_DELTA`
  (default 0.20).

- h_delta:

  Numeric; step size for the NLL curvature finite difference (default
  0.01).

## Value

A list with `TAU_BOUNDS`, `DELTA_BOUNDS`, `WEEK_THRESHOLD_DELTA`,
`LAMBDA_DELTA`, `tau_delta_hist`, `delta_stability`,
`stability_summary`, and `curvature_Dpp`.
