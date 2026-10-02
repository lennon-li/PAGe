# Plan a governed PAGe training run without fitting or launching workers

Normalizes the season sets, grids, M1 caps, support checks, and resource
settings that a subsequent
[`train_pipeline()`](https://lennon-li.github.io/PAGe/reference/train_pipeline.md)
call would use. This is a dry run: it does not fit models, create
checkpoints, or write artifacts.

## Usage

``` r
plan_training(
  allD,
  mode = c("refresh", "retune"),
  previous_results = NULL,
  exclude = c("2011-12", "2015-16", "2020-21", "2021-22"),
  prospective_holdout = "2025-26",
  promotion = NULL,
  loso_seasons = "all",
  n_cores = parallel::detectCores() - 1L,
  checkpoint_dir = NULL,
  m0_grid = .default_m0_grid(),
  m1_grid = default_m1_grid(),
  m2_grid = NULL,
  max_m2_finalists = 6L,
  max_m2_specs = 64L,
  m1_hard_caps = default_m1_hard_caps()
)
```

## Arguments

- allD:

  Multi-season surveillance data.

- mode:

  One of `"refresh"` or `"retune"`.

- previous_results:

  Optional prior M2 tuning result used to plan its grid.

- exclude:

  Seasons excluded from training and fitting.

- prospective_holdout:

  Season held out until promotion evidence releases it.

- promotion:

  Optional verified promotion evidence.

- loso_seasons:

  LOSO fold selector: `"all"`, `"alternating"`, or an explicit character
  vector.

- n_cores:

  Requested worker count.

- checkpoint_dir:

  Optional parent checkpoint directory; it is reported but not created.

- m0_grid, m1_grid:

  Optional explicit M0/M1 grids.

- m2_grid:

  Optional explicit M2 grid; otherwise
  [`plan_m2_grid()`](https://lennon-li.github.io/PAGe/reference/plan_m2_grid.md)
  is used.

- max_m2_finalists, max_m2_specs:

  Bounds for an automatically planned M2 grid.

- m1_hard_caps:

  M1 hard-cap policy.

## Value

A `page_training_plan` containing season selection, grids, support
audit, cap policy, and resource estimates.
