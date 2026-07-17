# Plot observed vs fitted positivity by season, with ignition week in title

Plot observed vs fitted positivity by season, with ignition week in
title

## Usage

``` r
plotSeasonCurves(df, x = "weekF")
```

## Arguments

- df:

  Data frame containing at least: season, weekF, y, N, fit. Also needs
  either: - iWeek (ignition weekF repeated within season), OR - ignition
  (logical TRUE at ignition row)

- x:

  Character. X-axis column name (default "weekF").

## Value

A ggplot object.
