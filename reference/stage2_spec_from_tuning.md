# Extract best Stage-2 spec from a tuning result

Convenience wrapper: given the list returned by
`tune_stage2_loso_spec_grid_parallel()`, finds the best row in
`tuned2$by_spec_grid` and calls
[`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md)
with the appropriate column mappings (`Kr` -\> `K`, `Kb` -\>
`pre_buffer`).

## Usage

``` r
stage2_spec_from_tuning(tuned2)
```

## Arguments

- tuned2:

  List with at least `$best` (1-row data frame with `spec_id`) and
  `$by_spec_grid` (full grid with hyperparameters).

## Value

A spec list as returned by
[`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md).
