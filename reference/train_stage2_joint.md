# Train Stage-2 joint model

Preferred usage: pass only `spec`. The function will use `spec$best_row`
to construct features and `spec$formula` to fit the model.

## Usage

``` r
train_stage2_joint(
  dat,
  template_df,
  spec = NULL,
  best_mean_nll = NULL,
  pre_buffer = NULL,
  alpha_state = NULL,
  k_e = 6L,
  k_n = 6L,
  ign_week_df = NULL,
  method = "REML",
  lambda_w = 0,
  w_floor = NULL,
  m1_preds = NULL,
  verbose = TRUE
)
```

## Arguments

- dat:

  Multi-season input data.

- template_df:

  Template curve.

- spec:

  Stage-2 spec created by
  [`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md).

- best_mean_nll:

  Legacy tuned row (delta,K,k_f,alpha_state) if `spec=NULL`.

- pre_buffer:

  Legacy pre-ignition training buffer.

- alpha_state:

  Legacy EWMA rate.

- k_e, k_n:

  Legacy smooth basis dimensions.

- ign_week_df:

  Optional ignition week estimates for alignment in held-out/new
  seasons.

- method:

  mgcv method.

- lambda_w, w_floor:

  Training time-decay rate and minimum weight.

- m1_preds:

  Optional M1 walk-forward predictions used for stacking.

- verbose:

  logical.

## Details

Backward compatible: if `spec=NULL`, you may pass `best_mean_nll` and
legacy basis sizes (k_e, k_n, k_1, k_2).
