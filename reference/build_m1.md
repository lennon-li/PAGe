# Build M1 reference curve and alignment hyperparameters

Fits the epidemic reference curve via
[`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md)
and learns alignment search bounds via
[`learn_alignment_hyperparams()`](https://lennon-li.github.io/PAGe/reference/learn_alignment_hyperparams.md).
Inherits `manual_labels` and `flag_args` from `m0`.

## Usage

``` r
build_m1(
  allD,
  m0,
  exclude = c("2011-12", "2015-16", "2020-21", "2021-22"),
  exclude_live = TRUE,
  min_live_weeks = 20L,
  m1_params = .default_m1_params()
)
```

## Arguments

- allD:

  Multi-season surveillance data frame.

- m0:

  Output of
  [`tune_m0()`](https://lennon-li.github.io/PAGe/reference/tune_m0.md)
  or
  [`build_m0()`](https://lennon-li.github.io/PAGe/reference/build_m0.md).
  Carries `manual_labels` and `flag_args` for consistent alignment.

- exclude:

  Character vector of seasons to exclude from the reference fit. Default
  excludes permanent invalid seasons and the 2015-16 ignition outlier;
  2025-26 is kept for production training.

- exclude_live:

  Logical. When `TRUE` (default), seasons with fewer than
  `min_live_weeks` observed weeks are also excluded (guards against
  partial current-season bias in the reference curve).

- min_live_weeks:

  Integer. Partial-season threshold (default `20L`).

- m1_params:

  Named list of M1 alignment parameters. Defaults to the canonical
  production specification.

## Value

A list with `ref`, `hyper`, `aligned_train`, `m1_params`, and
`seasons_used`. Pass to
[`tune_m1()`](https://lennon-li.github.io/PAGe/reference/tune_m1.md),
[`build_m2()`](https://lennon-li.github.io/PAGe/reference/build_m2.md),
and
[`train_m2()`](https://lennon-li.github.io/PAGe/reference/train_m2.md).
