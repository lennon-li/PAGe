# Compare M1 and M2 forecasts

Computes descriptive, matched-row comparisons for two forecast columns.
The primary summaries give every season equal weight: rows are first
averaged within season and those season summaries are then averaged.
Pooled row summaries are retained for reference. All deltas are M2 minus
M1, so a negative delta is better for these loss metrics. This function
is forecast only; M1 peak performance must be evaluated separately
because M2 cannot estimate peaks.

## Usage

``` r
compare_m1_m2(
  forecasts,
  outcome_col,
  m1_col,
  m2_col,
  season_col,
  origin_col,
  target_col,
  horizon_col,
  tolerance = 0,
  denominator_col = NULL
)
```

## Arguments

- forecasts:

  Data frame with one row per season, origin, target, and horizon, and
  columns for the observed proportion and both predictions.

- outcome_col, m1_col, m2_col:

  Character scalar column names in \`forecasts\` for the observed
  proportion and M1 and M2 predictions.

- season_col, origin_col, target_col, horizon_col:

  Character scalar column names in \`forecasts\` defining the unique
  forecast key.

- tolerance:

  Non-negative finite scalar maximum tolerated increase in any loss, on
  the same scale as the corresponding loss.

- denominator_col:

  Optional character scalar column name in \`forecasts\` containing
  positive test volumes. When supplied, matched forecast rows are
  weighted by this denominator; missing denominators are excluded.
  \`outcome_col\` remains a proportion in \[0, 1\], not a success count.

## Value

A named list with \`forecast\` and \`recommendation\` entries. Forecast
entries contain matched counts, exclusions, transparent loss rows,
equal-season and pooled summaries, and per-season summaries. The
recommendation contains \`decision\`, machine-readable \`reasons\`, and
the applied tolerance.

## Details

The recommendation is descriptive rather than inferential. \`use_m2\` is
returned only when both forecast losses are no worse than \`tolerance\`
and at least one is strictly lower. No significance test or automatic
promotion is performed.

When \`denominator_col\` is supplied, forecast MAE and Bernoulli NLL use
the test-volume-weighted form \`sum(N \* loss) / sum(N)\` within each
reported group. Equal-season aggregates then average those season-level
weighted losses. The NLL is the cross-entropy loss for the supplied
proportion and prediction; no binomial-coefficient constant is included.
