# Apply M1-v2 early-bias calibration to forecast summaries

Applies the learned scalar location offset to peak-time summary
statistics. The raw posterior and all passage probabilities remain
unchanged. This is a reporting calibration, not a second posterior
update.

## Usage

``` r
m1_v2_apply_bias_calibration(forecast, calibrator)
```

## Arguments

- forecast:

  A \`page_m1_v2_forecast\`.

- calibrator:

  A \`page_m1_v2_calibrator\` fitted for the same historical library as
  \`forecast\`.

## Value

A one-row data frame containing raw and calibrated peak summaries.
