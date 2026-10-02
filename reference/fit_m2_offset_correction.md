# Fit a regularized binomial M2 offset correction.

Fit a regularized binomial M2 offset correction.

## Usage

``` r
fit_m2_offset_correction(
  data,
  k_z = 3L,
  k_sp = 0L,
  method = "REML",
  gamma = 1.4,
  penalize_intercepts = FALSE,
  intercept_sp = -1,
  season_balance = FALSE
)
```

## Arguments

- data:

  Stacked lead-specific rows with binomial counts and M1/features.

- k_z:

  Basis size for the horizon-specific z_ema correction. Zero disables
  the smooth and leaves only the residual intercepts.

- k_sp:

  Basis size for the optional horizon-specific logit-spread correction.
  Zero disables this term.

- method:

  GAM fitting method, normally "REML".

- gamma:

  Smoothness selection multiplier passed to mgcv.

- penalize_intercepts:

  Penalize horizon intercepts toward zero.

- intercept_sp:

  Intercept penalty; -1 estimates it by REML.

- season_balance:

  Give each training season equal total trial weight.

## Value

A list containing the fitted GAM, visible formula, fit warnings,
training seasons, and effective degrees of freedom.
