# Load pre-built model artifacts for prospective deployment

Reads all offline-trained components from `data_dir` and returns them as
a named list (the "kit") ready for
[`run_prospective_pipeline()`](https://lennon-li.github.io/PAGe/reference/run_prospective_pipeline.md).
All heavy training (reference curve, M1 LOSO, M2 nested LOSO) must have
been completed beforehand and saved as RDS files.

## Usage

``` r
load_prospective_kit(
  data_dir,
  ref_file = "ref_production.rds",
  m2_file = "m2_production.rds",
  stage1_file = "stage1_tuning.rds"
)
```

## Arguments

- data_dir:

  Path to the directory containing the RDS files (passed to
  `normalizePath(..., mustWork = TRUE)`).

- ref_file:

  Filename of the production reference cache (default
  `"ref_production.rds"`). Must contain `$ref`, `$hyper`, and optionally
  `$M1_PARAMS`, `$flag_args`, `$manual_labels`, `$hist_data`.

- m2_file:

  Filename of the production M2 model (default `"m2_production.rds"`).
  Must contain a fitted `bam`/`gam` object. Optionally also contains
  `$spec`, `$template_df`, and `$m1_train_preds`.

- stage1_file:

  Filename of the M0 ignition tuning results (default
  `"stage1_tuning.rds"`). Must contain `$best_params`.

## Value

A named list with slots: `ref`, `hyper`, `M1_PARAMS`, `m0_params`,
`m2_production`, `best_spec`, `flag_args`, `manual_labels`, `hist_data`,
`m1_train_preds`, and `template_df`.
