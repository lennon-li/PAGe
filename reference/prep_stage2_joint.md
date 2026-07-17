# Prepare Stage-2 joint stacked data using a spec or tuned row

Prepare Stage-2 joint stacked data using a spec or tuned row

## Usage

``` r
prep_stage2_joint(
  dat,
  best_mean_nll,
  template_df,
  use_ramp = TRUE,
  leads = c(1L, 2L),
  ign_week_df = NULL,
  pre_buffer = 0L,
  alpha_state = 0.3,
  m1_preds = NULL,
  feature_ranges = NULL,
  verbose = FALSE
)
```

## Arguments

- dat:

  Multi-season data.frame with required cols: season, weekF, phase,
  newWeek, y, N.

- best_mean_nll:

  1-row object with delta, K, k_f, alpha_state.

- template_df:

  Template curve with columns newWeek and fit.

- use_ramp:

  Logical, passed through.

- leads:

  Integer leads.

- ign_week_df:

  Optional data.frame with season and iWeek_hat.

- pre_buffer:

  Integer.

- alpha_state:

  Numeric in (0,1).

- m1_preds:

  Optional M1 walk-forward predictions used for stacking.

- feature_ranges:

  Optional training feature scales reused for prediction.

- verbose:

  Logical.

## Value

data.frame stacked across leads with engineered covariates.
