# Score peak timing against the observed peak week

Score peak timing against the observed peak week

## Usage

``` r
score_peak_timing_v2(predictions, labels, prediction_col = "peak_weekF")
```

## Arguments

- predictions:

  Data frame with `season` and a numeric predicted peak column.

- labels:

  Timing-v2 labels.

- prediction_col:

  Name of the prediction column.

## Value

A data frame with observed truth, retained second label, and error.
