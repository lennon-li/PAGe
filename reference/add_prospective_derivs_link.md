# Prospective (real-time safe) derivatives of positivity on the logit scale

For each season in `alignedD`, fits a local quadratic to a rolling
window of `k` observations on the logit scale and returns the
instantaneous first and second derivatives as `d1_link` and `d2_link`.
Computation is strictly causal: only observations up to and including
the current week are used.

## Usage

``` r
add_prospective_derivs_link(alignedD, k = 5L, eps = 1e-06, min_obs = 4L)
```

## Arguments

- alignedD:

  Data frame with columns `season`, `weekF`, `y`, and `neg`.

- k:

  Integer; window size for local quadratic fit (default 5L).

- eps:

  Numeric; clipping epsilon for logit (default 1e-6).

- min_obs:

  Integer; minimum observations required (default 4L).

## Value

`alignedD` with additional columns `d1_link` and `d2_link`.
