# Plot ignition detection results (faceted)

Convenience plotter for the output of \`detectIgnitionBySeason()\` /
\`tuneIgnitionGrid()\`. Draws week-by-week signals and estimated
ignition week by season.

## Usage

``` r
plot_det_facet(det_out, smooth_col = NULL)
```

## Arguments

- det_out:

  Output from \`detectIgnitionBySeason()\` (or a compatible object that
  includes the per-week signals and season identifiers).

- smooth_col:

  Optional name of a column in \`det_out\$signals\` (or equivalent) used
  for an additional smooth/line layer. Default \`NULL\`.

## Value

A ggplot object.
