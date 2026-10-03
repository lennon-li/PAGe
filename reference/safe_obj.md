# Safe penalised NLL objective for tau/delta optimisation

Evaluates the normalised negative binomial log-likelihood penalised by a
ridge term on `delta`. Failed candidates return an infinite value with a
\`reason\` attribute; callers must treat them as fit failures rather
than as a large finite score.

## Usage

``` r
safe_obj(
  par,
  t,
  y,
  n,
  gfun,
  allow_scale,
  lam,
  w,
  min_support = 4L,
  support = NULL,
  ab_prior = NULL
)
```

## Arguments

- par:

  Numeric vector `c(tau, a, b, delta)` when `allow_scale = TRUE`, or
  `c(tau, a, delta)` otherwise.

- t:

  Numeric vector of `newWeek` values (observed data).

- y:

  Integer vector of positive-test counts.

- n:

  Integer vector of total-test counts.

- gfun:

  Reference curve function on the logit scale.

- allow_scale:

  Logical; whether the `b` scale parameter is included in `par`.

- lam:

  Numeric; ridge penalty coefficient on `delta`.

- w:

  Numeric vector of observation weights.

- min_support:

  Minimum number of finite, in-support observations required before the
  objective is evaluated.

- support:

  Optional logical vector marking observations eligible for the
  objective. `NULL` uses all observations.

- ab_prior:

  Optional list with `a_mean`, `a_sd`, `log_b_mean`, and `log_b_sd`
  supplying a Gaussian prior for the scale/intercept parameters. `NULL`
  disables the prior.

## Value

A single numeric scalar; failed candidates are \`Inf\` with a diagnostic
\`reason\` attribute.
