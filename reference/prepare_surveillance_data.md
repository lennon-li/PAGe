# Prepare surveillance data for PAGe

Normalizes weekly surveillance data to PAGe's canonical columns. Input
must contain `weekF`, `y`, and either `N` or `neg`. Missing totals,
negatives, and positivity are derived deterministically. When `N` is
zero, `p` is left missing rather than treating an unobserved week as
zero positivity.

## Usage

``` r
prepare_surveillance_data(data, season = NULL, tolerance = 1e-08)
```

## Arguments

- data:

  A data frame containing weekly surveillance observations.

- season:

  Optional single season identifier used only when `data` does not
  contain a `season` column.

- tolerance:

  Numeric tolerance for redundant count and positivity consistency
  checks.

## Value

A data frame with canonical columns `season`, `weekF`, `y`, `N`, `p`,
and `neg`, followed by any extra input columns in their original order.
