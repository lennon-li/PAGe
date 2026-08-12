# Bundle trained artifacts for prospective deployment

Assembles M0, M1, and M2 training outputs into the format returned by
[`load_prospective_kit()`](https://lennon-li.github.io/PAGe/reference/load_prospective_kit.md),
ready for use with
[`run_pipeline()`](https://lennon-li.github.io/PAGe/reference/run_prospective_pipeline.md),
[`run_m0()`](https://lennon-li.github.io/PAGe/reference/run_m0_detection.md),
[`run_m1()`](https://lennon-li.github.io/PAGe/reference/run_m1_alignment.md),
and
[`run_m2()`](https://lennon-li.github.io/PAGe/reference/run_m2_forecast.md).
Optionally saves reference and M2 bundles to disk. Legacy stage outputs
remain supported. If any input is a governed stage artifact, all three
inputs must be frozen, share the same season selection, and carry a
consistent upstream identity chain. The returned governed kit records
the selection, stage artifact identities, and a deterministic governance
identity.

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

  Frozen `page_m0_fit` from
  [`freeze_m0()`](https://lennon-li.github.io/PAGe/reference/freeze_m0.md),
  or a legacy M0 output compatible with
  [`tune_m0()`](https://lennon-li.github.io/PAGe/reference/tune_m0.md).

- m1:

  Frozen `page_m1_fit` from
  [`freeze_m1()`](https://lennon-li.github.io/PAGe/reference/freeze_m1.md),
  or a legacy output from
  [`build_m1()`](https://lennon-li.github.io/PAGe/reference/build_m1.md).

- m2_model:

  Frozen `page_m2_fit` from
  [`freeze_m2()`](https://lennon-li.github.io/PAGe/reference/freeze_m2.md),
  or a legacy output from
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

A kit list compatible with all `run_*()` functions. Governed inputs add
`season_selection`, `stage_artifact_ids`, and `governance_id`.
