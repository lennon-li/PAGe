# Build frozen retrospective peak truth v1 for one or more seasons

Uses k=8 for the point estimate and k in 5,6,8,10 to quantify smoothing
sensitivity. The sensitivity interval is diagnostic, not a confidence
interval.

## Usage

``` r
build_retrospective_peak_truth_v1(
  data,
  seasons = NULL,
  grid_step = 0.01,
  ambiguity_threshold = 1
)
```

## Arguments

- data:

  Completed surveillance data containing one or more seasons.

- seasons:

  Optional season vector. Defaults to all seasons.

- grid_step:

  Peak-location grid resolution.

- ambiguity_threshold:

  Weeks of smoothing-sensitivity range above which the peak is flagged
  ambiguous.

## Value

One-row-per-season data frame.
