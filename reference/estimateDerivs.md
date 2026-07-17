# Estimate smoothed positivity and derivatives (d1/d2) by season using binomial GAMs

Fits a separate binomial GAM for each season to smooth weekly positivity
and computes first and second derivatives of the fitted smooth. Returns
the input data augmented with fitted values, confidence intervals, and
derivative estimates (with simultaneous intervals), plus the fitted
model objects.

## Usage

``` r
estimateDerivs(
  allD,
  k = 10,
  bs = "ps",
  week_col = "weekF",
  season_col = "season",
  y_col = "y",
  n_col = "N",
  ci_level = 0.95,
  deriv_interval = "simultaneous",
  method = "REML",
  peak_weight_boost = 1,
  peak_weight_decay = 0.3,
  ignition_weeks = NULL
)
```

## Arguments

- allD:

  A data.frame containing (at minimum) season, week index, positives,
  and tests.

- k:

  Integer. Basis dimension passed to
  [`mgcv::s()`](https://rdrr.io/pkg/mgcv/man/s.html) for the
  within-season smooth.

- bs:

  Character. Smoother basis for
  [`mgcv::s()`](https://rdrr.io/pkg/mgcv/man/s.html), e.g. `"ps"` or
  `"tp"`.

- week_col:

  Character. Column name for the within-season week index used in
  smoothing (default `"weekF"`).

- season_col:

  Character. Column name identifying season (default `"season"`).

- y_col:

  Character. Column name for positives (default `"y"`).

- n_col:

  Character. Column name for tests (default `"N"`).

- ci_level:

  Numeric in (0,1). Confidence level for fitted mean intervals on the
  response scale (default 0.95).

- deriv_interval:

  Character. Interval type passed to
  [`gratia::derivatives()`](https://gavinsimpson.github.io/gratia/reference/derivatives.html),
  typically `"simultaneous"` (default) or `"confidence"`.

- method:

  Character. Smoothing parameter estimation method passed to
  [`mgcv::gam()`](https://rdrr.io/pkg/mgcv/man/gam.html), default
  `"REML"`.

- peak_weight_boost:

  Numeric \>= 1. Multiplicative weight applied to observations between
  ignition and observed peak (default 1 = no boost).

- peak_weight_decay:

  Numeric \> 0. Exponential decay rate for weights after the observed
  peak. Smaller values = slower decay (default 0.3, ~2-week half-life).

- ignition_weeks:

  Optional named integer vector mapping season labels to ignition week
  values (in `week_col` space). Required when `peak_weight_boost > 1`.
  If `NULL` and boosting is requested, falls back to the first week
  where `p = y/N >= 0.01`.

## Value

A list with two elements:

- data:

  A data.frame of `allD` augmented with columns: `neg`, `fit`,
  `fit_low`, `fit_high`, `d1`, `d1_low`, `d1_high`, `d2`, `d2_low`,
  `d2_high`.

- models:

  A named list of fitted
  [`mgcv::gam`](https://rdrr.io/pkg/mgcv/man/gam.html) objects (one per
  season).

## Details

When `peak_weight_boost > 1`, observations between ignition and the
observed peak receive higher weight, with a soft exponential decay after
the peak. This emphasises the rising-limb-through-peak region that
downstream alignment and forecasting (M2) care about most.
