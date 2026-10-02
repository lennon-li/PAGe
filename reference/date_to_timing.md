# Convert dates to continuous season timing coordinates

Convert dates to continuous season timing coordinates

## Usage

``` r
date_to_timing(calendar, dates, allow_na = TRUE)
```

## Arguments

- calendar:

  A `page_timing_calendar_v2` object with dates.

- dates:

  Dates to convert.

- allow_na:

  Whether missing dates should return missing coordinates.

## Value

Numeric timing coordinates.
