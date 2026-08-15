# Validate an M2 tuning result

Rejects invalid grid identity, incomplete folds, non-finite selected
metric, or absent selected specification.

## Usage

``` r
validate_m2_tuning(x, check_boundaries = FALSE, ...)
```

## Arguments

- x:

  A `page_m2_tuning` object.

- check_boundaries:

  Logical; require every genuinely tuned M2 axis to be bracketed or an
  explicitly accepted null/drop.

- ...:

  Reserved.

## Value

`x`, invisibly, if valid.
