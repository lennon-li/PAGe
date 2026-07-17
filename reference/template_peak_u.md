# Find the peak of a reference template curve

Evaluates `g_ref_fun` over a fine grid and returns the `u` value where
the curve is maximised.

## Usage

``` r
template_peak_u(g_ref_fun, u_range = c(1, 52), by = 0.01)
```

## Arguments

- g_ref_fun:

  Reference curve function on the logit scale.

- u_range:

  Numeric vector of length 2; grid endpoints (default `c(1, 52)`).

- by:

  Numeric grid step size (default 0.01).

## Value

A numeric scalar; the `u` value of the template peak.
