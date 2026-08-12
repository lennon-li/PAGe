# Return the default M1 alignment tuning grid

Crosses `k_ref = c(20, 25, 30, 40, 50)` with
`slope_weight = c(8, 12, 16, 20, 30)`. The additional `k_ref = 20` value
is a planned pre-holdout extension for the existing lower-edge
`k_ref = 25` result; it does not alter or rerun the historical grid. A
lower-edge `slope_weight = 8` result would require a separate,
explicitly approved `slope_weight = 4` extension.

## Usage

``` r
default_m1_grid()
```

## Value

A tibble with 25 rows (5 k_ref x 5 slope_weight combinations).
