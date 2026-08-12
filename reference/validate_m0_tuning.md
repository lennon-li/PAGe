# Validate an M0 tuning result

Rejects zero evaluable folds, non-finite selection metrics, missing
selected configuration, or mismatched folds.

## Usage

``` r
validate_m0_tuning(x, ...)
```

## Arguments

- x:

  A `page_m0_tuning` object.

- ...:

  Reserved.

## Value

`x`, invisibly, if valid.
