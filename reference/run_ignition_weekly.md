# Run M0 ignition detection week-by-week (walk-forward)

Applies
[`detectIgnition_oneSeason()`](https://lennon-li.github.io/PAGe/reference/detectIgnition_oneSeason.md)
at each evaluation week in `currentSeason`, building an as-of snapshot
for each week from `start_week` onward. Returns the full week-by-week
detection table together with scalar summary values for the locked
ignition week and the estimated ignition `iWeek_hat`.

## Usage

``` r
run_ignition_weekly(
  currentSeason,
  ign_fit_or_gam = NULL,
  params,
  start_week = 5L,
  week_col = "weekF"
)
```

## Arguments

- currentSeason:

  Data frame for the season to evaluate. Must contain `weekF` (or the
  column named in `week_col`), `y`, and either `N` or `neg`. Optional
  columns: `season`, `p`.

- ign_fit_or_gam:

  Fitted ignition classifier (output of
  [`fitIgnition()`](https://lennon-li.github.io/PAGe/reference/fitIgnition.md)
  or an `mgcv` GAM), or `NULL` when `params$use_cls = FALSE`.

- params:

  Named list of M0 threshold parameters (e.g. `tuned$best_params`).

- start_week:

  Integer; first `weekF` value to evaluate (default 5L).

- week_col:

  Character; name of the week column in `currentSeason` (default
  `"weekF"`).

## Value

A list with four elements:

- df:

  Tibble with one row per evaluated week containing per-week signals,
  gate conditions (`ok_*`), and `iWeek_hat_dynamic`.

- iWeek_hat_dynamic_last:

  Integer; dynamic ignition estimate at the last evaluated week.

- iWeek_hat_locked:

  Integer; earliest `iWeek_hat_dynamic` across all weeks (lock-in
  value).

- ign_week_locked:

  Integer; first week where detection fired (`ignite_ok_now == TRUE`).
