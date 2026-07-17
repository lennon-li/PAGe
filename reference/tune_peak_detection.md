# Tune peak detection parameters using pre-computed walk-forward results

Evaluates combinations of `use_ci` and `buffer_weeks` for peak passage
detection, using the `params_df` from
[`loso_walkforward()`](https://lennon-li.github.io/PAGe/reference/loso_walkforward.md).
No LOSO rerun is required — tuning runs in seconds.

## Usage

``` r
tune_peak_detection(
  params_df,
  allD,
  use_ci_grid = c(TRUE, FALSE),
  buffer_weeks_grid = -2:3
)
```

## Arguments

- params_df:

  Tibble from `loso_walkforward()$params_df`. Must have columns
  `season`, `eval_week`, `iWeek_hat`, `t_peak`, `t_peak_hi`,
  `anchorWeek`.

- allD:

  Raw data frame (one row per season-week) used to look up the true peak
  `weekF` per season. Must have columns `season`, `weekF`, `p`, `N`.

- use_ci_grid:

  Logical vector of `use_ci` values to evaluate (default
  `c(TRUE, FALSE)`).

- buffer_weeks_grid:

  Integer vector of `buffer_weeks` values to evaluate (default `-2:3`).

## Value

A tibble with one row per `(use_ci, buffer_weeks)` combination and
columns:

- use_ci:

  Logical. Whether upper CI was used for the threshold.

- buffer_weeks:

  Integer. Buffer added beyond the threshold.

- fp_rate:

  Numeric. Fraction of seasons with a false-positive detection (declared
  before true peak).

- mean_delay:

  Numeric. Mean detection delay (weeks after true peak) among seasons
  with no false positive.

- median_delay:

  Numeric. Median detection delay.

- max_delay:

  Numeric. Maximum detection delay.

- n_seasons:

  Integer. Total seasons evaluated.

## Details

For each grid point `(use_ci, buffer_weeks)`, the function simulates
detection at every `(season, eval_week)` row in `params_df`: the peak is
declared passed once the last observed `newWeek` meets
`threshold = t_peak_hi + buffer_weeks` (if `use_ci = TRUE`) or
`t_peak + buffer_weeks`. The first `eval_week` per season where
detection fires defines `detection_weekF`. Delay is computed as
`detection_weekF - true_peak_weekF` (positive = after peak, negative =
false positive).

## Examples

``` r
if (FALSE) { # \dontrun{
wf     <- readRDS("data/loso_wf_cache.rds")
allD   <- read.csv("data/flu_testing_data.csv") |>
  mutate(p = y / N, N = as.integer(N))
tuning <- tune_peak_detection(wf$params_df, allD)
# Pick smallest buffer_weeks with fp_rate == 0
tuning |> filter(fp_rate == 0) |> arrange(mean_delay)
} # }
```
