# Return the default M2 forecast tuning grid

Delegates to
[`plan_m2_grid()`](https://lennon-li.github.io/PAGe/reference/plan_m2_grid.md)
to return the compact initial grid. The deployed v16 incumbent is always
included, with one-factor neighbors and per-row provenance instead of an
explosive Cartesian product.

## Usage

``` r
default_m2_grid()
```

## Value

A data frame with M2 parameters, stable specification IDs, and
provenance.
