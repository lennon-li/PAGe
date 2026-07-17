# Bundle trained artifacts for prospective deployment

Assembles M0, M1, and M2 training outputs into the format returned by
[`load_prospective_kit()`](https://lennon-li.github.io/PAGe/reference/load_prospective_kit.md),
ready for use with
[`run_pipeline()`](https://lennon-li.github.io/PAGe/reference/run_prospective_pipeline.md),
[`run_m0()`](https://lennon-li.github.io/PAGe/reference/run_m0_detection.md),
[`run_m1()`](https://lennon-li.github.io/PAGe/reference/run_m1_alignment.md),
and
[`run_m2()`](https://lennon-li.github.io/PAGe/reference/run_m2_forecast.md).
Optionally saves reference and M2 bundles to disk.

## Usage

``` r
assemble_kit(
  m0,
  m1,
  m2_model,
  best_spec_id = NULL,
  save_ref_path = NULL,
  save_m2_path = NULL
)
```

## Arguments

- m0:

  Output of
  [`tune_m0()`](https://lennon-li.github.io/PAGe/reference/tune_m0.md).

- m1:

  Output of
  [`build_m1()`](https://lennon-li.github.io/PAGe/reference/build_m1.md).

- m2_model:

  Output of
  [`train_m2()`](https://lennon-li.github.io/PAGe/reference/train_m2.md).

- best_spec_id:

  Character label for the best M2 spec (optional; taken from
  `build_m2()$best_spec_id`).

- save_ref_path:

  Character. If set, saves the reference bundle (`ref_production.rds`
  format) to this path.

- save_m2_path:

  Character. If set, saves the M2 bundle (`m2_production.rds` format) to
  this path.

## Value

A kit list compatible with all `run_*()` functions.
