# Prepare Stage-2 M1 features from aligned prospective data

Computes standardized columns required by Stage-2 training/prediction:

- `y_now, N_now` from `y/N` (or `x/n`)

- `d1_now, d2_now` from `d1_link/d2_link` if present, else `d1/d2`

- ignition week `ign_weekF` from `iWeek` or `ignition` or `ignD`
  fallback

- `logit_f_eff` = `omega(t_rel;Kr)` \* template logit, where
  `omega(t;Kr)=clamp(t/Kr,0,1)` and `t_rel=weekF-ign_weekF`

- `z_ema` EWMA on observed logit positivity using `alpha_state`

- `logN_now` = log(N_now)

## Usage

``` r
plot_stage2_joint_fit_by_season(
  out_m1,
  feat_full,
  dat_raw = NULL,
  ign_hat_df = NULL,
  exclude_season_re = FALSE,
  exclude_newseason_terms = FALSE,
  facet_by_lead = TRUE,
  trim_preign = TRUE
)
```

## Arguments

- out_m1:

  Fitted Stage-2 result containing `fit` and `spec`.

- feat_full:

  Feature data used for plotting.

- dat_raw:

  Optional raw observations.

- ign_hat_df:

  Optional estimated ignition weeks by season.

- exclude_season_re:

  Logical; omit the season random effect.

- exclude_newseason_terms:

  Logical; omit terms unavailable for new seasons.

- facet_by_lead:

  Logical; facet forecasts by horizon.

- trim_preign:

  Logical; omit pre-ignition rows.

## Value

A data.table with original columns plus derived feature columns.

## Details

Requires helper functions already in your file: `wrap_week()`,
`ewma_recursive()`, `make_ref_logit_fun_from_template()`.
