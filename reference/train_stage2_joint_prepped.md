# Fit a Stage-2 joint GAM from a pre-prepared stacked dataset

Fits a [`mgcv::bam()`](https://rdrr.io/pkg/mgcv/man/bam.html) Stage-2
model to a stacked multi-lead, multi-season data frame. The formula and
all structural choices are governed by `spec` (from
[`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md)).
Time-decay training weights are computed from `t_since` when
`lambda_w > 0`. Training rows are restricted to post-ignition
observations (`post_ign == TRUE`).

## Usage

``` r
train_stage2_joint_prepped(
  d_all,
  best_mean_nll,
  template_df = NULL,
  spec = NULL,
  k_e = 6L,
  k_n = 6L,
  method = "REML",
  lambda_w = 0,
  w_floor = 0,
  verbose = FALSE
)
```

## Arguments

- d_all:

  Data frame produced by
  [`prep_stage2_joint()`](https://lennon-li.github.io/PAGe/reference/prep_stage2_joint.md),
  containing stacked multi-lead observations with columns `post_ign`,
  `lead`, `y_lead`, `N_lead`, and any covariates required by `spec`.

- best_mean_nll:

  List or 1-row data frame of tuned hyperparameters. Used to set
  defaults for `spec` when `spec = NULL`.

- template_df:

  Optional data frame with columns `newWeek` and `fit` for the reference
  template curve. Required when `spec$template_mode != "none"`.

- spec:

  Optional spec list from
  [`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md).
  When `NULL` a default parsimonious spec is constructed from
  `best_mean_nll`.

- k_e, k_n:

  Integer basis dimensions for EMA and log-N smooth terms (used only
  when `spec = NULL`; defaults 6L and 6L).

- method:

  Character; GAM fitting method. Defaults to `"REML"`; switched to
  `"fREML"` when discrete approximation is active.

- lambda_w:

  Numeric; time-decay weight rate (0 = uniform weights; default 0).

- w_floor:

  Numeric; minimum weight floor applied after the decay interval
  `t_floor_start` (default 0).

- verbose:

  Logical; print fitting diagnostics (default `FALSE`).

## Value

A list with `fit` (the `bam` object), `train_data`, `tuned`, `spec`,
`lambda_w`, and `feature_ranges`.
