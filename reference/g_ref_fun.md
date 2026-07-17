# Global shim: reference curve on logit scale (unbounded domain)

Evaluates the global reference function set via `set_reference()`.
Returns logit-scale predictions for arbitrary (possibly fractional) `u`
values without clamping.

## Usage

``` r
g_ref_fun(u)
```

## Arguments

- u:

  Numeric vector of week positions to evaluate.

## Value

Numeric vector of logit-scale reference values.
