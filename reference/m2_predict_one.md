# Predict M2 positivity from a fitted Stage-2 GAM (single row)

Shared prediction core used by all M2 code paths: LOSO frozen
evaluation, LOSO weekly-refit evaluation, and prospective deployment. By
centralising the newdata construction, factor-level alignment, season-RE
handling, soft-cap application, and CI logic in one place, we guarantee
that training-evaluation-deployment are fully consistent.

## Usage

``` r
m2_predict_one(
  fit,
  ew,
  h,
  iWeek,
  anchorWeek,
  logit_f_eff,
  z_ema,
  dz_ema = 0,
  logit_spread = 0,
  logN_now,
  season_label = NULL,
  ex_terms = NULL,
  include_season_re = FALSE,
  soft_cap_fn = NULL,
  return_ci = FALSE,
  bias_logit = 0
)
```

## Arguments

- fit:

  A fitted [`mgcv::bam`](https://rdrr.io/pkg/mgcv/man/bam.html)/`gam`
  object.

- ew:

  Integer. Current evaluation week (weekF).

- h:

  Integer. Forecast horizon (1 or 2).

- iWeek:

  Integer. Locked ignition week.

- anchorWeek:

  Integer. Reference-curve anchor week.

- logit_f_eff:

  Numeric. logit(M1 predicted positivity at target week).

- z_ema:

  Numeric. EWMA of logit-observed positivity.

- dz_ema:

  Numeric. Rate of change of z_ema (z_ema\[t\] - z_ema\[t-1\]).

- logit_spread:

  Numeric alignment-ensemble uncertainty on the logit scale.

- logN_now:

  Numeric. log(N) at eval week.

- season_label:

  Character. Season label for newdata: the test/current season name
  (used when the season is in the model's training data, i.e.
  weekly-refit mode), or `NULL` to fall back to the first historical
  level (frozen mode).

- ex_terms:

  Character vector. Terms to exclude from
  [`predict()`](https://rdrr.io/r/stats/predict.html) (e.g.
  exclude_newseason terms). Should NOT include `"s(season)"` when the
  season is in the refit training data.

- include_season_re:

  Logical. If `TRUE`, the season random effect is included in the
  prediction (weekly-refit mode). If `FALSE`, `"s(season)"` is appended
  to `ex_terms` (frozen mode).

- soft_cap_fn:

  Optional soft-cap function from
  [`make_soft_cap_fn()`](https://lennon-li.github.io/PAGe/reference/make_soft_cap_fn.md).

- return_ci:

  Logical. If `TRUE`, returns `m2_lo` and `m2_hi` (+/-1.96 SE on the
  link scale).

- bias_logit:

  Numeric online bias adjustment on the logit scale.

## Value

A named list with `m2_p` (and `m2_lo`, `m2_hi` if `return_ci = TRUE`),
or `NULL` on prediction failure.
