# Extract Stage-2 hyperparameters from tuning output

Helper to pull commonly used Stage-2 hyperparameters from a list or
1-row data.frame, supporting alternate names (e.g., `shift` for
`delta`).

## Usage

``` r
plot_ignition_weekly_snapshots(
  ign_out,
  currentSeason = NULL,
  facet = TRUE,
  ncol = 4,
  base_size = 11,
  y_max = 0.2,
  start_week = 5L,
  maxWeek = Inf,
  week_col = "weekF",
  y_col = "y",
  N_col = "N",
  p_col = "p",
  date_col = "date"
)
```

## Arguments

- ign_out:

  List returned by
  [`run_ignition_weekly()`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly.md).
  Must contain `$df` with at least columns `weekF` and `p_now`.

- currentSeason:

  Optional data frame with observed series columns (week, positivity
  and/or counts, optionally date). When `NULL`, `p_now` from
  `ign_out$df` is used as the observed series.

- facet:

  Logical; if `TRUE` (default) returns a single faceted ggplot; if
  `FALSE` returns a named list of per-snapshot ggplots.

- ncol:

  Integer; columns in the facet layout when `facet = TRUE` (default 4).

- base_size:

  Numeric; ggplot base font size (default 11).

- y_max:

  Numeric; upper y-axis limit across all panels (default 0.20).

- start_week:

  Integer; first `weekF` to include (default 5L).

- maxWeek:

  Numeric; last `weekF` to include (default `Inf`).

- week_col:

  Character; name of the week column in `currentSeason` (default
  `"weekF"`).

- y_col:

  Character; name of the positive-count column (default `"y"`).

- N_col:

  Character; name of the total-test column (default `"N"`).

- p_col:

  Character; name of the positivity column (default `"p"`).

- date_col:

  Character; name of the date column (default `"date"`).

## Value

A list with elements `delta`, `K`, `leads`, `use_ramp`, and `extra`.
Plot walk-forward ignition detection snapshots

Creates a faceted ggplot (or named list of ggplots) showing the observed
positivity series at each as-of week evaluated by
[`run_ignition_weekly()`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly.md).
The current-week observation is highlighted, detected weeks are coloured
red, and a dashed vertical line marks the locked ignition estimate when
detection has fired.

A ggplot object (when `facet = TRUE`) or a named list of ggplot objects
(when `facet = FALSE`).

## Details

`delta` (or `shift`), `K`, `leads`, and optionally `use_ramp`.
