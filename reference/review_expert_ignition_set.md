# Build expert ignition review objects for all seasons

Build expert ignition review objects for all seasons

## Usage

``` r
review_expert_ignition_set(
  data,
  seasons = NULL,
  existing_annotations = NULL,
  ...
)
```

## Arguments

- data:

  Surveillance data containing the seasons to review.

- seasons:

  Optional character vector of season identifiers to review. Defaults to
  all seasons present in `data`.

- existing_annotations:

  Optional existing annotation object or list of annotations to overlay.

- ...:

  Additional arguments passed to
  [`review_expert_ignition()`](https://lennon-li.github.io/PAGe/reference/review_expert_ignition.md).

## Value

A named list of `page_expert_ignition_review_v2` objects.
