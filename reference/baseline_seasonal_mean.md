# Seasonal-mean baseline forecasts

Forecasts the target week as the test-count-weighted mean positivity
across \`train_seasons\`. Calendar alignment matches the target calendar
week in every training season. Ignition alignment matches the training
week that shares the test season's offset from ignition, which requires
a named \`ignition\` vector. The test season is never used to form
predictions, and it is an error for \`season\` to appear in
\`train_seasons\`.

## Usage

``` r
baseline_seasonal_mean(
  data,
  season,
  train_seasons,
  origins,
  horizons = 1:2,
  align = c("calendar", "ignition"),
  ignition = NULL
)
```

## Arguments

- data:

  Canonical multi-season surveillance data.

- season:

  Single season identifier to forecast.

- train_seasons:

  Character vector of seasons contributing the seasonal mean. Must
  exclude \`season\`.

- origins:

  Numeric vector of whole origin weeks.

- horizons:

  Integer vector of positive forecast horizons. The target week is
  \`origin + horizon\`. Defaults to \`1:2\`.

- align:

  Alignment mode, \`"calendar"\` (default) or \`"ignition"\`.

- ignition:

  Optional named numeric vector of ignition weeks keyed by season.
  Required for \`align = "ignition"\` and used for \`t_since_target\`
  when supplied. When supplied it must name every training season and
  \`season\` for ignition alignment, and at least \`season\` otherwise.

## Value

A data frame with the same columns and clamping contract as
\[baseline_persistence()\], with \`model\` set to \`"seasonal_mean"\`
and \`t_since_target\` equal to \`target - ignition\[season\]\` when
\`ignition\` is supplied, otherwise \`NA\`.
