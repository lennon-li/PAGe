# Persistence baseline forecasts

Forecasts the target week as the last observed positivity at or before
the origin week (last observation carried forward). Only observations
with \`weekF \<= origin\` influence the prediction, so the baseline is
leakage-safe for prospective evaluation.

## Usage

``` r
baseline_persistence(data, season, origins, horizons = 1:2)
```

## Arguments

- data:

  Canonical multi-season surveillance data.

- season:

  Single season identifier to forecast.

- origins:

  Numeric vector of whole origin weeks.

- horizons:

  Integer vector of positive forecast horizons. The target week is
  \`origin + horizon\`. Defaults to \`1:2\`.

## Value

A data frame with one row per origin/horizon pair and columns
\`season\`, \`origin\`, \`target\`, \`horizon\`, \`outcome\`,
\`prediction\`, \`t_since_target\`, \`N_lead\`, and \`model\`.
Predictions are clamped to \`\[1e-6, 1 - 1e-6\]\`. \`outcome\` and
\`N_lead\` are \`NA\` when the target week is not observed, and
\`t_since_target\` is \`NA\` because persistence does not use ignition
timing.
