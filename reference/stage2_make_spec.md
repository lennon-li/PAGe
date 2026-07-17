# Create a Stage-2 training specification (hyperparameters + derived objects)

Builds a spec list that defines:

- template shift `delta`

- template ramp length `Kr`

- training buffer window `Kb` (weeks before ignition)

- spline basis sizes `k_*`

- template entry mode `T` (smooth/offset/none)

- derived: `spec$formula` and `spec$exclude_newseason`

## Usage

``` r
stage2_make_spec(
  delta = 0L,
  Kr = 3L,
  k_f = 6L,
  alpha_state = 0.3,
  Kb = 0L,
  leads = c(1L, 2L),
  T = c("S", "O", "N"),
  template_mode = NULL,
  use_ramp = NULL,
  k_e = 6L,
  k_n = 0L,
  k_de = 0L,
  k_r = 0L,
  k_w = 0L,
  k_s = 0L,
  k_sp = 0L,
  bs_week = "ts",
  bs_fs_marginal = "tp",
  use_season_re = TRUE,
  lambda_w = 0,
  w_floor = 0.05,
  anchorWeek = 20L,
  bias_alpha = 0.2,
  bias_beta = 0,
  K = NULL,
  pre_buffer = NULL
)
```

## Arguments

- delta:

  Integer template shift in weeks.

- Kr:

  Integer ramp length (\>=1). Kr=1 means "immediate" ramp after ignition
  week.

- k_f:

  Integer basis size for template smooth (only used when `T="S"`).

- alpha_state:

  Numeric EWMA decay in (0,1) used to compute `z_ema`.

- Kb:

  Integer buffer (weeks before ignition) included in training window:
  training rows satisfy `weekF >= ign_weekF - Kb`.

- leads:

  Integer horizons (usually `c(1L,2L)`).

- T:

  Template entry mode: `"S"` = smooth term; `"O"` = offset; `"N"` = no
  template.

- template_mode:

  Back-compat alias of `T`: "smooth"/"offset"/"none".

- use_ramp:

  Deprecated. If `FALSE`, forces `Kr=1`.

- k_de:

  Integer basis size for dz_ema smooth term. 0L disables it.

- k_r, k_sp:

  Integer basis sizes for residual and alignment-spread smooths.

- k_w, k_s, k_e, k_n:

  Integer basis sizes for smooth terms. Set any to 0L to disable the
  corresponding term.

- bs_week:

  Basis name for week smooths (typical: "ts").

- bs_fs_marginal:

  Marginal basis used by factor-smooth `bs="fs"` via `xt=list(bs=...)`.

- use_season_re:

  Back-compat flag (season RE is always included).

- lambda_w, w_floor:

  Training time-decay rate and minimum weight.

- anchorWeek:

  Reference-curve ignition anchor week.

- bias_alpha, bias_beta:

  Holt level and trend correction rates.

- K:

  Deprecated alias of `Kr`.

- pre_buffer:

  Deprecated alias of `Kb`.

## Value

A list `spec` containing hyperparameters plus:

- `spec$formula` joint model formula

- `spec$exclude_newseason` terms to exclude for new-season prediction

- `spec$best_row` small data.frame for printing

## Details

This function expects two project helpers to exist:

- `stage2_build_joint_formula(spec)`

- `stage2_exclude_newseason(spec)`
