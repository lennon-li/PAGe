# Expand a tuning grid at every unresolved winner boundary

This is the user-facing companion to \`inspect_tuning_boundaries()\`. It
appends one valid smaller adjacent value per unresolved axis and
preserves every existing row and specification identity. Pass the
returned grid to the same \`tune\_\*()\` function with its existing
\`checkpoint_dir\`; M1 and M2 checkpoints reuse completed
specifications, while M0 reuses cached grid scores when the prior tuning
object is supplied as \`previous_results\`.

## Usage

``` r
expand_tuning_grid(
  x,
  stage = c("M0", "M1", "M2"),
  grid = NULL,
  steps = NULL,
  max_specs = NULL,
  n_weeks = 52L,
  data = NULL,
  m1_k_ref_bounds = .m1_k_ref_bounds()
)
```

## Arguments

- x:

  A stage tuning result with a selected configuration and complete
  tuning grid. A raw grid alone is not sufficient for M0 or M1
  expansion.

- stage:

  One of \`"M0"\`, \`"M1"\`, or \`"M2"\`.

- grid:

  Optional grid override.

- steps:

  Optional named numeric vector overriding adjacent spacing.

- max_specs:

  Optional cap on returned rows.

- n_weeks:

  Integer reference-domain size used to guard M1 basis values.

- data:

  Optional stage data used to guard M0 rolling/window support.

- m1_k_ref_bounds:

  Named integer vector with \`lower\` and \`upper\` hard bounds for M1
  \`k_ref\` expansion. Defaults to 10–50.

## Value

The original grid with new boundary rows appended. New rows carry
\`provenance = "boundary:\<parameter\>"\` when that column is available.
