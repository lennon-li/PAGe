# Summarise alignment fit as a one-row tibble

Convenience formatter for the result of
\[align_forecast_pipeline_dilate()\] or similar alignment routines.

## Usage

``` r
makeTable(res)
```

## Arguments

- res:

  List with elements \`tau\`, \`delta\`, \`fallback_reason\`, and
  \`peak\` (where \`peak\` contains \`t_peak\`, \`t_peak_ci\`, and
  \`p_peak\`).

## Value

A one-row tibble with columns \`tau_hat\`, \`delta_hat\`, \`fallback\`,
\`Peak week\`, \`Peak week (LCL)\`, \`Peak week (UCL)\`, and \`Peak
probability\`.
