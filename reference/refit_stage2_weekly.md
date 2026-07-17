# Refit Stage-2 GAM with current-season data for weekly prospective forecasting

Combines all historical aligned data with the current season's
observations (formatted via `format_current_for_stage2`) and refits the
Stage-2 GAM. Call this function each week after ignition detection to
obtain an updated model that has estimated the live season's random
effect and factor-smooth.

## Usage

``` r
refit_stage2_weekly(
  current_obs,
  iWeek_used,
  hist_data,
  template_df,
  spec,
  m1_preds = NULL,
  season_label = "current",
  addFS = NULL,
  verbose = TRUE
)
```

## Arguments

- current_obs:

  data.frame with columns `weekF`, `y`, `N` (or `y`/`neg`) for the
  current season up to the current week.

- iWeek_used:

  Numeric. Detected ignition week (on weekF scale).

- hist_data:

  `alignedD_prosp` – historical aligned dataset (all past seasons).

- template_df:

  Template curve with `newWeek` and `fit`.

- spec:

  Stage-2 spec from
  [`stage2_spec_from_tuning()`](https://lennon-li.github.io/PAGe/reference/stage2_spec_from_tuning.md).

- m1_preds:

  Optional historical M1 walk-forward predictions.

- season_label:

  Character. Label for the current season (default `"current"`).

- addFS:

  Integer threshold for re-enabling the season-specific factor-smooth in
  a brand-new season refit. If `NULL` (default), the factor-smooth is
  never included in weekly refits for unseen seasons. If an integer is
  given, the original `spec$k_s` is restored once at least that many
  post-ignition origin weeks are available in `current_obs`.

- verbose:

  Logical. Print progress messages.

## Value

Output of
[`train_stage2_joint()`](https://lennon-li.github.io/PAGe/reference/train_stage2_joint.md)
on the combined dataset.
