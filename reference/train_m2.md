# Fit the M2 production GAM on all training seasons

Trains the Stage-2 GAM on all non-excluded seasons using the best spec
from
[`build_m2()`](https://lennon-li.github.io/PAGe/reference/build_m2.md).
Runs M1 walk-forward predictions before fitting.

## Usage

``` r
train_m2(
  allD,
  m0,
  m1,
  best_spec = NULL,
  exclude = c("2011-12", "2015-16", "2020-21", "2021-22"),
  verbose = FALSE
)
```

## Arguments

- allD:

  Multi-season surveillance data frame.

- m0:

  Output of
  [`tune_m0()`](https://lennon-li.github.io/PAGe/reference/tune_m0.md).
  Must include `best_params`.

- m1:

  Output of
  [`build_m1()`](https://lennon-li.github.io/PAGe/reference/build_m1.md).
  Provides `ref` and `hyper`.

- best_spec:

  Stage-2 spec from `build_m2()$best_spec` or
  [`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md).
  When `NULL`, uses the locked deployed v16 specification for a
  production-data refresh without retuning.

- exclude:

  Character vector of seasons to exclude from training. Default excludes
  permanent invalid seasons and 2015-16. Note: 2025-26 is kept
  (production training uses the current season).

- verbose:

  Logical. Print progress.

## Value

A list with `fit` (GAM), `feature_ranges`, `m1_train_preds`, `spec`,
`training_seasons`, and `spec_version`. Pass to
[`assemble_kit()`](https://lennon-li.github.io/PAGe/reference/assemble_kit.md).
