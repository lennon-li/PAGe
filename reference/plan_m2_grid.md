# Plan a bounded M2 tuning grid

Creates a compact, explainable M2 grid. Without compatible prior tuning
results, the plan contains the deployed v16 specification and one-factor
neighbors. With prior results, it retains v16, greedily retains diverse
high-performing finalists, adds one-factor neighbors around the prior
winner, and expands grid boundaries reached by that winner.

## Usage

``` r
plan_m2_grid(previous_results = NULL, max_finalists = 6L, max_specs = 64L)
```

## Arguments

- previous_results:

  Optional prior
  [`build_m2()`](https://lennon-li.github.io/PAGe/reference/build_m2.md)
  result containing `summary` and `grid`; `scores` may supply a missing
  summary metric. Ranking uses `bernoulli_nll`, then `mean_nll`.

- max_finalists:

  Maximum number of diverse prior finalists to retain.

- max_specs:

  Hard cap on returned specifications.

## Value

A data frame with M2 parameters, stable `spec_id`, and
semicolon-separated `provenance` for every row.
