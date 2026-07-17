# Plot observed vs Stage-2 forecasts across pseudo-prospective snapshots

Visualizes the output of
[`stage2_predict_series()`](https://lennon-li.github.io/PAGe/reference/stage2_predict_series.md).
For each snapshot, plots:

- observed `p_obs` as points

- forecast mean curves for `h1` (blue) and `h2` (green)

- optional uncertainty ribbons (from `p_lo_h*`/`p_hi_h*`)

- truth stars at `asof_weekF+1` and `asof_weekF+2` using `p_true`

- vertical line at `asof_weekF` (red) and ignition week (black dashed)

- optional reference curve `p_ref` as a grey background line

## Usage

``` r
plot_stage2(
  ppp,
  ign_week,
  facet = TRUE,
  ncol = 4,
  show_ref = TRUE,
  show_pi = TRUE,
  interval = c("pi", "ci", "none"),
  h_plot = c("h1", "h2"),
  base_size = 10
)
```

## Arguments

- ppp:

  Output from
  [`stage2_predict_series()`](https://lennon-li.github.io/PAGe/reference/stage2_predict_series.md)
  (list of snapshot data.frames or a single data.frame).

- ign_week:

  Ignition week (integer). Can be a scalar applied to all snapshots, or
  a vector/list aligned to snapshots.

- facet:

  Logical. If TRUE (default) returns one faceted `ggplot`; if FALSE
  returns a list of plots.

- ncol:

  Integer number of facet columns when `facet=TRUE`.

- show_ref:

  Logical. If TRUE, draws `p_ref` in grey when available.

- show_pi:

  Logical. If TRUE, draws ribbons from `p_lo_h*`/`p_hi_h*`.

- interval:

  Interval display: prediction, confidence, or none.

- h_plot:

  Forecast horizons to display.

- base_size:

  Base font size passed to
  [`ggplot2::theme_minimal()`](https://ggplot2.tidyverse.org/reference/ggtheme.html).

## Value

A `ggplot` object if `facet=TRUE`; otherwise a named list of `ggplot`
objects.

## Details

The x-axis uses `date` if present, otherwise `weekF`.
