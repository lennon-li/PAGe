# Predict an M2 offset correction and return its residual link contribution.

The returned \`m1_p\` is computed directly from the offset, while
\`p_hat\` includes only the fitted correction. No capping, switching, or
online bias adjustment is applied here.

## Usage

``` r
predict_m2_offset_correction(fit, newdata)
```

## Arguments

- fit:

  A fitted GAM or the list returned by \`fit_m2_offset_correction()\`.

- newdata:

  Prediction rows containing \`logit_f_eff\` and all terms used by the
  fitted correction.

## Value

A data frame containing the M1 probability, corrected probability,
corrected linear predictor, and residual link contribution.
