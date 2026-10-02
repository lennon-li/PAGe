# Finalize a reviewed peak label

Records a user's selected observed peak week after inspecting the
review. Tied or near-tied raw maxima are exposed in `peak_candidates`; a
user may choose a scientifically justified smoothed peak when
`require_candidate = FALSE`.

## Usage

``` r
finalize_peak_label(
  review,
  weekF,
  annotator = NULL,
  note = NULL,
  require_candidate = FALSE
)
```

## Arguments

- review:

  An object returned by
  [`review_ignition_label()`](https://lennon-li.github.io/PAGe/reference/review_ignition_label.md).

- weekF:

  One observed integer weekF selected by the user.

- annotator:

  Optional person or process identifier.

- note:

  Optional free-text rationale.

- require_candidate:

  Logical; require the selection to be a reported raw peak candidate.

## Value

An object of class `page_peak_label` with a named `label` vector and
provenance.
