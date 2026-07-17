# Build aligned training data using M0 ignition detection

Computes seasonal derivative signals via
[`estimateDerivs()`](https://lennon-li.github.io/PAGe/reference/estimateDerivs.md),
flags ignition events via
[`flagIgnition()`](https://lennon-li.github.io/PAGe/reference/flagIgnition.md),
and aligns all seasons to a common `newWeek` coordinate via
[`alignIgnition()`](https://lennon-li.github.io/PAGe/reference/alignIgnition.md).

## Usage

``` r
build_m0(
  allD,
  exclude = c("2011-12", "2015-16", "2020-21", "2021-22"),
  manual_labels = .default_manual_labels(),
  flag_args = .default_flag_args(),
  best_params = .default_m0_params(),
  k_deriv = 10L
)
```

## Arguments

- allD:

  Multi-season surveillance data frame with columns `season`, `weekF`,
  `y`, `N`, `p`.

- exclude:

  Character vector of seasons to exclude permanently.

- manual_labels:

  Named integer vector of manually-verified ignition weeks (names =
  season labels). Defaults to canonical production labels.

- flag_args:

  List of ignition-flagging hyperparameters. Defaults to canonical
  production values.

- best_params:

  Locked production M0 parameters. Defaults to the deployed fresh-run
  values and is returned for downstream M1/M2 training.

- k_deriv:

  Integer. GAM basis functions for derivative smoothing (default `10L`).

## Value

A list with `aligned` (aligned data frame), `seasons_used`,
`manual_labels`, `flag_args`, and `best_params`.
