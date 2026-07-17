# Run M0 ignition detection for the current season

Detects epidemic ignition from the current season data using pre-trained
M0 thresholds. Optionally overrides the automatic estimate with a manual
week. Returns the resolved ignition week and the full
[`run_ignition_weekly()`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly.md)
output for downstream M1 alignment.

## Usage

``` r
run_m0_detection(
  kit,
  current_data,
  manual_ign_week = NA_integer_,
  verbose = TRUE
)

run_m0(kit, current_data, ...)
```

## Arguments

- kit:

  A kit list returned by
  [`load_prospective_kit()`](https://lennon-li.github.io/PAGe/reference/load_prospective_kit.md).

- current_data:

  Data frame for the current season. Must contain `weekF`, `y`, `N`,
  `neg`, `p`.

- manual_ign_week:

  Integer or `NA_integer_`. When set, overrides the M0 automatic
  ignition estimate with a known value.

- verbose:

  Logical. Emit progress messages (default `TRUE`).

- ...:

  Additional arguments forwarded by the `run_m0()` alias.

## Value

A list with:

- ign_out:

  Full output of
  [`run_ignition_weekly()`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly.md),
  with `iWeek_hat_locked` and `ign_week_locked` updated if overridden.

- iWeek_locked:

  Resolved ignition week (`NA` if not detected).

- overridden:

  Logical; `TRUE` if the manual override was applied.
