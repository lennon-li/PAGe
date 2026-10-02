# Build a governed M2 offset-subset configuration

Build a governed M2 offset-subset configuration

## Usage

``` r
m2_subset_config(
  h1 = NULL,
  h2 = NULL,
  alpha_state = 0.2,
  bs = "ts",
  method = "REML",
  gamma = 1.4,
  intercept_sp = -1
)
```

## Arguments

- h1, h2:

  Selected per-horizon specifications (one-row data frames, lists, or
  NULL for the all-off default).

- alpha_state:

  EMA decay used to build the \`z\`/\`d\` features, in (0, 1).

- bs:

  Basis type; only \`"ts"\` is supported.

- method:

  GAM fitting method.

- gamma:

  Smoothness selection multiplier (\>= 1).

- intercept_sp:

  Horizon-intercept penalty; -1 estimates it by REML.

## Value

A validated configuration list tagged with the \`offset_subset_v1\`
family.
