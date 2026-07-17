# Format current-season observations for Stage-2 refit

Converts raw current-season surveillance data and M1 alignment outputs
into the column set required by
[`train_stage2_joint()`](https://lennon-li.github.io/PAGe/reference/train_stage2_joint.md):
`season`, `weekF`, `phase`, `newWeek`, `y`, `N`, `neg`.

## Usage

``` r
format_current_for_stage2(
  currentSeason,
  iWeek_used,
  template_df = NULL,
  spec = NULL,
  season_label = "current"
)
```

## Arguments

- currentSeason:

  data.frame with columns `weekF`, `y`, and either `N` (total tests) or
  `neg` (negative tests).

- iWeek_used:

  Integer. Ignition week on the `weekF` scale.

- template_df:

  data.frame with columns `newWeek` and `fit` (unused here but retained
  for signature compatibility with `refit_stage2_weekly`).

- spec:

  Stage-2 spec from
  [`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md).
  Must contain `spec$anchorWeek`.

- season_label:

  Character label for the current season (default `"current"`).

## Value

data.frame with the required Stage-2 columns, ready to `rbind` with
historical aligned data.
