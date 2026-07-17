# Mark in-season weeks based on a positivity threshold

Given the output \`res\` from \[align_forecast_pipeline_dilate()\], this
function finds the first week the fitted curve exceeds \`threshold\` and
the first week after the peak where it falls back below \`threshold\`.
It also marks each week as "in-season" or not.

## Usage

``` r
mark_season_weeks(res, threshold = 0.05, min_run = 1L)
```

## Arguments

- res:

  A list returned by \[align_forecast_pipeline_dilate()\], containing at
  least \`pred_df\` (with columns \`newWeek\`, \`p_hat\`) and \`peak\`
  (with \`t_peak\`).

- threshold:

  Numeric positivity threshold (e.g. \`0.05\` for 5%).

- min_run:

  Integer, minimum run length of consecutive weeks above the threshold
  to declare the start of the season.

## Value

A list with elements:

- \`start_week\` - first surveillance week above \`threshold\`.

- \`end_week\` - first week after the peak where fitted positivity falls
  below \`threshold\`.

- \`in_season\` - logical vector the same length as
  \`res\$pred_df\$newWeek\`, indicating in-season weeks.
