# Predict from an M2-A test-volume-trend shadow artifact

Uses only observations at or before the forecast origin. Window zero
reproduces the A1-style state model without a test-volume-trend term.

## Usage

``` r
predict_m2_a_ntrend_shadow(artifact, weekly_data, origin_week, horizons = c(1L, 2L))
```

## Arguments

- artifact:

  Result of
  [`fit_m2_a_ntrend_shadow()`](https://lennon-li.github.io/PAGe/reference/fit_m2_a_ntrend_shadow.md).

- weekly_data:

  One-season weekly data with weekF, y, and N.

- origin_week:

  Forecast origin week.

- horizons:

  Integer forecast horizons.

## Value

A data frame of shadow forecasts with the selected N-trend window and
enabled/off state.
