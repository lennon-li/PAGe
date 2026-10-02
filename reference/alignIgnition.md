# Align within-season week index by shifting ignition to a common anchor week

Align within-season week index by shifting ignition to a common anchor
week

## Usage

``` r
alignIgnition(
  outs,
  season_col = "season",
  week_col = "weekF",
  nweek_col = "nW_true",
  template_weeks = .page_template_weeks()
)
```

## Arguments

- outs:

  list of flagIgnition() outputs (each has \$data and \$ignition)

- season_col:

  season column name (default "season")

- week_col:

  within-season week column name (default "weekF")

- nweek_col:

  calendar length output column (default "nW_true"); derived from season
  start year

- template_weeks:

  Template domain used for fitting (default 52). Rows shifted outside
  this domain are retained and flagged, but are excluded by
  \`estimateRef()\` rather than wrapped back into the season.

## Value

data.frame with newWeek and phase_inSeason added; attributes:
anchorWeek, ignD
