# Estimate season random effect causally from accumulated observations

Computes a shrinkage scalar for the current season's intercept shift on
the logit scale using only observations up to the current week. The
estimate equals the mean logit-scale residual (observed minus GAM
prediction without season RE), shrunk toward zero by `lambda_re`. Adding
this scalar to `bias_logit` in
[`m2_predict_one()`](https://lennon-li.github.io/PAGe/reference/m2_predict_one.md)
replaces the hard exclusion of `s(season)` while remaining causally
safe.

## Usage

``` r
estimate_season_re_online(fit, obs_df, ex_terms = NULL, lambda_re = 1)
```

## Arguments

- fit:

  Fitted mgcv GAM with a season random effect.

- obs_df:

  Data frame of current-season observations with columns `y`, `N`, and
  all covariates required by `fit`.

- ex_terms:

  Character vector of additional terms to exclude.

- lambda_re:

  Shrinkage strength; default 1 (one pseudo-observation at 0).

## Value

Numeric scalar (the shrinkage RE estimate on the logit scale).
