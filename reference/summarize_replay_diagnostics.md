# Summarize aggregate replay diagnostics

Computes disclosure-safe overall and by-horizon diagnostics from replay
predictions. This summary contains no prediction rows or surveillance
values.

## Usage

``` r
summarize_replay_diagnostics(predictions, interval_level = 0.9, eps = 1e-12)
```

## Arguments

- predictions:

  Prediction data frame containing \`p_hat\`, observed probability
  (\`p_obs\`, or \`y_lead\`/\`N_lead\`), and \`lead\`.

- interval_level:

  Nominal central coverage for \`p_lo\`/\`p_hi\` intervals.

- eps:

  Probability clipping value.

## Value

A list with one-row \`overall\` and aggregate \`horizon\` data frames.
Calibration and interval metrics use \`NA\` plus a status when they
cannot be estimated safely.
