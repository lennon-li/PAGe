# Apply finalized ignition labels to canonical training data

Adds `iWeek`, `phase`, and aligned `newWeek` columns to a new data
frame. Raw counts and positivity are preserved, and the input object is
never modified.

## Usage

``` r
apply_ignition_labels(
  data,
  labels,
  anchor_week = NULL,
  n_weeks_col = NULL,
  require_all = TRUE
)
```

## Arguments

- data:

  Canonical surveillance data.

- labels:

  Named integer vector, or a `page_ignition_label` object.

- anchor_week:

  Common aligned anchor. Defaults to the median supplied label, rounded
  down as in
  [`alignIgnition()`](https://lennon-li.github.io/PAGe/reference/alignIgnition.md).

- n_weeks_col:

  Optional column containing each season's total week count. If omitted,
  the maximum observed weekF is used per season.

- require_all:

  Logical; require a label for every season in `data`.

## Value

A new data frame with `iWeek`, `phase`, and `newWeek`.
