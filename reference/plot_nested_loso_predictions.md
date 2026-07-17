# Plot nested LOSO predictions by season

Produces a faceted ggplot of observed vs predicted positivity for each
held-out season from nested LOSO results. Similar to
[`plot_stage2_joint_fit_by_season()`](https://lennon-li.github.io/PAGe/reference/plot_stage2_joint_fit_by_season.md)
but uses out-of-sample predictions from the CV object rather than
in-sample fits.

## Usage

``` r
plot_nested_loso_predictions(
  cv_result,
  dat_raw = NULL,
  y_max = 0.5,
  show_ci = TRUE,
  title = "Nested LOSO: predicted vs observed by season"
)
```

## Arguments

- cv_result:

  Output of
  [`nested_loso_cv()`](https://lennon-li.github.io/PAGe/reference/nested_loso_cv.md)
  or one element of `nested_loso_grid_search()$cv_results`.

- dat_raw:

  Optional aligned data for true ignition lines.

- y_max:

  Numeric upper y-axis limit.

- show_ci:

  Logical; draw approximate prediction intervals.

- title:

  Plot title.

## Value

A ggplot object.
