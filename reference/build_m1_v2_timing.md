# Build the governed M1-v2 timing artifact

Fits the peak-aligned low-rank M1-v2 historical library and its strictly
inner-cross-fitted early-bias calibrator. This timing artifact is
independent of the legacy M1 alignment curves still used by the current
M2 implementation.

## Usage

``` r
build_m1_v2_timing(
  allD,
  peak_truth,
  activation_table,
  k = 8L,
  grid_step = 0.01,
  tau_step = 0.1,
  amplitude_grid = seq(0.08, 0.44, by = 0.02),
  calibration_origins = 4L,
  calibration_candidate_step = 0.2,
  passage_candidate_step = 0.2
)
```

## Arguments

- allD:

  Completed historical surveillance data.

- peak_truth:

  Retrospective peak truth with columns \`season\` and
  \`peak_week_decimal\`.

- activation_table:

  Historical cross-fitted M0 activation table with \`season\`,
  \`activation_origin_week\`, and \`activation_week_decimal\`.

- k, grid_step, tau_step:

  Retrospective smoothing and peak-relative library controls passed to
  \`fit_m1_v2_library()\`.

- amplitude_grid:

  Candidate peak-amplitude integration grid forwarded to the M1-v2
  library. Defaults to the frozen Influenza-A grid.

- calibration_origins:

  Number of earliest post-M0 primary origins used by the nested scalar
  timing calibrator.

- calibration_candidate_step:

  Candidate grid spacing used only in the inner calibration replay.

- passage_candidate_step:

  Candidate grid spacing used in inner cross-fitted M1-C policy
  selection.

## Value

A \`page_m1_v2_stage\` object containing \`library\`, \`calibrator\`,
and a deterministic artifact identity.
