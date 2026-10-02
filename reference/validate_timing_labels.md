# Validate and normalize independent ignition and peak labels

Users may provide either event independently. Each supplied event
accepts one integer week or exactly two consecutive integer weeks. A
singleton is expanded to the preceding pair, for example
`18 -> c(17, 18)`. The normalized pair is retained as uncertainty
metadata. Ignition uses the pair midpoint as its numeric target. Peak
uses the observed peak week as its evaluation truth; the adjacent second
label is retained as provenance.

## Usage

``` r
validate_timing_labels(
  ignition = NULL,
  peak = NULL,
  season = NULL,
  n_weeks = NULL,
  calendar = NULL,
  peak_observed = NULL
)
```

## Arguments

- ignition:

  Optional ignition label.

- peak:

  Optional peak label.

- season:

  Optional season identifier.

- n_weeks:

  Number of weeks in the season.

- calendar:

  Optional timing calendar. Its week count must agree with `n_weeks`.

- peak_observed:

  Optional observed peak week selected from `peak`.

## Value

A class `page_timing_labels_v2` object.
