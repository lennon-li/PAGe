# Compute 2x2 profile-likelihood covariance for (tau, delta)

Estimates the joint covariance matrix of the alignment parameters
\\(\hat\tau, \hat\delta)\\ via a numerical 2×2 Hessian of the profile
NLL (marginalised over the intercept `a` and scale `b` using Nelder-Mead
at each grid point). Uses nine NLL evaluations via central differences.

## Usage

``` r
cov_tau_delta_from_profile(fit, h_tau = 0.1, h_del = 0.005)
```

## Arguments

- fit:

  List returned by
  [`fit_tau_delta()`](https://lennon-li.github.io/PAGe/reference/fit_tau_delta.md)
  (or `fit_tau_delta_old()`). Must contain `tau`, `delta`, `a`, `b`,
  `allow_scale`, `t`, `y`, `n`, `w`, and `g_ref_fun`.

- h_tau:

  Numeric step size for the `tau` derivative (default 0.1).

- h_del:

  Numeric step size for the `delta` derivative (default 0.005).

## Value

A list with `V` (2×2 covariance matrix, `NA`-filled when the Hessian is
singular) and `center` (`c(tau_hat, delta_hat)`).
