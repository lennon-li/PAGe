# Prospective alignment and peak detection for one season

Production-ready function called once per week with updated season data.
Performs real-time ignition detection, alignment, forecast, and peak
passage detection, returning the current state of the season.

## Usage

``` r
run_alignment_prospective(
  currentSeason,
  ref,
  hyper,
  params = NULL,
  ign_out = NULL,
  use_ci = TRUE,
  buffer_weeks = 0L,
  allow_scale = NULL,
  level = 0.95,
  min_obs = 4L,
  cal = NULL,
  curvature_ratio = 1,
  time_weights = NULL,
  trough_weight = 0.1,
  rise_weight = 1,
  peak_decay = 0.3
)
```

## Arguments

- currentSeason:

  Data frame for the ongoing season up to the current `weekF`. Must have
  columns `weekF`, `y`, and either `N` or `neg`.

- ref:

  Output from
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md)
  (pre-computed from training data).

- hyper:

  Output from
  [`learn_alignment_hyperparams()`](https://lennon-li.github.io/PAGe/reference/learn_alignment_hyperparams.md)
  (pre-computed from training data).

- params:

  Named list of Stage-1 detector threshold parameters. Only used if
  `ign_out` is `NULL`. One of `params` or `ign_out` must be supplied.

- ign_out:

  Pre-computed output from
  [`run_ignition_weekly()`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly.md).
  If `NULL` (default), runs ignition detection internally using
  `params`.

- use_ci:

  Logical; if `TRUE` (default), the peak is declared passed once the
  last observed `newWeek` exceeds the upper CI bound for the peak. If
  `FALSE`, uses the point estimate only.

- buffer_weeks:

  Integer. Additional weeks beyond the peak threshold required before
  declaring the peak passed (default `0L`).

- allow_scale:

  Logical or `NULL`. If `NULL` (default), scale identifiability is
  determined automatically via
  [`check_scale_identifiability()`](https://lennon-li.github.io/PAGe/reference/check_scale_identifiability.md).

- level:

  Numeric. Confidence level for prediction intervals (default `0.95`).

- min_obs:

  Integer. Minimum number of rows in `currentSeason` required before
  attempting alignment (default `4L`).

- cal:

  Optional peak-calibration object.

- curvature_ratio:

  Numeric coefficient for activating dilation.

- time_weights:

  Optional observation weights.

- trough_weight, rise_weight, peak_decay:

  Alignment-loss controls.

## Value

A named list with components:

- state:

  Character: `"pre_ignition"` (ignition not yet locked), `"aligning"`
  (ignition locked, actively forecasting), or `"post_peak"` (peak
  detected, alignment can stop).

- iWeek_hat:

  Integer. Estimated ignition week in original `weekF` space (`NA` if
  pre-ignition).

- ign_week_locked:

  Integer. First `weekF` where ignition was confirmed (`NA` if
  pre-ignition).

- tau:

  Numeric. Time-shift alignment parameter.

- delta:

  Numeric. Scale (dilation) alignment parameter.

- a:

  Numeric. Lower asymptote.

- b:

  Numeric. Upper asymptote.

- allow_scale:

  Logical. Whether scale fitting was enabled.

- delta_on:

  Logical. Whether dilation was active.

- t_peak:

  Numeric. Estimated peak in `newWeek` space.

- t_peak_ci:

  Numeric length-2. 95% CI for the peak in `newWeek` space.

- peak_weekF:

  Integer. Estimated peak in original `weekF` space.

- peak_weekF_lo:

  Integer. Lower CI bound of peak in `weekF` space.

- peak_weekF_hi:

  Integer. Upper CI bound of peak in `weekF` space.

- peak_passed:

  Logical. `TRUE` if the peak is considered to have passed.

- fallback_reason:

  Character or `NA`. Reason for a partial fallback in the alignment, if
  any.

- forecast_df:

  Tibble. Prediction data frame from
  [`align_forecast_pipeline_dilate()`](https://lennon-li.github.io/PAGe/reference/align_forecast_pipeline_dilate.md)
  (`NULL` if pre-ignition).

- ign_out:

  List. Full output from
  [`run_ignition_weekly()`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly.md).

## Examples

``` r
if (FALSE) { # \dontrun{
ref    <- readRDS("data/ref.rds")
hyper  <- readRDS("data/hyper.rds")
params <- readRDS("data/stage1_tuning.rds")$best_params

# Called once per week as new data arrives
ap <- run_alignment_prospective(
  currentSeason = current_data,
  ref           = ref,
  hyper         = hyper,
  params        = params
)
ap$state       # "pre_ignition", "aligning", or "post_peak"
ap$peak_weekF  # estimated peak in original week space

# Pass previous ign_out to avoid re-running ignition each week
ap2 <- run_alignment_prospective(
  currentSeason = current_data_next_week,
  ref           = ref,
  hyper         = hyper,
  params        = NULL,
  ign_out       = ap$ign_out
)
} # }
```
