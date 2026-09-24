# Return the explicitly selected Legacy Model settings

The Legacy Model pins `p_thr = 0.002`, `p_sum_thr = 0.07`, and ignition
weeks 8–26. Its M1 prior is \\a \sim N(0, 0.10^2)\\ and \\\log(b) \sim
N(0, 0.05^2)\\. These settings are opt-in and do not change the
package's general training defaults. Pass `$m0_params` to
[`build_m0()`](https://lennon-li.github.io/PAGe/reference/build_m0.md),
`$m0_grid` to
[`tune_m0()`](https://lennon-li.github.io/PAGe/reference/tune_m0.md),
and `$m1_ab_prior` to
[`align_forecast_pipeline_dilate()`](https://lennon-li.github.io/PAGe/reference/align_forecast_pipeline_dilate.md).

## Usage

``` r
legacy_model_settings()
```

## Value

A named list containing the Legacy Model M0 parameters, tuning grid, and
M1 calibration prior.
