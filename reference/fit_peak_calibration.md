# Fit peak calibration model from LOSO walk-forward results

Trains a two-stage calibration on the `params_df` produced by
[`loso_walkforward()`](https://lennon-li.github.io/PAGe/reference/loso_walkforward.md):

1.  **Prior (for shrinkage):** learns the historical distribution of
    true peak timing in aligned `newWeek` space (\\\mu\\, \\\sigma\\).

2.  **Residual bias GAM:** after applying shrinkage, fits a smooth of
    the remaining prediction error as a function of weeks since
    ignition.

## Usage

``` r
fit_peak_calibration(
  params_df,
  allD,
  anchorWeek = 27L,
  level = 0.95,
  holdout_season = NULL
)
```

## Arguments

- params_df:

  Tibble from `loso_walkforward()$params_df`.

- allD:

  Raw data frame with columns `season`, `weekF`, `p`, `N` — used to
  determine the true peak week per season.

- anchorWeek:

  Integer. Alignment anchor week (default `27L`).

- level:

  Numeric. CI level used in `params_df` (default `0.95`).

- holdout_season:

  Character scalar or `NULL`. When non-`NULL`, rows for this season are
  excluded before computing the prior weights (\\\mu\\, \\\sigma\\) and
  before fitting `bias_gam`. Use this inside a LOSO loop to avoid data
  leakage from the held-out fold. When `NULL` (default), all seasons are
  used and behaviour is bit-for-bit identical to the pre-fix version.

## Value

A list with:

- mu_prior:

  Numeric. Prior mean of true peak in `newWeek` space.

- sigma_prior:

  Numeric. Prior SD of true peak in `newWeek` space.

- bias_gam:

  A [`mgcv::gam`](https://rdrr.io/pkg/mgcv/man/gam.html) object for
  residual bias correction.

- cal_df:

  Tibble. Training rows with raw and shrunk predictions, for
  diagnostics.

## Details

The returned object is passed to `run_alignment_prospective(cal = ...)`
to calibrate real-time peak estimates.

## Examples

``` r
if (FALSE) { # \dontrun{
wf  <- readRDS("data/loso_wf_cache.rds")
allD <- read.csv("data/flu_testing_data.csv") |>
  mutate(p = pos_flua / test_flu, N = test_flu)
cal <- fit_peak_calibration(wf$params_df, allD)
# LOSO-safe usage (exclude held-out season):
cal_fold <- fit_peak_calibration(wf$params_df, allD, holdout_season = "2022-23")
# Use in production:
ap  <- run_alignment_prospective(currentSeason, ref, hyper, params, cal = cal)
} # }
```
