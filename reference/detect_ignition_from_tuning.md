# Fit ignition classifier and run season-level detection

Convenience wrapper that calls
[`fitIgnition()`](https://lennon-li.github.io/PAGe/reference/fitIgnition.md)
with the supplied knob arguments and then passes the fitted object to
[`detectIgnitionBySeason_M0v2()`](https://lennon-li.github.io/PAGe/reference/detectIgnitionBySeason_M0v2.md)
using the best parameters from a previous LOSO tuning run.

## Usage

``` r
detect_ignition_from_tuning(
  tuned,
  alignedD,
  score_col = "p_cls_p",
  keep_signals = TRUE,
  iWeek = TRUE,
  verbose = TRUE,
  fit_base = TRUE,
  fit_slope = FALSE,
  fit_fs = FALSE,
  event_k = 1L,
  lead = 1L,
  A_pre = 6L,
  B_post = 6L,
  k_week = 6L,
  k_p = 8L
)
```

## Arguments

- tuned:

  List returned by a LOSO tuning step (e.g.
  [`tuneIgnitionGrid_M0v2()`](https://lennon-li.github.io/PAGe/reference/tuneIgnitionGrid_M0v2.md)).
  Must contain `$best_params` as a named list of M0 gate thresholds.

- alignedD:

  Data frame of aligned historical seasons passed to
  [`fitIgnition()`](https://lennon-li.github.io/PAGe/reference/fitIgnition.md).

- score_col:

  Character; column in `alignedD` used as the GAM classifier score
  (default `"p_cls_p"`).

- keep_signals:

  Logical; if `TRUE` retains per-week signal columns in the output
  (default `TRUE`).

- iWeek:

  Logical; if `TRUE` also estimates `iWeek_hat` (default `TRUE`).

- verbose:

  Logical; controls progress messages (default `TRUE`).

- fit_base, fit_slope, fit_fs:

  Logicals passed to
  [`fitIgnition()`](https://lennon-li.github.io/PAGe/reference/fitIgnition.md)
  controlling which GAM smooth terms to include.

- event_k, lead, A_pre, B_post, k_week, k_p:

  Integer/numeric knobs passed to
  [`fitIgnition()`](https://lennon-li.github.io/PAGe/reference/fitIgnition.md).

## Value

Output of
[`detectIgnitionBySeason_M0v2()`](https://lennon-li.github.io/PAGe/reference/detectIgnitionBySeason_M0v2.md);
a list with `$data` (per-week signals), `$by_season` (per-season
summaries), and optionally `$compare` (truth vs estimate).
