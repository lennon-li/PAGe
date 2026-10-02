# Prospective multi-template alignment for several ensemble weightings

Computes the expensive per-template alignment once for \`currentSeason\`
and then re-ensembles for each entry of \`weight_sets\`. This is exact:
each element of the result is identical to calling
[`run_alignment_prospective_multi()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective_multi.md)
with that weighting, because the weighting parameters only enter the
softmax reweighting step (see
[`align_multi_template`](https://lennon-li.github.io/PAGe/reference/align_multi_template.md)).
Intended for tuning loops that sweep `slope_weight` / temperature at a
fixed alignment configuration.

## Usage

``` r
run_alignment_prospective_multi_weights(
  currentSeason,
  ref,
  hyper,
  ign_out,
  weight_sets,
  use_ci = TRUE,
  buffer_weeks = 0L,
  allow_scale = NULL,
  level = 0.95,
  min_obs = 4L,
  curvature_ratio = 1,
  trough_weight = 0.1,
  rise_weight = 1,
  peak_decay = 0.3,
  top_k = NULL,
  blend_alpha = 1,
  spread_method = c("between", "total"),
  timing_mode = c("legacy", "fractional"),
  peak_stabilization = c("legacy", "causal"),
  peak_state = NULL,
  stabilizer_max_jump_weeks = 2
)
```

## Arguments

- currentSeason, ref, hyper, ign_out, use_ci, buffer_weeks, allow_scale,
  level, :

  min_obs,curvature_ratio,trough_weight,rise_weight,peak_decay,top_k,
  blend_alpha,spread_method,timing_mode As in
  [`run_alignment_prospective_multi()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective_multi.md).

- weight_sets:

  List of weighting overrides. Each element must be a list with
  `slope_weight`, `temperature`, `slope_window`, `dynamic_temp`, and
  `dynamic_temp_pivot`.

## Value

A list with the same length as `weight_sets`; each element has the
structure returned by
[`run_alignment_prospective_multi()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective_multi.md).
