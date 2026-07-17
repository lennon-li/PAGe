# Run M2 forecast using M1 alignment outputs

For each evaluation week in `m1_result$per_week`, builds M2 covariates
from the M1 alignment output and predicts 1- and 2-week-ahead
positivity.

## Usage

``` r
run_m2_forecast(
  kit,
  current_data,
  m1_result,
  mode = c("frozen", "weekly_refit"),
  verbose = TRUE
)

run_m2(kit, current_data, m1_result, ...)
```

## Arguments

- kit:

  A kit list returned by
  [`load_prospective_kit()`](https://lennon-li.github.io/PAGe/reference/load_prospective_kit.md).

- current_data:

  Data frame for the current season.

- m1_result:

  Output of
  [`run_m1_alignment()`](https://lennon-li.github.io/PAGe/reference/run_m1_alignment.md).

- mode:

  Character. `"frozen"` (default) or `"weekly_refit"`.

- verbose:

  Logical. Emit progress messages (default `TRUE`).

- ...:

  Additional arguments forwarded by the `run_m2()` alias.

## Value

A list with `m2_preds`: tibble with columns `eval_week`, `h`,
`target_weekF`, `m1_p`, `m1_lo`, `m1_hi`, `m2_p`, `m2_lo`, `m2_hi`.

## Details

Two modes are supported via `mode`:

- `"frozen"` (default):

  Predicts directly from the frozen production GAM stored in
  `kit$m2_production$fit`. This matches the validated production
  evaluation path.

- `"weekly_refit"`:

  Each week, combines `kit$hist_data` with current-season observations
  up to that week and refits the Stage-2 GAM via
  [`refit_stage2_weekly()`](https://lennon-li.github.io/PAGe/reference/refit_stage2_weekly.md).
  Requires `kit$hist_data` (produced by `docs/run.qmd` and loaded by
  [`load_prospective_kit()`](https://lennon-li.github.io/PAGe/reference/load_prospective_kit.md)).
