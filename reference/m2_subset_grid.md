# Build the governed M2 offset-subset candidate grid

Enumerates the optional-term subset family: an optional horizon
intercept crossed with per-term basis sizes for \`z\`, \`u\`, and \`d\`.
A basis size of zero turns the term off; positive values must be at
least three. The all-off row (\`i0_kz0_ku0_kd0\`) is always included and
reproduces M1 exactly.

## Usage

``` r
m2_subset_grid(
  k_values = c(0L, 3L, 4L, 5L, 6L, 7L, 8L),
  k_z_values = k_values,
  k_u_values = k_values,
  k_d_values = k_values,
  k_tau_values = 0L,
  conf_scale = "none",
  alpha_state = 0.2,
  gamma = 1.4
)
```

## Arguments

- k_values:

  Default candidate basis sizes for every term.

- k_z_values, k_u_values, k_d_values:

  Per-term candidate basis sizes.

- k_tau_values:

  Candidate basis sizes for the origin-time peak-relative term. The
  stage-A default is the exact existing grid with this term off.

- conf_scale:

  Confidence-scaling values. Stage-A defaults to \`"none"\`.

- alpha_state:

  EMA decay used to build the \`z\`/\`d\` features; one value.

- gamma:

  Smoothness selection multiplier; one value \>= 1.

## Value

A data frame with stable \`id\`, component, and \`enabled_count\`
columns, ordered from simplest to most complex.
