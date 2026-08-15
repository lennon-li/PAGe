# Validate an M0 tuning result

Rejects zero evaluable folds, non-finite selection metrics, missing
selected configuration, or mismatched folds. Governed workflows can also
require every genuinely tuned M0 axis to be bracketed or explicitly
accepted as a null/drop choice.

## Usage

``` r
validate_m0_tuning(x, grid = NULL, check_boundaries = FALSE, ...)
```

## Arguments

- x:

  A `page_m0_tuning` object.

- grid:

  Complete M0 grid used for tuning when boundary checks are enabled.

- check_boundaries:

  Logical; require all varying numeric M0 axes to be bracketed, except
  predeclared null/drop values.

- ...:

  Reserved.

## Value

`x`, invisibly, if valid.
