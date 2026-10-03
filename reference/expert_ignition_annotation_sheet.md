# Create a blank ignition annotation sheet

Create a blank ignition annotation sheet

## Usage

``` r
expert_ignition_annotation_sheet(
  data,
  annotator,
  annotation_version,
  positivity_version
)
```

## Arguments

- data:

  Surveillance data used to populate the sheet.

- annotator:

  Non-empty annotator identifier.

- annotation_version:

  Non-empty annotation version label.

- positivity_version:

  Non-empty positivity-definition version label.

## Value

A data frame with one blank annotation row per season.
