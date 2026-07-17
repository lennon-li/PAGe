# Build a single LOSO fold: training alignment + reference curve

For a held-out test season, filters to training seasons, runs the M0
detection pipeline (derivatives -\> ignition -\> alignment), fits the
reference curve, and learns alignment hyperparams. Everything needed to
run M1 on this fold.

## Usage

``` r
nested_loso_build_fold(
  allD,
  test_season,
  exclude_seasons = NULL,
  k_deriv = 10L,
  k_ref = 25L,
  n_weeks = 52L,
  ref_method = "fs",
  manual_labels = NULL,
  flag_args = list(p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L, min_window =
    10L, w_min = 21L, w_max = 21L, d2_relax = -0.01),
  verbose = TRUE
)
```

## Arguments

- allD:

  Data frame with all seasons (columns: season, week, y, neg, ...).

- test_season:

  Character scalar – the held-out season.

- exclude_seasons:

  Character vector of seasons to drop entirely (before fold splitting).

- k_deriv:

  Integer; basis dimension for
  [`estimateDerivs()`](https://lennon-li.github.io/PAGe/reference/estimateDerivs.md).

- k_ref:

  Integer; basis dimension for
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md).

- n_weeks:

  Integer; period for reference GAM (default 52).

- ref_method:

  Reference-curve method passed to
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md).

- manual_labels:

  Optional named list of manual ignition labels.

- flag_args:

  Named list of arguments forwarded to
  [`flagIgnition()`](https://lennon-li.github.io/PAGe/reference/flagIgnition.md).

- verbose:

  Logical; print progress messages.

## Value

A named list with components:

- ref:

  Output of
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md)
  on training seasons.

- hyper:

  Output of
  [`learn_alignment_hyperparams()`](https://lennon-li.github.io/PAGe/reference/learn_alignment_hyperparams.md).

- aligned_train:

  Aligned training data (output of
  [`alignIgnition()`](https://lennon-li.github.io/PAGe/reference/alignIgnition.md)).

- template_df:

  Two-column tibble (newWeek, fit) from the per-fold ref curve.

- train_seasons:

  Character vector of training season labels.

- test_season:

  The held-out season label (echoed back).
