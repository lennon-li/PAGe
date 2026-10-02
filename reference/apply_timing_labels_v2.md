# Apply timing-v2 labels to canonical surveillance data

Applies the numeric ignition midpoint as the alignment and phase
reference, adds the observed peak week when supplied, and attaches the
complete timing evidence to the returned data frame. A single finalized
object or a list of finalized objects may be supplied for multiple
seasons.

## Usage

``` r
apply_timing_labels_v2(
  data,
  labels,
  anchor_week = NULL,
  n_weeks_col = NULL,
  require_all = TRUE
)
```

## Arguments

- data:

  Canonical or preparable surveillance data.

- labels:

  A `page_season_timing_v2` object, a `page_timing_labels_v2` object, or
  a list of those objects.

- anchor_week:

  Common aligned anchor passed to
  [`apply_ignition_labels()`](https://lennon-li.github.io/PAGe/reference/apply_ignition_labels.md).

- n_weeks_col:

  Optional column containing each season's total week count. When
  omitted, the count recorded with each timing label is used.

- require_all:

  Logical; require an ignition label for every season.

## Value

A new data frame with legacy integer `iWeek`, numeric `iWeekF`, `phase`,
numeric `newWeek`, and observed `peak_weekF`, plus timing evidence
attributes.
