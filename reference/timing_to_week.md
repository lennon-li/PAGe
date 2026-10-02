# Convert continuous timing coordinates to observed integer weeks

Convert continuous timing coordinates to observed integer weeks

## Usage

``` r
timing_to_week(calendar, timing, allow_na = TRUE)
```

## Arguments

- calendar:

  A `page_timing_calendar_v2` object.

- timing:

  Numeric coordinates in the season.

- allow_na:

  Whether missing coordinates should return missing weeks.

## Value

Integer observed `weekF` values.
