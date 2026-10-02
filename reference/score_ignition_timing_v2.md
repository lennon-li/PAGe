# Score fractional M0 detections against midpoint ignition labels

Score fractional M0 detections against midpoint ignition labels

## Usage

``` r
score_ignition_timing_v2(detection, labels)
```

## Arguments

- detection:

  Output from
  [`detectIgnitionBySeason_M0v2_timing()`](https://lennon-li.github.io/PAGe/reference/detectIgnitionBySeason_M0v2_timing.md).

- labels:

  Timing-v2 labels used as truth.

## Value

A per-season data frame with numeric truth, estimate, and error.
