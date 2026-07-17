# Score a fitted Stage-2 GAM on a test set

Computes binomial NLL, mean NLL, Brier score, and RMSE(p) for a fitted
Stage-2 `bam`/`gam` on held-out data. Optionally applies time-decay
weights (`lambda_w`) and restricts evaluation to an early observation
window (`eval_window`). Factor levels for `lead`, `season`, and
`season_h` are aligned to the training model before prediction.

## Usage

``` r
score_stage2_metrics(
  fit,
  d_test,
  exclude_season_re = TRUE,
  exclude_terms = NULL,
  lambda_w = 0,
  eval_window = NULL,
  soft_cap_fn = NULL
)
```

## Arguments

- fit:

  Fitted [`mgcv::gam`](https://rdrr.io/pkg/mgcv/man/gam.html) or
  [`mgcv::bam`](https://rdrr.io/pkg/mgcv/man/bam.html) Stage-2 model.

- d_test:

  Data frame of test observations. Must contain `y_lead` and `N_lead`
  (outcome counts) plus any predictors used in `fit`.

- exclude_season_re:

  Logical; if `TRUE` (default) the season random effect (`s(season)`) is
  excluded when predicting.

- exclude_terms:

  Character vector of additional terms to exclude from prediction.
  Overrides `exclude_season_re` when non-`NULL`.

- lambda_w:

  Numeric; exponential time-decay rate applied to `t_since` when
  computing observation weights (0 = uniform; default 0).

- eval_window:

  Optional integer; restrict scoring to rows where
  `t_since <= eval_window`. When `NULL` all rows are scored.

- soft_cap_fn:

  Optional function applied to `p_hat` after prediction (e.g. a soft
  ceiling on positivity).

## Value

A list with `nll`, `mean_nll`, `brier`, and `rmse_p`.
