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
  stage1_file = "stage1_tuning.rds",
  compatibility = c("strict", "locked_defaults", "legacy")
)
```

## Arguments

- data_dir:

  Path to the directory containing the RDS files (passed to
  `normalizePath(..., mustWork = TRUE)`).

- ref_file:

  Filename of the production reference cache (default
  `"ref_production.rds"`). Must contain `$ref`, `$hyper`, `$M1_PARAMS`,
  and optionally `$flag_args`, `$manual_labels`, `$hist_data`.

- m2_file:

  Filename of the production M2 model (default `"m2_production.rds"`).
  Must contain a fitted `bam`/`gam` object and `$spec`. Optionally also
  contains `$template_df`, and `$m1_train_preds`.

- stage1_file:

  Filename of the M0 ignition tuning results (default
  `"stage1_tuning.rds"`). Must contain `$best_params`.

- compatibility:

  Compatibility policy. `"strict"` (default) requires the canonical
  saved `M1_PARAMS` and `m2_production$spec`. `"locked_defaults"`
  permits a missing `M1_PARAMS` by using the centralized locked defaults
  with a warning. `"legacy"` also enables deprecated artifact discovery
  and fallback behavior with warnings.

## Value

A named list with slots: `ref`, `hyper`, `M1_PARAMS`, `m0_params`,
`m2_production`, `best_spec`, `flag_args`, `manual_labels`, `hist_data`,
`m1_train_preds`, and `template_df`.
