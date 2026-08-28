# Plot metric sensitivity across tuning-grid parameters

Plot metric sensitivity across tuning-grid parameters

## Usage

``` r
plot_nll_sensitivity(
  x,
  metric = "bernoulli_nll",
  parameters = NULL,
  run = NULL,
  season = NULL,
  statistic = c("best_metric", "mean_metric", "adjacent_gain"),
  facet_scales = "free_x"
)
```

## Arguments

- x:

  A tuning result, a named tuning-result list, or a
  `page_nll_sensitivity` object from
  [`extract_nll_sensitivity()`](https://lennon-li.github.io/PAGe/reference/extract_nll_sensitivity.md).

- metric:

  Metric column when `x` is a raw tuning result.

- parameters:

  Optional parameters to plot.

- run:

  Optional run names to retain.

- season:

  Optional season. When supplied, plots season-specific values from
  `by_season`; otherwise plots overall values.

- statistic:

  Either `"best_metric"` (default), `"mean_metric"`, or
  `"adjacent_gain"`.

- facet_scales:

  Passed to
  [`ggplot2::facet_wrap()`](https://ggplot2.tidyverse.org/reference/facet_wrap.html).

## Value

A `ggplot` object.
