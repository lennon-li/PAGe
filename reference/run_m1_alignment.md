# Walk-forward M1 alignment for the current season

For each evaluation week from ignition to the last observed week, aligns
the partial curve to reference templates using the 4-parameter dilation
model. Requires the output of
[`run_m0_detection()`](https://lennon-li.github.io/PAGe/reference/run_m0_detection.md).

## Usage

``` r
run_m1_alignment(kit, current_data, m0_result, walk_start = 5L, verbose = TRUE)

run_m1(kit, current_data, m0_result, ...)
```

## Arguments

- kit:

  A kit list returned by
  [`load_prospective_kit()`](https://lennon-li.github.io/PAGe/reference/load_prospective_kit.md).

- current_data:

  Data frame for the current season.

- m0_result:

  Output of
  [`run_m0_detection()`](https://lennon-li.github.io/PAGe/reference/run_m0_detection.md).

- walk_start:

  Integer. Minimum evaluation week (default `5L`). Actual start is
  `max(walk_start, iWeek_locked)`.

- verbose:

  Logical. Emit progress messages (default `TRUE`).

- ...:

  Additional arguments forwarded by the `run_m1()` alias.

## Value

A list with:

- params_df:

  Tibble with one row per eval_week of alignment params.

- m1_curves:

  Tibble of M1 forecast curves by eval_week.

- per_week:

  List with one entry per eval_week; each entry holds `ew`, `ap` (raw
  alignment output), and `season_to_ew` (data slice). Passed to
  [`run_m2_forecast()`](https://lennon-li.github.io/PAGe/reference/run_m2_forecast.md).

- m0_result:

  The M0 result passed in, carried forward for M2.

## Details

You may stop here if you only need peak detection (without M2
forecasts), or override `m0_result$iWeek_locked` before passing to M1.
