# Number of epidemiological weeks in a full season cycle

Returns 52 or 53 depending on the ISO epidemiological week structure of
the given year. Uses the epidemiological week number of Dec 28, which is
always in the last epiweek of the year.

## Usage

``` r
get_full_cycle_weeks(year)
```

## Arguments

- year:

  Integer calendar year (e.g., 2026).

## Value

Integer, typically 52 or 53.

## Examples

``` r
if (FALSE) { # \dontrun{
get_full_cycle_weeks(2025)
get_full_cycle_weeks(2026)
} # }
```
