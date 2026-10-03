# Create one expert decimal ignition annotation

Create one expert decimal ignition annotation

## Usage

``` r
new_expert_ignition_annotation(
  season,
  ignition_week_decimal,
  n_weeks = 52L,
  ignition_interval = NULL,
  annotator,
  annotation_version,
  annotated_at,
  data_snapshot_id,
  positivity_version,
  comment = NULL
)
```

## Arguments

- season:

  Non-empty season identifier.

- ignition_week_decimal:

  Expert decimal ignition week within `[1, n_weeks + 1)`.

- n_weeks:

  Integer season length (at least 2); defaults to 52.

- ignition_interval:

  Optional ordered two-value decimal interval containing
  `ignition_week_decimal`.

- annotator:

  Non-empty annotator identifier.

- annotation_version:

  Non-empty annotation version label.

- annotated_at:

  Annotation timestamp (POSIXct or string).

- data_snapshot_id:

  Non-empty identifier of the reviewed data snapshot.

- positivity_version:

  Non-empty positivity-definition version label.

- comment:

  Optional free-text comment.

## Value

A `page_expert_ignition_annotation_v2` object.
