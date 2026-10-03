# Audit peak-location sensitivity across simple GAM basis dimensions

Audit peak-location sensitivity across simple GAM basis dimensions

## Usage

``` r
retrospective_gam_peak_sensitivity(
  data,
  season = NULL,
  k_values = c(5L, 6L, 8L, 10L),
  grid_step = 0.01
)
```

## Arguments

- data:

  One completed season of surveillance data accepted by
  [`prepare_surveillance_data()`](https://lennon-li.github.io/PAGe/reference/prepare_surveillance_data.md).

- season:

  Optional season identifier.

- k_values:

  Integer vector of cubic regression spline basis dimensions to compare.

- grid_step:

  Decimal-week resolution used to locate each fitted maximum.

## Value

A data frame of peak-location sensitivity summaries.
