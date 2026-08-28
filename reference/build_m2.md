# Build M2 forecast model via nested LOSO grid search

Runs Phase 1 (M1 walk-forward cache per LOSO fold) and Phase 2 (frozen
GAM + Holt EMA bias grid search) to identify the best M2 spec. Uses
`loso_seasons = "alternating"` by default for fast demos; switch to
`"all"` for production tuning.

## Usage

``` r
build_m2(
  allD,
  m0,
  m1,
  loso_seasons = "alternating",
  exclude_seas = "2015-16",
  holdout_season = "2025-26",
  grid = default_m2_grid(),
  bias_alpha = 0.05,
  bias_beta = 0,
  n_cores = parallel::detectCores() - 1L,
  checkpoint_dir = NULL,
  m1_artifact_path = NULL,
  fail_fast = TRUE,
  future_max_size = NULL,
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
  Provides reference curve and params.

- loso_seasons:

  Which seasons to evaluate as LOSO test folds. `"alternating"`
  (default) halves tuning time; `"all"` for production quality. A
  character vector selects specific seasons.

- exclude_seas:

  Seasons to exclude from LOSO folds entirely.

- holdout_season:

  Prospective season excluded by default. Set to NULL only after an
  explicit promotion release.

- grid:

  Tuning grid. Default: compact
  [`default_m2_grid()`](https://lennon-li.github.io/PAGe/reference/default_m2_grid.md)
  plan. Per-row `bias_alpha` and `bias_beta` columns override their
  scalar fallbacks.

- bias_alpha, bias_beta:

  Numeric. Backward-compatible Holt EMA scalar fallbacks used when the
  grid omits the corresponding columns.

- n_cores:

  Integer. Parallel cores.

- checkpoint_dir:

  Character. Directory for Phase 2 checkpoint files. Pass `NULL` to
  disable checkpointing.

- m1_artifact_path:

  Character. Optional path for the complete Phase 1 M1 LOSO artifact.
  When `NULL` and `checkpoint_dir` is supplied, `m1_phase1.rds` is
  written inside that directory. A matching existing artifact is reused;
  it is compacted in memory before M2 workers receive it.

- fail_fast:

  Logical. Stop on the first unsupported fold/spec instead of converting
  model failures to missing scores (default `TRUE`).

- future_max_size:

  Numeric. Maximum size, in bytes, of globals exported to future
  workers. When `NULL` (default), the limit is raised only as needed for
  the prepared M1 cache, with a 2 GiB safety ceiling.

- verbose:

  Logical. Print progress.

## Value

A list with `best_spec`, `best_spec_id`, `summary` (ranked by Bernoulli
NLL), `scores`, `cv_results`, and `grid`. Pass `best_spec` to
[`train_m2()`](https://lennon-li.github.io/PAGe/reference/train_m2.md).
