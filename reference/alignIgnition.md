# Align within-season week index by shifting ignition to a common anchor week

Align within-season week index by shifting ignition to a common anchor
week

## Usage

``` r
alignIgnition(
  outs,
  season_col = "season",
  week_col = "weekF",
  nweek_col = "nW_true"
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

  season length column name (default "nW_true"); if missing uses
  max(weekF) per season

## Value

data.frame with newWeek and phase_inSeason added; attributes:
anchorWeek, ignD
