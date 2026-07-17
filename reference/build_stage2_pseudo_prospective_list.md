# Build pseudo-prospective Stage-2 snapshot list (current season)

Creates a sequence of "as-of week" snapshots for the current season to
mimic online/prospective operation. Each snapshot is a data frame
containing all weeks `weekF = 1..n_weeks`, stacked by `lead` (e.g. `h1`,
`h2`).

## Usage

``` r
build_stage2_pseudo_prospective_list(
  currentSeason,
  template_df,
  best_mean_nll,
  iWeek_hat,
  align = TRUE,
  anchorWeek = 19L,
  pre_buffer = 1L,
  n_weeks = 53L,
  eps = 1e-06,
  date_col = if ("date" %in% names(currentSeason)) "date" else NULL
)
```

## Arguments

- currentSeason:

  One-season data.frame with at least columns `weekF`, `y`, and either
  `N` or `neg`. Optional `date` column (see `date_col`).

- template_df:

  Data frame with columns `newWeek` (integer) and `fit` (numeric in
  (0,1)) defining the reference/template curve.

- best_mean_nll:

  Tuned Stage-2 hyperparameters (list or 1-row data.frame) that may
  contain `delta` (or `shift`), `K`, and `leads`.

- iWeek_hat:

  Integer ignition week estimate used for phase and alignment.

- align:

  Logical. If TRUE, uses aligned
  `newWeek = weekF - iWeek_hat + anchorWeek`. If FALSE, uses
  `newWeek = weekF`.

- anchorWeek:

  Integer anchor week used when `align=TRUE`.

- pre_buffer:

  Integer \>= 0. Weeks before ignition included for `toFit==1` logic.

- n_weeks:

  Integer. Length of the full season axis (52 or 53).

- eps:

  Numeric small constant passed to derivative calculations.

- date_col:

  Character. Name of the date column in `currentSeason` (default tries
  `"date"`).

## Value

A list with:

- meta:

  List of snapshot metadata (e.g., `iWeek_hat`, `n_weeks`, tuned
  `delta/K/leads`).

- df:

  Named list of snapshot data.frames, each stacked by `lead`.

## Details

For a snapshot with as-of week `asof_weekF`:

- Observed fields `y`, `N`, `neg`, `p`, `date` are present only for
  `weekF <= asof_weekF` and set to `NA` afterward.

- Truth fields `*_true` (e.g. `p_true`) are retained for all available
  weeks (retrospective evaluation).

- `toFit == 1` only for origin weeks up to `asof_weekF` and after
  `iWeek_hat - pre_buffer`.

- Stage-2 covariates are computed: `newWeek`, template curve columns,
  and prospective derivatives (`d1_link`, `d2_link`).

Snapshot list is built only from ignition week through the most recent
observed week (internally defined as the max `weekF` with finite
`p_true`).
