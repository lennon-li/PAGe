# Apply fractional timing to an M1 alignment result

This opt-in adapter reuses the existing M1 result but re-computes
aligned coordinates from the numeric ignition estimate without integer
coercion.

## Usage

``` r
fractional_alignment_coordinates_v2(current_data, m0_result, anchor_week)
```

## Arguments

- current_data:

  Weekly current-season data.

- m0_result:

  Output from
  [`run_ignition_weekly_timing_v2()`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly_timing_v2.md).

- anchor_week:

  Numeric aligned anchor.

## Value

A list containing numeric `iWeek_hatF` and `currentD`.
