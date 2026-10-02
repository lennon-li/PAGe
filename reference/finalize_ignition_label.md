# Finalize a reviewed ignition label

Explicitly records a user's selected week after reviewing the output of
[`review_ignition_label()`](https://lennon-li.github.io/PAGe/reference/review_ignition_label.md).
The selected week must be an observed week inside the declared candidate
window.

## Usage

``` r
finalize_ignition_label(review, weekF, annotator = NULL, note = NULL)
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

## Value

An object of class `page_ignition_label`; its `labels` element is a
named integer vector suitable for training APIs.
