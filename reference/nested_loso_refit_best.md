# Refit M2 on all historical data with a chosen spec

After selecting the best spec from nested LOSO, this function refits M2
on the full aligned historical dataset using the production reference
curve. Returns the fit object ready for deployment or plotting.

## Usage

``` r
nested_loso_refit_best(
  alignedD_prosp,
  template_df,
  spec,
  m1_preds = NULL,
  method = "REML",
  verbose = TRUE
)
```

## Arguments

- alignedD_prosp:

  Aligned historical data with prospective derivatives (output of
  [`add_prospective_derivs_link()`](https://lennon-li.github.io/PAGe/reference/add_prospective_derivs_link.md)).

- template_df:

  Reference curve template (newWeek, fit) - typically from the
  production (full-data)
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md).

- spec:

  M2 spec object (from LOSO best or
  [`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md)).

- m1_preds:

  Optional data frame of M1 walk-forward predictions for all training
  seasons (output of
  [`m1_walkforward_multi()`](https://lennon-li.github.io/PAGe/reference/m1_walkforward_multi.md)).
  When supplied, `logit_f_eff` in the training data is replaced with
  M1-based values, matching the richer feature representation available
  at deployment time. \*\*This should be the same `m1_preds` that will
  be passed to
  [`refit_stage2_weekly()`](https://lennon-li.github.io/PAGe/reference/refit_stage2_weekly.md)
  at deployment\*\*, so the frozen GAM and the weekly refit are trained
  on the same feature space. Save it in `m2_production.rds` (as
  `m1_train_preds`) and load via
  [`load_prospective_kit()`](https://lennon-li.github.io/PAGe/reference/load_prospective_kit.md).

- method:

  GAM fitting method (default `"REML"`).

- verbose:

  Logical; print progress.

## Value

Output of
[`train_stage2_joint()`](https://lennon-li.github.io/PAGe/reference/train_stage2_joint.md) -
a list with `fit`, `train_data`, `spec`, `tuned`, etc.
