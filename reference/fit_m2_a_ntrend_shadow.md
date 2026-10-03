# Tune a causal test-volume trend for the M2-A state forecast

Evaluates causal log-test-volume slopes while preserving window zero as
an explicit null model. This is shadow-only and does not modify the
canonical v3 release.

## Usage

``` r
fit_m2_a_ntrend_shadow(
  weekly_data,
  windows = 0:4,
  min_origin_week = 13L,
  min_chronological_train_seasons = 3L,
  off_tolerance = 1e-04
)
```

## Arguments

- weekly_data:

  Weekly A surveillance data with season, weekF, y, and N.

- windows:

  Integer causal lookback windows. Must include zero, the explicit OFF
  candidate.

- min_origin_week:

  Earliest forecast origin.

- min_chronological_train_seasons:

  Minimum number of prior seasons for chronological evaluation.

- off_tolerance:

  Absolute mean-NLL tolerance within which the zero/OFF candidate is
  preferred.

## Value

A `page_m2_a_ntrend_shadow` artifact containing LOSO and chronological
scores, the selected window, and a full-history shadow fit.
