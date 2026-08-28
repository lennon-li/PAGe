# Compute weighted logit-scale spread (internal helper)

`"between"` computes the weighted between-template standard deviation.
`"total"` adds weighted per-template SE\\2 (from `g_s_mu_se`) to the
between-template variance. When per-template SEs are all zero/missing
for a forecast week, that week falls back to between-only and the
fallback count is incremented.

## Usage

``` r
.compute_logit_spread(logit_mat, wts, se_mat = NULL, spread_method = "between")
```

## Arguments

- logit_mat:

  Numeric matrix (n_future x n_templates) of logit-scale template
  forecasts.

- wts:

  Numeric vector of ensemble weights (length n_templates).

- se_mat:

  Numeric matrix or NULL; per-template GAM SEs at forecast weeks (same
  shape as `logit_mat`). Required for `"total"` mode.

- spread_method:

  Character; `"between"` or `"total"`.

## Value

List with `spread` (numeric vector, length `nrow(logit_mat)`) and
`fallback_count` (integer).
