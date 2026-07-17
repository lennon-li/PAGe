# Global shim: reference curve mean and SE on logit scale

Evaluates the global GAM-based reference function set via
`set_reference()`, returning both the fitted mean and the pointwise
standard error on the logit scale.

## Usage

``` r
g_ref_mu_se(u)
```

## Arguments

- u:

  Numeric vector of week positions to evaluate.

## Value

A list with `mu` and `se` (both numeric vectors of the same length as
`u`).
