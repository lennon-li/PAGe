# Record user supplied ignition and peak timing labels

Each event accepts one week or two consecutive weeks. A singleton is
expanded to the preceding pair. Ignition is scored at the pair midpoint.
For peak, the observed week is selected from the supplied pair by the
larger observed positivity (ties select the earlier week); the other
week remains second-label provenance.

## Usage

``` r
finalize_season_timing_v2(
  review,
  ignition,
  peak,
  n_weeks = NULL,
  calendar = NULL,
  annotator = NULL,
  note = NULL
)
```

## Arguments

- review:

  An object returned by
  [`review_season_timing_v2()`](https://lennon-li.github.io/PAGe/reference/review_season_timing_v2.md).

- ignition:

  One ignition week or two consecutive ignition weeks.

- peak:

  One peak week or two consecutive peak weeks.

- n_weeks:

  Optional number of weeks in the season. When omitted, the larger of 52
  and the maximum observed `weekF` is used, or the calendar's count is
  used when `calendar` is supplied.

- calendar:

  Optional `page_timing_calendar_v2` object.

- annotator:

  Optional person or process identifier.

- note:

  Optional free-text rationale for the labels.

## Value

An object of class `page_season_timing_v2` containing normalized labels,
scoring references, evidence rows, and review provenance.
