# Determine whether the epidemic peak has passed

Uses the peak estimate from \[align_forecast_pipeline_dilate()\] and the
last observed week in the current season to decide if the peak is
already in the past.

## Usage

``` r
peak_status_from_align(res, currentD, use_ci = TRUE, buffer_weeks = 0L)
```

## Arguments

- res:

  List returned by \[align_forecast_pipeline_dilate()\]; must have a
  \`peak\` element with \`t_peak\` and \`t_peak_ci\`.

- currentD:

  Data frame of current season data with at least a \`newWeek\` column
  (the same scale used in the alignment).

- use_ci:

  Logical; if \`TRUE\` (default), we declare the peak "passed" once the
  last observed week is beyond the \*upper\* CI bound for the peak. If
  \`FALSE\`, we use the point estimate only.

- buffer_weeks:

  Non-negative integer; additional weeks beyond the peak (or upper CI)
  required before declaring the peak passed.

## Value

A list with components:

- peak_passed:

  logical, \`TRUE\` if we consider the peak passed.

- last_obs_week:

  last observed \`newWeek\` in \`currentD\`.

- t_peak:

  estimated peak week on the same \`newWeek\` scale.

- t_peak_ci:

  numeric length-2 vector with the 95% CI for the peak.

- threshold_week:

  week threshold used for the decision.
