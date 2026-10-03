# Review one season for expert decimal ignition annotation

Creates a Plotly review without assigning truth. Peak truth is derived
separately by the retrospective GAM procedure.

## Usage

``` r
review_expert_ignition(
  data,
  season = NULL,
  existing_annotation = NULL,
  weekF_start = NULL,
  weekF_end = NULL,
  show_counts = TRUE
)
```

## Arguments

- data:

  Surveillance data containing the season to review.

- season:

  Optional season identifier. Required when `data` holds more than one
  season.

- existing_annotation:

  Optional existing `page_expert_ignition_annotation_v2` object to
  overlay on the review.

- weekF_start, weekF_end:

  Optional numeric display-window bounds on the `weekF` axis. Defaults
  to the full observed range.

- show_counts:

  Logical; include positive and tested counts in the hover text.

## Value

A `page_expert_ignition_review_v2` object.
