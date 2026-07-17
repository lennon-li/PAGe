# Prospective multi-template alignment wrapper

Drop-in replacement for
[`run_alignment_prospective()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective.md)
that uses
[`align_multi_template()`](https://lennon-li.github.io/PAGe/reference/align_multi_template.md)
internally. Returns the same output structure.

## Usage

``` r
run_alignment_prospective_multi(
  currentSeason,
  ref,
  hyper,
  ign_out,
  use_ci = TRUE,
  buffer_weeks = 0L,
  allow_scale = NULL,
  level = 0.95,
  min_obs = 4L,
  curvature_ratio = 1,
  trough_weight = 0.1,
  rise_weight = 1,
  peak_decay = 0.3,
  temperature = 1,
  top_k = NULL,
  blend_alpha = 1,
  slope_weight = 1,
  slope_window = 6L,
  dynamic_temp = TRUE,
  dynamic_temp_pivot = 10L
)
```

## Arguments

- currentSeason:

  Data frame for one season up to current eval_week.

- ref:

  Reference object from `estimateRef(method = "fs")`, must contain
  `eta_mat`.

- hyper:

  Alignment hyperparameters.

- ign_out:

  Ignition detection output.

- use_ci:

  Logical; use CI for peak passage detection.

- buffer_weeks:

  Integer; weeks past peak threshold.

- allow_scale:

  Logical or NULL.

- level:

  CI level.

- min_obs:

  Integer; minimum observations required.

- curvature_ratio:

  Numeric; delta gate coefficient.

- trough_weight:

  Numeric; alignment loss trough weight.

- rise_weight:

  Numeric; alignment loss rise weight.

- peak_decay:

  Numeric; exponential decay after peak.

- temperature:

  Numeric; softmax temperature.

- top_k:

  Integer or NULL; pre-filter templates.

- blend_alpha:

  Numeric 0–1; template blending.

- slope_weight, slope_window:

  Growth-rate similarity controls.

- dynamic_temp, dynamic_temp_pivot:

  Early-season temperature controls.

## Value

List with same structure as
[`run_alignment_prospective()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective.md)
output.
