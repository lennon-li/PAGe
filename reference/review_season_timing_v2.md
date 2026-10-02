# Review one season for timing-v2 labels

Produces the week-level plot and summary used before a user assigns
ignition and peak labels. The review is read-only; labels are recorded
separately by
[`finalize_season_timing_v2()`](https://lennon-li.github.io/PAGe/reference/finalize_season_timing_v2.md).

## Usage

``` r
review_season_timing_v2(
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

An object of class `page_timing_review_v2`, retaining the signals,
candidate summaries, plot, and data provenance.
