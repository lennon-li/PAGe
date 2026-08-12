# Freeze an M0 draft artifact

Promotes a draft M0 fit to immutable frozen status. When `tuning` is
supplied, it is validated first via
[`validate_m0_tuning()`](https://lennon-li.github.io/PAGe/reference/validate_m0_tuning.md).

## Usage

``` r
freeze_m0(fit, tuning = NULL, ...)
```

## Arguments

- fit:

  A `page_m0_fit` in draft or frozen state.

- tuning:

  Optional `page_m0_tuning` result to validate.

- ...:

  Reserved.

## Value

The `page_m0_fit` in `frozen` state.
