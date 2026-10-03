# Prepare arbitrary surveillance data for the PAGe pipeline

Converts a user-supplied weekly data frame with source-specific column
names to the canonical surveillance contract used by PAGe. This function
does not fetch, filter, or aggregate observations; the input must
already contain exactly one row per season and week.

## Usage

``` r
prepare_page_data(
  data,
  outcome_col,
  week_col,
  season_col,
  total_col = NULL,
  negative_col = NULL,
  positivity_col = NULL,
  week_type = c("within_season", "mmwr"),
  start_week = 27L,
  start_year_col = NULL,
  date_col = NULL,
  mmwr_year_col = NULL,
  tolerance = 1e-08
)
```

## Arguments

- data:

  A data frame containing weekly observations.

- outcome_col:

  Character scalar naming the positive-count column.

- week_col:

  Character scalar naming the week column. With
  `week_type = "within_season"`, values are already PAGe week indices.

- season_col:

  Character scalar naming the season identifier column.

- total_col:

  Optional character scalar naming the total-observation column. At
  least one of `total_col` and `negative_col` is required.

- negative_col:

  Optional character scalar naming the negative-count column. At least
  one of `total_col` and `negative_col` is required.

- positivity_col:

  Optional character scalar naming a supplied positivity column. If
  supplied, it is checked against the counts.

- week_type:

  Week representation: `"within_season"` for an existing PAGe-style week
  index, or `"mmwr"` for calendar/MMWR week numbers that must be
  converted using `start_week`.

- start_week:

  Integer MMWR week used as the season origin when `week_type = "mmwr"`;
  defaults to 27.

- start_year_col:

  Optional character scalar naming the season start-year column.
  Required for non-YYYY-YY season labels when `week_type = "mmwr"`.

- date_col:

  Optional character scalar naming a calendar date column. Used with
  `week_type = "mmwr"` to derive the season and validate the mapped
  week. Mutually informative with `mmwr_year_col`.

- mmwr_year_col:

  Optional character scalar naming the MMWR year column. Used with
  `week_type = "mmwr"` to resolve the season when season labels are not
  in `YYYY-YY` form. Supply at most one of `start_year_col` and
  `mmwr_year_col`.

- tolerance:

  Numeric tolerance passed to
  [`prepare_surveillance_data`](https://lennon-li.github.io/PAGe/reference/prepare_surveillance_data.md)
  for consistency checks.

## Value

A data frame with canonical columns `season`, `weekF`, `y`, `N`, `p`,
and `neg`, followed by unmapped source columns. The result can be passed
directly to
[`train_pipeline()`](https://lennon-li.github.io/PAGe/reference/train_pipeline.md)
or the stage APIs.

## Details

The outcome is the positive-count column, not a percentage. Supply
either a total-count column, a negative-count column, or both. When
calendar/MMWR weeks are supplied, `weekF` is computed from `start_week`
and a season start year. The start year is read from `start_year_col`,
or is inferred from season labels of the form `YYYY-YY`.
