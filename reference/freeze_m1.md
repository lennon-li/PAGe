# Freeze an M1 draft artifact

Freeze an M1 draft artifact

## Usage

``` r
freeze_m1(fit, tuning = NULL, ...)
```

## Arguments

- fit:

  A `page_m1_fit`.

- tuning:

  Optional `page_m1_tuning` to validate. Governed tuning is
  boundary-validated before freezing.

- ...:

  Reserved.

## Value

The `page_m1_fit` in `frozen` state.
