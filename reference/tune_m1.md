# Tune M1 alignment hyperparameters via LOSO grid search

Runs leave-one-season-out grid search over M1 alignment parameters using
[`tune_m1_alignment()`](https://lennon-li.github.io/PAGe/reference/tune_m1_alignment.md).
Supports resumable checkpoints.

## Usage

``` r
tune_m1(
  allD,
  m0,
  m1 = NULL,
  loso_seasons = "all",
  grid = default_m1_grid(),
  n_cores = parallel::detectCores() - 1L,
  checkpoint_dir = NULL,
  verbose = TRUE,
  selection = NULL,
  manual_labels = NULL
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

- selection:

  Optional governed `page_season_selection`. When supplied, `m0` must be
  frozen, only selected training seasons are used, and the result is a
  `page_m1_tuning`.

- manual_labels:

  Optional named ignition-week vector in the M0 week coordinate system.
  Defaults to labels stored in `m0`. M1 tuning applies its historical
  one-week coordinate offset after resolving this value.

## Value

Output of
[`tune_m1_alignment()`](https://lennon-li.github.io/PAGe/reference/tune_m1_alignment.md)
– a list with per-spec MAE scores and the best spec parameters.
