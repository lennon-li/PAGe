# Build the joint Stage-2 mgcv formula from a spec

Uses your naming convention: - ramp length is Kr (used in features, not
formula) - buffer is Kb (used in stacking, not formula) - spline basis
sizes are k\_\*

## Usage

``` r
stage2_build_joint_formula(spec)
```

## Arguments

- spec:

  A spec list from stage2_make_spec().

## Value

An R formula suitable for mgcv::bam().

## Details

Required columns in the stacked training data: y_lead, N_lead, lead,
season, season_h, logit_f_eff, newWeek, z_ema, z_resid, logN_now, dz_ema
(some may be unused depending on k\_\*).
