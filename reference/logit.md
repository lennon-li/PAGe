# Logit transformation with clipping

Applies [`qlogis()`](https://rdrr.io/r/stats/Logistic.html) after
clamping `p` to \\\[10^{-6},\\ 1 - 10^{-6}\]\\ to avoid \\\pm\infty\\ at
the boundary.

## Usage

``` r
logit(p)
```

## Arguments

- p:

  Numeric vector of probability values in \\(0, 1)\\.

## Value

Numeric vector of logit-transformed values.
