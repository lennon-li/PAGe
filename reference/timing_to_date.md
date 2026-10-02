# Convert continuous timing coordinates to dates

Convert continuous timing coordinates to dates

## Usage

``` r
timing_to_date(calendar, timing, allow_na = TRUE)
```

## Arguments

- calendar:

  A dated `page_timing_calendar_v2` object.

- timing:

  Numeric coordinates in the season.

- allow_na:

  Whether missing coordinates should return missing dates.

## Value

Dates obtained by linear interpolation within the calendar week.
