# Walk-forward alignment evaluation with LOSO reference curves

For each test season (LOSO by default):

1.  Runs
    [`estimateDerivs()`](https://lennon-li.github.io/PAGe/reference/estimateDerivs.md) +
    [`flagIgnition()`](https://lennon-li.github.io/PAGe/reference/flagIgnition.md) +
    [`alignIgnition()`](https://lennon-li.github.io/PAGe/reference/alignIgnition.md)
    on the training seasons to build an aligned training dataset.

2.  Fits the reference curve with
    [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md)
    on the training aligned data.

3.  Runs
    [`run_ignition_weekly()`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly.md)
    prospectively on the raw test-season data to simulate real-time
    ignition detection.

4.  Walks forward from `walk_start` to `walk_end`: once ignition locks
    at `iWeek_hat`, re-anchors data as
    `newWeek = weekF - iWeek_hat + anchorWeek` and produces alignment +
    forecast at each step.

## Usage

``` r
loso_walkforward(
  allD,
  params,
  walk_start = NULL,
  walk_end = NULL,
  manual_labels = NULL,
  train_seasons = NULL,
  test_seasons = NULL,
  exclude_seasons = NULL,
  k_deriv = 10L,
  k_ref = 10L,
  n_weeks = 52L,
  flag_args = list(p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L, min_window =
    10L, w_min = 21L, w_max = 21L, d2_relax = -0.01),
  allow_scale = NULL,
  level = 0.95,
  use_ci = TRUE,
  buffer_weeks = 0L,
  n_cores = parallel::detectCores() - 1L,
  min_obs = 4L,
  curvature_ratio = 1,
  template_shift = 0L,
  peak_weight_boost = 1,
  peak_weight_decay = 0.3,
  align_trough_weight = 0.1,
  align_rise_weight = 1,
  align_peak_decay = 0.3,
  use_multi_template = TRUE,
  ref_method = "fs",
  multi_temperature = 0.25,
  multi_top_k = NULL,
  multi_blend_alpha = 1,
  slope_weight = 8,
  slope_window = 6L,
  dynamic_temp = FALSE,
  dynamic_temp_pivot = 10L,
  checkpoint_file = NULL,
  verbose = TRUE
)
```

## Arguments

- allD:

  Raw data frame (one row per season-week) with at least `season`,
  `weekF`, `y`, `N` (or `neg`), `p`.

- params:

  Named list of Stage-1 detector threshold parameters passed to
  [`run_ignition_weekly()`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly.md)
  (e.g. `stage1_tuning.rds$best_params`).

- walk_start:

  Integer or `NULL`. First `weekF` at which to produce a forecast.
  `NULL` (default) starts at the ignition-lock week.

- walk_end:

  Integer or `NULL`. Last `weekF` at which to evaluate. `NULL` (default)
  uses the last observed week of the season.

- manual_labels:

  Named integer vector mapping season labels to verified ignition
  `weekF` values, passed to
  [`flagIgnition()`](https://lennon-li.github.io/PAGe/reference/flagIgnition.md)
  for training seasons. `NULL` forces algorithmic detection.

- train_seasons:

  Character vector of training season labels. `NULL` (default) uses all
  seasons except the test season (LOSO).

- test_seasons:

  Character vector of test season labels. `NULL` (default) evaluates all
  seasons.

- exclude_seasons:

  Character vector of season labels to exclude from both training and
  testing. Useful for known outlier seasons (e.g. `"2015-16"`). `NULL`
  (default) excludes nothing.

- k_deriv:

  Basis dimension passed to
  [`estimateDerivs()`](https://lennon-li.github.io/PAGe/reference/estimateDerivs.md)
  (default 10).

- k_ref:

  Basis dimension passed to
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md)
  (default 10).

- n_weeks:

  Integer. Template domain length for
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md)
  (default 52).

- flag_args:

  Named list of additional arguments forwarded to
  [`flagIgnition()`](https://lennon-li.github.io/PAGe/reference/flagIgnition.md)
  (excluding `df` and `manual_labels`).

- allow_scale:

  Logical or `NULL`. Passed to
  [`check_scale_identifiability()`](https://lennon-li.github.io/PAGe/reference/check_scale_identifiability.md).
  `NULL` auto-detects per fold.

- level:

  Numeric. CI level for forecast intervals (default 0.95).

- use_ci:

  Logical. Forwarded to
  [`run_alignment_prospective()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective.md).
  If `TRUE` (default), the peak is declared passed once the last
  observed `newWeek` exceeds the upper CI bound.

- buffer_weeks:

  Integer. Forwarded to
  [`run_alignment_prospective()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective.md).
  Additional weeks beyond the threshold before declaring the peak passed
  (default `0L`).

- n_cores:

  Integer. Parallel workers for the eval_weeks loop per season. Defaults
  to `parallel::detectCores() - 1`. Set to 1 to disable.

- min_obs:

  Integer. Minimum observations after ignition before attempting
  alignment (default 4).

- curvature_ratio:

  Numeric coefficient for activating dilation.

- template_shift:

  Integer shift applied to template coordinates.

- peak_weight_boost:

  Numeric \>= 1. Multiplicative weight for observations between ignition
  and peak in
  [`estimateDerivs()`](https://lennon-li.github.io/PAGe/reference/estimateDerivs.md)
  (default 1 = no boost).

- peak_weight_decay:

  Numeric \> 0. Exponential decay rate for weights after the observed
  peak (default 0.3).

- align_trough_weight, align_rise_weight, align_peak_decay:

  Numeric alignment-loss weights for epidemic regions.

- use_multi_template:

  Logical; use the multi-template ensemble.

- ref_method:

  Reference-curve method passed to
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md).

- multi_temperature, multi_top_k, multi_blend_alpha:

  Ensemble controls.

- slope_weight, slope_window:

  Growth-rate similarity controls.

- dynamic_temp, dynamic_temp_pivot:

  Early-season temperature controls.

- checkpoint_file:

  Character path (or `NULL`). If provided, saves incremental results to
  this RDS file after each test season completes. On restart, completed
  seasons are loaded from the checkpoint and skipped. Delete the file to
  force a full rerun.

- verbose:

  Logical. Print per-season progress (default `TRUE`).

## Value

A list with three elements:

- params_df:

  Tibble with one row per (season, eval_week). Columns: `season`,
  `eval_week`, `n_obs`, `iWeek_hat`, `iWeek_true`, `tau`, `delta`, `a`,
  `b`, `allow_scale`, `delta_on`, `t_peak`, `t_peak_lo`, `t_peak_hi`,
  `peak_weekF`, `peak_passed`, `fallback_reason`, `n_train`,
  `anchorWeek`.

- forecast_df:

  Tibble with one row per (season, eval_week, newWeek). Columns:
  `season`, `eval_week`, `newWeek`, `p_hat`, `p_lo`, `p_hi`, `kind`.

- ref_list:

  Named list of
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md)
  outputs, one per test season.

## Examples

``` r
if (FALSE) { # \dontrun{
tuned <- readRDS("data/stage1_tuning.rds")
wf <- loso_walkforward(
  allD          = allD,
  params        = tuned$best_params,
  walk_start    = 10,
  walk_end      = 30,
  manual_labels = c("2017-18" = 20L, "2018-19" = 19L),
  test_seasons  = "2017-18"
)
} # }
```
