# Safe penalised NLL objective for tau/delta optimisation

Evaluates the normalised negative binomial log-likelihood penalised by a
ridge term on `delta`. Returns the large sentinel value `1e9` whenever
the reference curve is non-finite, any log-likelihood term is
non-finite, or an error occurs, so that the outer optimiser can safely
continue.

## Usage

``` r
safe_obj(par, t, y, n, gfun, allow_scale, lam, w)
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

## Value

A single numeric scalar (the penalised NLL, or `1e9` on failure).
