# Run prospective M0 with fractional ignition timing

Run prospective M0 with fractional ignition timing

## Usage

``` r
run_ignition_weekly_timing_v2(currentSeason, params, start_week = 5L, ...)
```

## Arguments

- currentSeason:

  One-season weekly surveillance data frame.

- params:

  M0 detector parameters.

- start_week:

  First week to evaluate.

- ...:

  Additional arguments are reserved for future detector controls.

## Value

The legacy weekly output with `iWeek_hat_dynamicF`, `iWeek_hat_lockedF`,
and integer brackets.
