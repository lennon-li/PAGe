# Run the full M0 -\> M1 -\> M2 walk-forward pipeline for one season

Thin wrapper around
[`run_m0_detection()`](https://lennon-li.github.io/PAGe/reference/run_m0_detection.md),
[`run_m1_alignment()`](https://lennon-li.github.io/PAGe/reference/run_m1_alignment.md),
and
[`run_m2_forecast()`](https://lennon-li.github.io/PAGe/reference/run_m2_forecast.md).
Use the individual functions directly if you need to inspect
intermediate results, override the ignition week, or stop after peak
detection without running M2.

## Usage

``` r
run_prospective_pipeline(
  kit,
  current_data,
  walk_start = 5L,
  manual_ign_week = NA_integer_,
  mode = c("frozen", "weekly_refit"),
  season = NULL,
  verbose = TRUE,
  timing_mode = c("legacy", "fractional"),
  m2_v2_weekly_data = NULL,
  m2_v2_b_handoff = NULL,
  m2_v2_b_gate_review = NULL
)

run_pipeline(kit, current_data, timing_mode = c("legacy", "fractional"), ...)
```

## Arguments

- kit:

  A kit list returned by
  [`load_prospective_kit()`](https://lennon-li.github.io/PAGe/reference/load_prospective_kit.md).

- current_data:

  Data frame for the current season.

- walk_start:

  Integer. Minimum evaluation week (default `5L`).

- manual_ign_week:

  Integer or `NA_integer_`. Manual ignition override.

- mode:

  Character runtime mode. `"frozen"` uses the validated production GAM;
  `"weekly_refit"` refits using kit history.

- season:

  Optional single season identifier. Used only when `current_data` has
  no `season` column. A unique `kit$current_season` or
  `kit$forecast_season` is also accepted.

- verbose:

  Logical. Emit progress messages (default `TRUE`).

- timing_mode:

  Character. `"legacy"` preserves integer timing; `"fractional"` carries
  numeric ignition and aligned-week coordinates.

- m2_v2_weekly_data:

  Optional typed A/B weekly panel for the governed M2-v2 shadow path. If
  absent, M2-v2 is reported unavailable and legacy M2 behavior is
  unchanged.

- m2_v2_b_handoff:

  Optional type-B soft-timing handoff.

- m2_v2_b_gate_review:

  Optional reviewed B gate-opening object.

- ...:

  Additional arguments passed by the `run_pipeline()` alias.

## Value

A list with `params_df`, `m1_curves`, `m2_preds`, `pred_df`, `last_obs`,
and `ign_out`. The plot fields are consumed directly by
[`plot_forecast()`](https://lennon-li.github.io/PAGe/reference/plot_forecast.md).
