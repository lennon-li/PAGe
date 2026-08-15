# Expand a tuning grid at every unresolved winner boundary

This is the user-facing companion to \`inspect_tuning_boundaries()\`. It
appends one valid adjacent value per unresolved axis and preserves every
existing row and specification identity. Pass the returned grid to the
same \`tune\_\*()\` function with its existing \`checkpoint_dir\`; M1
and M2 checkpoints reuse completed specifications, while M0 reuses
cached grid scores when the prior tuning object is supplied as
\`previous_results\`.

## Usage

``` r
expand_tuning_grid(
  x,
  stage = c("M0", "M1", "M2"),
  grid = NULL,
  steps = NULL,
  max_specs = NULL
)
```

## Arguments

- x:

  A tuning result or a grid data frame.

- stage:

  One of \`"M0"\`, \`"M1"\`, or \`"M2"\`.

- grid:

  Optional grid override.

- steps:

  Optional named numeric vector overriding adjacent spacing.

- max_specs:

  Optional cap on returned rows.

## Value

The original grid with new boundary rows appended. New rows carry
\`provenance = "boundary:\<parameter\>"\` when that column is available.
