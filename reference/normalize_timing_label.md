# Normalize one user timing label

A timing-v2 label is one integer week or two consecutive integer weeks.
A singleton `w` is normalized to `c(w - 1, w)`. The original input and
normalized pair are retained, and their midpoint is exposed as the
numeric timing target. This function does not modify any legacy label
vector.

## Usage

``` r
normalize_timing_label(
  label,
  event_type = c("ignition", "peak"),
  n_weeks = 52L,
  observed_weekF = NULL
)
```

## Arguments

- label:

  One or two integer week numbers.

- event_type:

  Either `"ignition"` or `"peak"`.

- n_weeks:

  Number of weeks in the season.

- observed_weekF:

  Optional observed peak week. It must be one of the supplied peak
  weeks; omit it only before review-based peak resolution.

## Value

A normalized timing label object.
