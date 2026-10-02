# Review a season before assigning its retrospective ignition label

Creates a transparent, reproducible review object for one canonical PAGe
season. The object contains week-level positivity signals, Wilson
intervals, simple candidate summaries, and a ggplot object for visual
inspection. No label is assigned by this function and the input is never
modified.

## Usage

``` r
review_ignition_label(
  data,
  season = NULL,
  smooth_window = 3L,
  p_threshold = 0.01,
  candidate_window = NULL,
  peak_tolerance = 1e-12,
  confidence = 0.95
)
```

## Arguments

- data:

  Canonical surveillance data containing `season`, `weekF`, `y`, and `N`
  (or `neg`). It must contain one season after optional filtering; use
  `season` to select one season from multi-season data.

- season:

  Optional season identifier. Required when `data` contains more than
  one season.

- smooth_window:

  Positive integer used for the centred moving average.

- p_threshold:

  Positivity threshold shown in the plot and used for candidate
  summaries.

- candidate_window:

  Optional two-integer weekF range in which candidates may be
  considered. The observed range is used when omitted.

- peak_tolerance:

  Non-negative tolerance for treating observed positivity values as tied
  peak candidates.

- confidence:

  Confidence level for Wilson intervals.

## Value

An object of class `page_ignition_review` with `signals`, `summary`,
`candidates`, `plot`, and a `provenance` list. Pass it to
[`finalize_ignition_label()`](https://lennon-li.github.io/PAGe/reference/finalize_ignition_label.md)
after visual review.
