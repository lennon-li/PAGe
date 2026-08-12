# Validate an M1 tuning result

Rejects zero evaluable seasons, all-missing metrics, non-finite selected
metric, missing selected configuration, or fold/selection mismatches.

## Usage

``` r
validate_m1_tuning(x, ...)
```

## Arguments

- x:

  A `page_m1_tuning` object.

- ...:

  Reserved.

## Value

`x`, invisibly, if valid.
