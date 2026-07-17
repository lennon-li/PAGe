# Produce per-snapshot Stage-2 forecast series (h1/h2) on the target-week axis

Takes pseudo-prospective snapshots produced by
[`build_stage2_pseudo_prospective_list()`](https://lennon-li.github.io/PAGe/reference/build_stage2_pseudo_prospective_list.md)
and applies a fitted Stage-2 model to produce forecasts aligned to the
\*target\* week:

- `h1` predictions are placed at `weekF_target = weekF_origin + 1`

- `h2` predictions are placed at `weekF_target = weekF_origin + 2`

## Usage

``` r
stage2_predict_series(
  pp,
  stage2_fit,
  which = c("all", "latest"),
  horizons = c(1L, 2L),
  alpha_state = NULL,
  ref_col = "template_fit_shift",
  exclude_season_re = TRUE,
  interval = c("pi", "ci"),
  level = 0.95,
  pi_B = 2000L,
  pi_seed = 1L,
  date_step_days = 7L
)
```

## Arguments

- pp:

  Output of
  [`build_stage2_pseudo_prospective_list()`](https://lennon-li.github.io/PAGe/reference/build_stage2_pseudo_prospective_list.md)
  (list with `meta` and `df`) or a compatible list of snapshot
  data.frames.

- stage2_fit:

  A fitted mgcv `gam`/`bam` Stage-2 model.

- which:

  Which snapshots to process: `"all"` (default) or `"latest"`.

- horizons:

  Integer vector of horizons to include (default `c(1L,2L)` -\>
  `h1,h2`).

- alpha_state:

  Numeric in (0,1). If `z_ema` is missing, it is computed as an EWMA on
  the logit scale using this alpha. Defaults to `pp$meta$alpha_state` if
  present, else 0.3.

- ref_col:

  Character. Column name used as background reference curve (default
  `"template_fit_shift"`).

- exclude_season_re:

  Logical. If TRUE (default), excludes `s(season)` during prediction.

- interval:

  Interval type, prediction or confidence.

- level:

  Confidence level for intervals (default 0.95).

- pi_B:

  Number of prediction-interval simulations.

- pi_seed:

  Random seed for interval simulation.

- date_step_days:

  Integer days per week when imputing missing dates (default 7).

## Value

If `which="latest"`, returns a single data.frame. If `which="all"`,
returns a list of data.frames (one per snapshot) in the same order as
input snapshots.

## Details

The returned time series for each snapshot contains:

- `weekF`, `newWeek`, `date`

- `p_obs`: observed probability (masked beyond the as-of week)

- `p_true`: retrospective truth (if present in snapshots)

- `p_ref`: reference/template curve (from `ref_col`)

- `p_hat_h1`, `p_lo_h1`, `p_hi_h1`

- `p_hat_h2`, `p_lo_h2`, `p_hi_h2`

- `asof_weekF`: the as-of origin week for that snapshot

Uncertainty bands are computed as link-scale confidence intervals for
the mean, transformed back to the response scale via
[`plogis()`](https://rdrr.io/r/stats/Logistic.html).
