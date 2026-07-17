# Global shim: reference curve clamped to support

Evaluates the global reference function set via `set_reference()`,
clamping `u` to the grid support before prediction to avoid
extrapolation artefacts.

## Usage

``` r
g_ref_safe(u)
```

## Arguments

- u:

  Numeric vector of week positions to evaluate.

## Value

Numeric vector of logit-scale reference values.
