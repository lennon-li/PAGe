# Leave-one-season-out evaluation of M0v2 ignition detection

Performs strict LOSO cross-validation for the M0v2 ignition model. In
each fold the held-out season is withheld from both training the GAM
classifier (`fitIgnition`) and tuning the gate thresholds
(`tuneIgnitionGrid_M0v2`). Returns per-fold outputs and aggregated
detection accuracy metrics.

## Usage

``` r
loso_M0v2(
  dat,
  grid,
  season_col = "season",
  week_col = "weekF",
  phase_col = "phase",
  p_col = "p",
  score_col = "p_cls_p",
  drop_seasons = NULL,
  exSeason_tune = NULL,
  fit_args = list(fit_base = TRUE, fit_slope = FALSE, fit_fs = FALSE, event_k = 1L, lead
    = 1L, A_pre = 6L, B_post = 6L, k_week = 6L, k_p = 8L, k_fs = 4L, select = FALSE,
    verbose = FALSE),
  tune_args = list(miss_penalty = 0, lambda = 20, kappa = 0, gamma = 25, gamma_late = 0,
    iWeek = TRUE, ncores = 10L, verbose = FALSE, progress_every = 200L),
  verbose = TRUE
)
```

## Arguments

- dat:

  Data frame with columns `season`, `weekF`, `phase`, `p`, and the score
  column (default `p_cls_p`).

- grid:

  Data frame of candidate gate-threshold parameter combinations passed
  to
  [`tuneIgnitionGrid_M0v2()`](https://lennon-li.github.io/PAGe/reference/tuneIgnitionGrid_M0v2.md)
  in each fold.

- season_col, week_col, phase_col, p_col, score_col:

  Character strings naming the corresponding columns in `dat`.

- drop_seasons:

  Optional character vector; seasons excluded from all folds (neither
  training nor evaluation).

- exSeason_tune:

  Optional character vector; additional seasons excluded from tuning
  only (not from evaluation).

- fit_args:

  Named list of arguments forwarded to
  [`fitIgnition()`](https://lennon-li.github.io/PAGe/reference/fitIgnition.md)
  on each fold.

- tune_args:

  Named list of arguments forwarded to
  [`tuneIgnitionGrid_M0v2()`](https://lennon-li.github.io/PAGe/reference/tuneIgnitionGrid_M0v2.md)
  on each fold.

- verbose:

  Logical; print fold-level progress messages (default `TRUE`).

## Value

A list with per-fold outputs (`fold_out`) and aggregated summary data
frames (`eval_all`, `eval_tune`, `eval_excluded`).
