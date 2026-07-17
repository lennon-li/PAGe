# Plot a PAGe 2-week-ahead forecast

Draws the current-season positivity forecast produced by the M0/M1/M2
pipeline. Optionally overlays historical season trajectories as a grey
background for context.

## Usage

``` r
plot_forecast(res, history = NULL)
```

## Arguments

- res:

  List returned by the prospective pipeline (e.g.
  [`run_prospective_pipeline()`](https://lennon-li.github.io/PAGe/reference/run_prospective_pipeline.md)).
  Must contain `$pred_df` (with columns `newWeek`, `p_hat`, `p_lo`,
  `p_hi`, and `kind`) and `$last_obs`.

- history:

  Optional data frame of historical seasons with columns `season`,
  `newWeek` or `weekF`, `y`, and either `N` or `neg`. When supplied,
  season trajectories are plotted as translucent grey lines.

## Value

A `ggplot` object.
