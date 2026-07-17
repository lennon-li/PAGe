# Tune M0 ignition detection hyperparameters via LOSO grid search

Runs leave-one-season-out grid search over M0 detection parameters using
[`loso_M0v2()`](https://lennon-li.github.io/PAGe/reference/loso_M0v2.md).
The 36-spec grid matches the production tuning run.

## Usage

``` r
tune_m0(
  allD,
  loso_seasons = "all",
  exclude = c("2011-12", "2015-16", "2020-21", "2021-22"),
  grid = .default_m0_grid(),
  manual_labels = .default_manual_labels(),
  flag_args = .default_flag_args(),
  n_cores = parallel::detectCores() - 1L,
  verbose = TRUE
)
```

## Arguments

- allD:

  Multi-season surveillance data frame.

- loso_seasons:

  Which seasons to evaluate as LOSO test folds. `"all"` (default)
  evaluates every season; `"alternating"` uses every other season
  (removes non-selected from training too — acceptable for quick demos).
  A character vector selects specific seasons.

- exclude:

  Character vector of seasons to permanently exclude.

- grid:

  Tuning grid as a data frame. Default: `.default_m0_grid()`.

- manual_labels:

  Named integer vector of manual ignition labels.

- flag_args:

  List of ignition-flagging parameters.

- n_cores:

  Integer. Parallel cores (default: all minus 1).

- verbose:

  Logical. Print progress.

## Value

A list with `best_params`, `tuning` (full
[`loso_M0v2()`](https://lennon-li.github.io/PAGe/reference/loso_M0v2.md)
output), `aligned`, `seasons_used`, `manual_labels`, and `flag_args`.
Pass directly to
[`build_m1()`](https://lennon-li.github.io/PAGe/reference/build_m1.md),
[`build_m2()`](https://lennon-li.github.io/PAGe/reference/build_m2.md),
and
[`train_m2()`](https://lennon-li.github.io/PAGe/reference/train_m2.md).
