# Fit the M1-v2 peak-relative historical library

Fits one retrospective smooth per completed training season, aligns each
season to supplied continuous peak truth, normalizes by fitted peak
height, and learns two one-component peak-relative shape models: one for
future-peak inference and one extending through peak +3 for passage
inference.

## Usage

``` r
fit_m1_v2_library(
  data,
  peak_truth,
  k = 8L,
  grid_step = 0.01,
  tau_step = 0.1,
  amplitude_grid = seq(0.08, 0.44, by = 0.02)
)
```

## Arguments

- data:

  Completed historical surveillance data.

- peak_truth:

  Data frame with \`season\` and \`peak_week_decimal\`.

- k:

  Basis dimension for the retrospective GAM smoother.

- grid_step:

  Fine-grid resolution for retrospective smoothing.

- tau_step:

  Peak-relative training grid resolution.

- amplitude_grid:

  Positive candidate peak-amplitude values integrated out by the timing
  likelihood. Defaults to the frozen Influenza-A grid.

## Value

A \`page_m1_v2_library\` object.

## Details

The first shape component is constrained so every admissible deformation
retains its maximum at relative time zero. This prevents the shape
nuisance from exchanging a time shift for the target peak time.
