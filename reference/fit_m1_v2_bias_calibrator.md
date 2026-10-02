# Fit the M1-v2 early-bias calibrator

Learns one scalar timing-location correction entirely inside the
historical training set. For each historical season, an inner M1-v2
library is trained on all other seasons, predictions are generated at
the first few primary post-M0 origins, and the season-balanced
early-weighted mean signed error is estimated. The returned offset is
the negative of that mean bias.

## Usage

``` r
fit_m1_v2_bias_calibrator(
  library,
  data,
  peak_truth,
  activation_table,
  n_origins = 4L,
  candidate_step = 0.2
)
```

## Arguments

- library:

  Full historical \`page_m1_v2_library\` to which the calibrator will be
  attached conceptually.

- data:

  The same completed historical surveillance data used to fit
  \`library\`.

- peak_truth:

  The same peak-truth table used to fit \`library\`.

- activation_table:

  Data frame with one row per training season and columns \`season\`,
  \`activation_origin_week\`, and \`activation_week_decimal\`.
  Activation values must themselves be cross-fitted/causal historical M0
  outputs; this function does not generate M0 values.

- n_origins:

  Number of earliest primary origins per inner season used for
  calibration. Default 4 is the frozen exploratory choice.

- candidate_step:

  Candidate peak-time grid spacing for inner predictions.

## Value

A \`page_m1_v2_calibrator\` object.

## Details

This calibrator is intentionally low dimensional. It does not modify
M1-C passage probabilities or the shape of the M1-F posterior.
