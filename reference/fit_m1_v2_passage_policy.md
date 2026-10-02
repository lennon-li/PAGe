# Fit the M1-v2 passage-confirmation policy

Selects the hybrid M1-C thresholds using only inner cross-fitted
historical passage posteriors from the supplied training seasons.
Selection prioritizes false-early confirmations, then their magnitude,
misses by peak+2, and delay.

## Usage

``` r
fit_m1_v2_passage_policy(
  library,
  data,
  peak_truth,
  activation_table,
  candidate_step = 0.2,
  high_thresholds = 0.95,
  low_thresholds = c(0.1, 0.2, 0.3, 0.4),
  drop_fractions = c(0.03, 0.05, 0.08, 0.1),
  fast_drop_fraction = 0,
  min_post_activation = c(3L, 4L)
)
```

## Arguments

- library:

  Full historical \`page_m1_v2_library\`.

- data:

  Completed historical surveillance data used by \`library\`.

- peak_truth:

  Peak truth used by \`library\`.

- activation_table:

  Cross-fitted historical M0 activation table; same schema as
  \`fit_m1_v2_bias_calibrator()\`.

- candidate_step:

  Candidate peak-time grid spacing in inner passage replays.

- high_thresholds, low_thresholds, drop_fractions, min_post_activation:

  Predeclared candidate policy grid.

- fast_drop_fraction:

  Optional extra drop floor for the one-week fast branch. Default 0
  reproduces the validated rule family.

## Value

A \`page_m1_v2_passage_policy\`.
