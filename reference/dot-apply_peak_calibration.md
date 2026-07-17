# Apply Bayesian shrinkage + bias correction to a peak estimate

Internal helper used by
[`run_alignment_prospective()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective.md)
when `cal` is provided. Applies two corrections sequentially:

1.  **Shrinkage (C):** pulls `t_peak` toward the historical prior mean,
    weighted by the ratio of prior variance to data variance (CI width).
    Early-season wide CIs → heavy shrinkage.

2.  **Bias correction (A):** subtracts the residual bias predicted by a
    GAM fitted on LOSO errors as a function of `t_since_ign`.

Returns calibrated `t_peak` and updated CI bounds (posterior variance).

## Usage

``` r
.apply_peak_calibration(
  t_peak,
  t_peak_lo,
  t_peak_hi,
  t_since_ign,
  cal,
  level = 0.95
)
```

## Arguments

- t_peak:

  Numeric. Raw peak estimate in `newWeek` space.

- t_peak_lo:

  Numeric. Lower CI bound in `newWeek` space.

- t_peak_hi:

  Numeric. Upper CI bound in `newWeek` space.

- t_since_ign:

  Numeric. Weeks since true ignition (`eval_week - iWeek_hat`).

- cal:

  List. Output of
  [`fit_peak_calibration()`](https://lennon-li.github.io/PAGe/reference/fit_peak_calibration.md).

- level:

  Numeric. CI level (default `0.95`).

## Value

Named list with `t_peak`, `t_peak_lo`, `t_peak_hi`.
