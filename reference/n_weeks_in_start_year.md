# Number of MMWR weeks in a flu-season start year

Returns 52 for most years and 53 for years in which the last day of
December falls in MMWR week 53 (a 53-week year). Used to correctly
compute within-season week indices that wrap across the year boundary.

Variant of `n_weeks_in_start_year()` used in contexts where `MMWRweek`
is available without package qualification (e.g. inside scripts that
attach the MMWRweek namespace).

## Usage

``` r
n_weeks_in_start_year(start_year)

n_weeks_in_start_year(start_year)
```

## Arguments

- start_year:

  Integer; the calendar year containing the season anchor week 27.

## Value

Integer scalar, either 52L or 53L.

Integer scalar, either 52L or 53L.
