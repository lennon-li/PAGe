# Create a continuous season timing calendar

The opt-in timing-v2 API represents week `w` by the half-open interval
`[w, w + 1)`. Thus, `19.2` means 20 percent of the way from the start of
observed week 19 to the start of observed week 20. Observed `weekF`
values remain integer week identifiers. Calendar dates are optional, but
must be supplied when converting between dates and timing coordinates.

## Usage

``` r
new_timing_calendar(
  season = NULL,
  n_weeks = NULL,
  week_starts = NULL,
  week_ends = NULL
)
```

## Arguments

- season:

  Optional season identifier.

- n_weeks:

  Number of weeks in the season. Both 52 and 53 week seasons are
  supported. When omitted, the length of `week_starts` is used; undated
  calendars default to 52 weeks.

- week_starts:

  Optional `Date` vector of week start dates.

- week_ends:

  Optional `Date` vector of exclusive week end dates. When omitted, each
  end is the next start date and the final end is seven days after the
  final start.

## Value

An object of class `page_timing_calendar_v2` containing the season
calendar and the documented continuous coordinate convention.
