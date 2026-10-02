# Prospective ignition detection (M0v2) across seasons

Applies a prospective-safe ignition detector across all seasons. The
detector has five possible evidence votes: classifier score, rolling
positivity sum, smoothed positivity level, cumulative prevalence, and
smoothed trend. The classifier vote is optional and is disabled in the
current M0-v2 policy.

## Usage

``` r
detectIgnitionBySeason_M0v2(
  ign_fit,
  params,
  score_col = "p_cls_p",
  season_col = "season",
  week_col = "weekF",
  y_col = "y",
  N_col = "N",
  phase_col = "phase",
  truth_col = "iWeek",
  keep_signals = TRUE,
  verbose = TRUE,
  iWeek = FALSE,
  copy_data = TRUE,
  validate_support = TRUE
)
```

## Arguments

- ign_fit:

  Either a list returned by \[fitIgnition()\] containing `$data`, or a
  data.frame/data.table.

- params:

  Named list of thresholds/hyperparameters.

- score_col:

  Character. Name of classifier score column. Default `"p_cls_p"`.

- season_col, week_col:

  Column names for season and within-season week.

- y_col, N_col:

  Column names for positives and totals.

- phase_col:

  Column name for phase indicator (used for truth if `truth_col`
  missing).

- truth_col:

  Column name for truth ignition week if stored explicitly.

- keep_signals:

  Logical. If TRUE return full row-level signals.

- verbose:

  Logical. If TRUE prints summary.

- iWeek:

  Logical. If TRUE return season-level compare table.

- copy_data:

  Logical. If FALSE operate on input data.table by reference.

- validate_support:

  Logical. If TRUE (default), reject parameter windows that exceed
  observed within-season data. Prospective one-season snapshots may set
  this to FALSE; rolling gates remain undefined until enough
  observations arrive.

## Value

list with `by_season` and optionally `data` and `compare`.

## Details

A separate raw-positivity persistence safeguard can be enabled with
`raw_nondec_n > 1`. Each week-to-week decrease in the most recent
`raw_nondec_n` observations must be no larger than `raw_drop_se_tol`
standard errors of the difference between the two weekly binomial
proportions. The current M0-v2 policy uses 1 SE. This safeguard is
mandatory in addition to the N-of-votes rule; it is not an
interchangeable vote. Setting `raw_nondec_n = 1` disables it.

Within the eligible window `w_min <= week <= w_max`, ignition is
declared at the earliest week where the raw-persistence safeguard passes
and at least `N_req` evidence votes are satisfied.
