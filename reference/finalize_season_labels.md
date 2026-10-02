# Finalize ignition and peak labels together

Finalize ignition and peak labels together

## Usage

``` r
finalize_season_labels(
  review,
  ignition_weekF,
  peak_weekF,
  annotator = NULL,
  note = NULL
)
```

## Arguments

- review:

  An object returned by
  [`review_ignition_label()`](https://lennon-li.github.io/PAGe/reference/review_ignition_label.md).

- ignition_weekF:

  User-selected ignition weekF.

- peak_weekF:

  User-selected peak weekF.

- annotator:

  Optional person or process identifier.

- note:

  Optional rationale shared by both labels.

## Value

A class `page_season_labels` object containing named `ignition_labels`
and `peak_labels` vectors.
