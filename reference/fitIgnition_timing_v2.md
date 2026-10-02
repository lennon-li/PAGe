# Fit the M0 classifier using fractional timing targets

Fit the M0 classifier using fractional timing targets

## Usage

``` r
fitIgnition_timing_v2(data, labels, ...)
```

## Arguments

- data:

  Weekly training data accepted by
  [`fitIgnition()`](https://lennon-li.github.io/PAGe/reference/fitIgnition.md).

- labels:

  Timing-v2 labels for the training seasons.

- ...:

  Arguments passed to
  [`fitIgnition()`](https://lennon-li.github.io/PAGe/reference/fitIgnition.md).

## Value

An M0 classifier result with numeric timing provenance.
