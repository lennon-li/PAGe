# Evaluate M2 using a frozen GAM with walk-forward bias correction

Variant of `nested_loso_m2_eval()` that applies Holt-style
trend-augmented bias correction during walk-forward evaluation. The GAM
is trained once on historical data (frozen); at each evaluation week the
correction is updated from out-of-sample residuals and extrapolated
forward.

## Usage

``` r
nested_loso_m2_eval_frozen_bias(
  allD,
  fold,
  m2_fit,
  m1_test_preds,
  spec,
  eval_window = 12L,
  horizons = c(1L, 2L),
  bias_alpha = 0.2,
  bias_beta = 0,
  manual_labels = NULL,
  manual_labels_train = NULL,
  manual_labels_test = NULL,
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

- m2_fit:

  Output of
  [`nested_loso_m2_train()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m2_train.md)
  (the trained M2 GAM).

- m1_test_preds:

  Output of
  [`nested_loso_m1_test()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m1_test.md):
  tibble with columns `eval_weekF`, `target_weekF`, `h`, `m1_p_hat`,
  `m1_tau`.

- spec:

  Stage-2 spec from
  [`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md).

- eval_window:

  Integer; max t_since to evaluate (default 12L).

- horizons:

  Integer vector of forecast horizons (default `c(1L, 2L)`).

- bias_alpha:

  Numeric; EMA smoothing for Holt bias level (default 0.2).

- bias_beta:

  Numeric; EMA smoothing for Holt bias trend (default 0). Both bias
  settings are explicit evaluator inputs; callers may take them from a
  tuning-grid specification.

- manual_labels:

  Optional named integer vector of manual ignition labels (deprecated;
  use `manual_labels_train` and `manual_labels_test`).

- manual_labels_train:

  Optional named integer vector of manual ignition labels for training
  seasons only. Used when building training-fold ignition. Should
  exclude the held-out test season (B4 fix).

- manual_labels_test:

  Optional named integer vector of manual ignition labels for the test
  season. Default `NULL` = use prospective
  [`flagIgnition()`](https://lennon-li.github.io/PAGe/reference/flagIgnition.md)
  without override (no retrospective label leakage).

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
[`run_m2_forecast()`](https://lennon-li.github.io/PAGe/reference/run_m2_forecast.md)
and is much faster than
[`nested_loso_m2_eval_weekly_refit()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m2_eval_weekly_refit.md)
(~12x) because no GAM refitting occurs per eval week.
