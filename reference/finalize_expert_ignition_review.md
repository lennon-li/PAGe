# Finalize numeric expert ignition after review

Finalize numeric expert ignition after review

## Usage

``` r
finalize_expert_ignition_review(
  review,
  ignition_week_decimal,
  annotator,
  annotation_version,
  positivity_version,
  ignition_interval = NULL,
  comment = NULL,
  annotated_at = Sys.time()
)
```

## Arguments

- review:

  A `page_expert_ignition_review_v2` object from
  [`review_expert_ignition()`](https://lennon-li.github.io/PAGe/reference/review_expert_ignition.md).

- ignition_week_decimal:

  Expert decimal ignition week.

- annotator:

  Non-empty annotator identifier.

- annotation_version:

  Non-empty annotation version label.

- positivity_version:

  Non-empty positivity-definition version label.

- ignition_interval:

  Optional ordered two-value decimal ignition interval containing
  `ignition_week_decimal`.

- comment:

  Optional free-text comment.

- annotated_at:

  Annotation timestamp; defaults to the current time.

## Value

A `page_expert_ignition_annotation_v2` object.
