# Prospective ignition detection (M0v2) across seasons

Applies a prospective-safe ignition detector across all seasons. The
detector uses five gates:

1.  classifier score gate: `score_col >= cls_thr`

2.  rolling-sum evidence gate: `p_sumK >= p_sum_thr` where
    `p_sumK = rollsum(p, K_sum)`

3.  smoothed positivity level gate: `p_sm >= p_thr` where
    `p_sm = rollmean(p, L)`

4.  cumulative prevalence gate: `prev >= prev_thr` where
    `prev = cumsum(y)/cumsum(N)`

5.  noise-tolerant trend gate on `p_sm` requiring sustained increases
    with tolerance `eps`

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
  copy_data = TRUE
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

## Value

list with `by_season` and optionally `data` and `compare`.

## Details

Within the eligible window `w_min <= week <= w_max`, ignition is
declared at the earliest week where at least `N_req` of the five gates
are satisfied (N-of-5 voting). The classifier gate is a vote (not
mandatory).
