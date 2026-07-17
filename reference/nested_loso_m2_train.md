# Train M2 model on one LOSO fold

Prepares aligned training data with prospective derivatives, then trains
the M2 GAM using the fold's per-fold `template_df` (leakage-free
reference curve). Optionally injects M1 stacking predictions.

## Usage

``` r
nested_loso_m2_train(
  fold,
  m1_train_preds = NULL,
  spec,
  method = "REML",
  verbose = TRUE
)
```

## Arguments

- fold:

  Output of
  [`nested_loso_build_fold()`](https://lennon-li.github.io/PAGe/reference/nested_loso_build_fold.md).

- m1_train_preds:

  M1 walk-forward predictions for training seasons (output of
  [`nested_loso_m1_train()`](https://lennon-li.github.io/PAGe/reference/nested_loso_m1_train.md)),
  or `NULL` to skip stacking.

- spec:

  M2 hyperparameter spec object (as used by
  [`train_stage2_joint()`](https://lennon-li.github.io/PAGe/reference/train_stage2_joint.md)).

- method:

  GAM fitting method (default `"REML"`).

- verbose:

  Logical; print progress.

## Value

Output of
[`train_stage2_joint()`](https://lennon-li.github.io/PAGe/reference/train_stage2_joint.md)
(list with `fit`, `train_data`, …), or `NULL` if training fails.
