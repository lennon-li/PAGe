# LOSO grid search over M1 alignment hyperparameters

Runs
[`loso_walkforward()`](https://lennon-li.github.io/PAGe/reference/loso_walkforward.md)
for every combination of candidate values across multiple alignment
hyperparameters and scores each specification by prospective peak MAE
under three Weibull weighting schemes (same metrics as `tune_loso_k()`).

## Usage

``` r
tune_m1_alignment(
  allD,
  params,
  grid,
  manual_labels = NULL,
  exclude_seasons = NULL,
  n_weeks = 52L,
  n_cores = parallel::detectCores() - 1L,
  checkpoint_dir = "data/m1_tune_ckpt",
  verbose = TRUE,
  ...
)
```

## Arguments

- allD:

  Raw data frame passed to
  [`loso_walkforward()`](https://lennon-li.github.io/PAGe/reference/loso_walkforward.md).

- params:

  Stage-1 detector parameters list.

- grid:

  A data frame (or tibble) where each row is one parameter
  specification. Column names must match arguments of
  [`loso_walkforward()`](https://lennon-li.github.io/PAGe/reference/loso_walkforward.md)
  (e.g. `k_ref`, `multi_temperature`, `template_shift`,
  `align_rise_weight`).

- manual_labels:

  Named integer vector of verified ignition weeks.

- exclude_seasons:

  Character vector of seasons to exclude.

- n_weeks:

  Integer. Template length (default 52).

- n_cores:

  Integer. Workers per
  [`loso_walkforward()`](https://lennon-li.github.io/PAGe/reference/loso_walkforward.md)
  call (default `parallel::detectCores() - 1`).

- checkpoint_dir:

  Character. Directory for per-spec checkpoint files and the results
  cache (default `"data/m1_tune_ckpt"`).

- verbose:

  Logical. Print progress (default `TRUE`).

- ...:

  Additional fixed arguments forwarded to
  [`loso_walkforward()`](https://lennon-li.github.io/PAGe/reference/loso_walkforward.md)
  (e.g. `buffer_weeks`, `use_ci`).

## Value

A list with elements:

- scores:

  Tibble with one row per spec: `spec_id` plus the grid columns,
  `mae_uniform`, `mae_exp`, `mae_weibull`, `n_seasons`.

- best:

  Single-row tibble for the spec with lowest `mae_weibull`.

- grid:

  The input grid (for reference).

## Details

Each specification is identified by a short string `spec_id`. Results
are checkpointed after every completed spec so the search can be resumed
after interruption.

## Examples

``` r
if (FALSE) { # \dontrun{
grid <- expand.grid(
  k_ref             = c(15L, 20L, 25L),
  multi_temperature = c(0.5, 1.0, 2.0),
  template_shift    = c(-1L, 0L, 1L),
  align_rise_weight = c(1.0, 2.0, 3.0),
  stringsAsFactors  = FALSE
)
res <- tune_m1_alignment(
  allD, params, grid,
  manual_labels   = manual_labels,
  exclude_seasons = "2015-16",
  use_multi_template = TRUE,
  ref_method         = "fs"
)
res$best
} # }
```
