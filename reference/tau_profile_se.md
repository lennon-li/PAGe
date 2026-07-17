# Estimate tau and its profile standard error

Fits the temporal alignment shift `tau` by 1-D golden-section
optimisation over profile log-likelihood (marginalising over the
intercept via GLM), then approximates the standard error of `tau_hat`
from the numerical second derivative of the profile *deviance*.

## Usage

``` r
tau_profile_se(
  currentD,
  g_ref,
  allow_scale = FALSE,
  h = 0.001,
  tau0 = 0,
  tau_bounds = c(-12, 12)
)
```

## Arguments

- currentD:

  Data frame for one season with columns `newWeek`, `y` (positives), and
  `neg` (negatives).

- g_ref:

  Reference curve function on the logit scale,
  `g_ref(u) = logit(p_ref(u))`.

- allow_scale:

  Logical; if `TRUE` fits an intercept + slope (`a + b * g_ref`) rather
  than offset-only (default `FALSE`).

- h:

  Numeric step size for numerical second derivative (default `1e-3`).

- tau0:

  Numeric starting value for the search interval centre (default 0).

- tau_bounds:

  Numeric vector of length 2; hard limits for `tau` (default
  `c(-12, 12)`).

## Value

A list with `tau_hat` (numeric) and `se_tau` (numeric, `NA` when the
Hessian is non-positive).
