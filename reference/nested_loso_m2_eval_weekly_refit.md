# Evaluate a Stage-2 spec using weekly GAM refit on the test season

Variant of `nested_loso_m2_eval()` that uses
[`refit_stage2_weekly()`](https://lennon-li.github.io/PAGe/reference/refit_stage2_weekly.md)
instead of predicting from a frozen fit. For each post-ignition
evaluation week on the held-out test season, the GAM is refitted on all
training-season aligned data plus the current-season observations
accumulated to that week.

## Usage

``` r
nested_loso_m2_eval_weekly_refit(
  allD,
  fold,
  m1_test_preds,
  spec,
  m1_train_preds = NULL,
  eval_window = 12L,
  horizons = c(1L, 2L),
  manual_labels = NULL,
  flag_args = list(p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L, min_window =
    10L, w_min = 21L, w_max = 21L, d2_relax = -0.01),
  verbose = TRUE
)
```

## Arguments

- allD:

  Full multi-season data frame.

- fold:

  Fold object from
  [`nested_loso_build_fold()`](https://lennon-li.github.io/PAGe/reference/nested_loso_build_fold.md).

- m1_test_preds:

  Held-out-season M1 predictions.

- spec:

  Stage-2 specification.

- m1_train_preds:

  Optional training-season M1 predictions.

- eval_window:

  Maximum post-ignition evaluation week.

- horizons:

  Forecast horizons.

- manual_labels:

  Optional named ignition labels.

- flag_args:

  Named list forwarded to
  [`flagIgnition()`](https://lennon-li.github.io/PAGe/reference/flagIgnition.md).

- verbose:

  Logical.

## Value

Same structure as `nested_loso_m2_eval()`: list with `scores` and
`predictions`.

## Details

This matches the deployment semantics of
`run_m2_forecast(mode="weekly_refit")`.
