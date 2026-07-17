# Tune M1 alignment hyperparameters via LOSO grid search

Runs leave-one-season-out grid search over M1 alignment parameters using
[`tune_m1_alignment()`](https://lennon-li.github.io/PAGe/reference/tune_m1_alignment.md).
Supports resumable checkpoints.

## Usage

``` r
tune_m1(
  allD,
  m0,
  m1,
  loso_seasons = "all",
  grid = default_m1_grid(),
  n_cores = parallel::detectCores() - 1L,
  checkpoint_dir = NULL,
  verbose = TRUE
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
  Provides `m1_params`.

- loso_seasons:

  Which seasons to use as LOSO test folds. `"all"` (default) tests every
  season; `"alternating"` tests every other season.

- grid:

  Tuning grid. Default:
  [`default_m1_grid()`](https://lennon-li.github.io/PAGe/reference/default_m1_grid.md).

- n_cores:

  Integer. Parallel cores.

- checkpoint_dir:

  Character. Directory for resumable checkpoints. Uses a temp directory
  if `NULL`.

- verbose:

  Logical. Print progress.

## Value

Output of
[`tune_m1_alignment()`](https://lennon-li.github.io/PAGe/reference/tune_m1_alignment.md)
— a list with per-spec MAE scores and the best spec parameters.
