# Wilson score confidence interval for a proportion

Computes the Wilson score interval for observed count `y` out of `n`
trials at the requested confidence level.

## Usage

``` r
wilson_ci(y, n, level = 0.95)
```

## Arguments

- y:

  Integer or numeric; number of successes.

- n:

  Integer or numeric; number of trials.

- level:

  Numeric; confidence level (default 0.95).

## Value

A two-column numeric matrix with columns `lo` and `hi`, both clamped to
\\\[0, 1\]\\.
