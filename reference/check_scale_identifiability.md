# Check if scaling (b) is identifiable yet, with a more sensitive rule

Check if scaling (b) is identifiable yet, with a more sensitive rule

## Usage

``` r
check_scale_identifiability(
  currentD,
  g_ref_fun,
  hyper,
  min_week = 20,
  g_range_thresh = 0.25,
  p_range_thresh = 0.05
)
```

## Arguments

- currentD:

  data frame with newWeek, y, neg.

- g_ref_fun:

  reference spline on link scale.

- hyper:

  list from learn_alignment_hyperparams().

- min_week:

  do not allow scaling before this epi week in newWeek space.

- g_range_thresh:

  minimum range of g(u) (on link scale) to trust scaling.

- p_range_thresh:

  minimum range of crude positivity to trust scaling.

## Value

list with allow_scale_rec (TRUE/FALSE) and diagnostics.
