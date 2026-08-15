# Freeze an M0 draft artifact

Promotes a draft M0 fit to immutable frozen status. Governed tuning is
boundary-validated before the fit can be frozen.

## Usage

``` r
freeze_m0(fit, tuning = NULL, ...)
```

## Arguments

- fit:

  A `page_m0_fit` in draft or frozen state.

- tuning:

  Optional `page_m0_tuning` result to validate. Governed tuning must
  include its complete grid for boundary validation.

- ...:

  Reserved.

## Value

The `page_m0_fit` in `frozen` state.
