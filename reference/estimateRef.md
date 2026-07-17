# Estimate a reference (template) curve for influenza positivity

Fits a season-pooled model on aligned week index `newWeek` with a cyclic
smooth and a season random intercept. Multiple estimation methods are
available via the `method` parameter.

## Usage

``` r
estimateRef(
  alignedD,
  exSeason = NULL,
  k = 10,
  n_weeks = 52L,
  nAGQ = 1,
  method = c("binomial", "binomial_weighted", "gaussian_logit", "median_smooth", "fs",
    "gaussian_logit_fs"),
  trough_weight = 0.1,
  peak_weight_boost = 3,
  agg = c("median", "mean")
)
```

## Arguments

- alignedD:

  Data frame with at least: `season`, `newWeek`, `y`, `neg`. Methods
  `"gaussian_logit"` and `"median_smooth"` also require `fit` (from
  [`estimateDerivs()`](https://lennon-li.github.io/PAGe/reference/estimateDerivs.md)).

- exSeason:

  Character vector of season labels to exclude.

- k:

  Basis dimension for the cyclic smooth.

- n_weeks:

  Integer. Number of weeks in the template domain (default 52).

- nAGQ:

  Passed to `gamm4`; default 1 (Laplace). Only used by binomial methods.

- method:

  Character. Estimation method:

  "binomial"

  :   Binomial GAMM on raw counts via gamm4 (original).

  "binomial_weighted"

  :   Binomial GAMM on raw counts with ignition-to-peak count inflation
      (like estimateDerivs weighting).

  "gaussian_logit"

  :   Gaussian GAM on logit(fit) with trough downweighting. Requires
      `fit` column.

  "median_smooth"

  :   Pointwise median of per-season `fit` across seasons at each
      newWeek, then smooth with cyclic GAM. Requires `fit` column.

  "fs"

  :   Factor-smooth interaction via `s(newWeek, season, bs="fs")`. Each
      season gets its own smooth with shared smoothness penalty;
      population curve = average of per-season predictions. Requires
      `fit` column.

  "gaussian_logit_fs"

  :   Combined: global cyclic smooth `s(newWeek, bs="cc")` plus
      factor-smooth `s(newWeek, season, bs="fs")` for per-season shape
      deviations. Population curve from the global smooth only (fs
      excluded from prediction). Requires `fit` column.

- trough_weight:

  Numeric in (0,1\]. Weight for pre-season (phase==0) rows. Only used by
  `"gaussian_logit"` and `"binomial_weighted"`. Default 0.1.

- peak_weight_boost:

  Numeric \>= 1. Count inflation factor for ignition-to-peak rows. Only
  used by `"binomial_weighted"`. Default 3.

- agg:

  Character. Aggregation method for the `"fs"` method's population
  curve: `"median"` (default) takes pointwise median across seasons on
  logit scale; `"mean"` takes the mean. Ignored for other methods.

## Value

A list with components: `mod2`, `g_ref_fun`, `g_ref_safe`,
`g_ref_mu_se`, `ref_df`, `pred_df`, `dat`, `anchorWeek`, `method`.
