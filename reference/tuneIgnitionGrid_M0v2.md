# Grid-search tuning for M0v2 ignition detector

Tunes M0v2 ignition thresholds over a parameter grid by repeatedly
calling \[detectIgnitionBySeason_M0v2()\] and comparing estimated
ignition weeks to season-level truth ignition weeks. Scoring uses a
symmetric adjusted error with a -1 week wiggle room (detecting one week
early counts as exact). Seasons with no detection within
`[w_min, w_max]` are assigned `w_max` as a fallback, so misses never
occur.

## Usage

``` r
tuneIgnitionGrid_M0v2(
  ign_fit,
  grid,
  score_col = "p_cls_p",
  week_col = "weekF",
  season_col = "season",
  phase_col = "phase",
  truth_col = "iWeek",
  exSeason = NULL,
  miss_penalty = 0,
  lambda = 20,
  kappa = 0,
  gamma = 25,
  gamma_late = 0,
  iWeek = TRUE,
  ncores = 10L,
  verbose = TRUE,
  progress_every = 200L
)
```

## Arguments

- ign_fit:

  Either \[fitIgnition()\] output (list with `$data`) or a
  data.frame/data.table.

- grid:

  data.frame of parameter combinations; missing columns are filled by
  defaults.

- score_col:

  Character. Classifier score column name. Default `"p_cls_p"`.

- week_col, season_col:

  Column names for within-season week and season.

- phase_col:

  Column name used if `truth_col` is unavailable.

- truth_col:

  Column name for truth ignition week if stored.

- exSeason:

  Optional character vector of seasons to exclude from tuning (but still
  evaluate afterward).

- miss_penalty:

  Numeric. Penalty per missing detection. Default 0 (no misses occur due
  to the `w_max` fallback in `detectIgnitionBySeason_M0v2`).

- lambda:

  Numeric. Weight on worst-case adjusted error `max_abs`.

- kappa:

  Numeric. Extra weight on late errors. Default 0 (symmetric scoring).

- gamma:

  Numeric. Penalty for adjusted error exceeding 2 weeks.

- gamma_late:

  Numeric. Extra penalty for being late \>2 weeks. Default 0 (disabled).

- iWeek:

  Logical. Use `truth_col` if available; otherwise infer from
  `phase_col`.

- ncores:

  Integer \>= 1. Number of cores.

- verbose:

  Logical. Print progress.

- progress_every:

  Integer. Chunk size for progress updates.

## Value

List with best params, full results, runtime, and evaluation tables.
