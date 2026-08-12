# Plan a bounded M2 tuning grid

Creates a compact, explainable M2 grid. Without compatible prior tuning
results, the plan contains the current v16-corrected incumbent and
one-factor neighbors. With prior results, it retains v16, greedily
retains diverse high-performing finalists, adds one-factor neighbors
around the prior winner, and expands grid boundaries reached by that
winner using the spacing adjacent to each reached boundary.

## Usage

``` r
plan_m2_grid(previous_results = NULL, max_finalists = 6L, max_specs = 64L)
```

## Arguments

- previous_results:

  Optional prior
  [`build_m2()`](https://lennon-li.github.io/PAGe/reference/build_m2.md)
  result containing `summary` and `grid`. Grid specification IDs, when
  supplied, must match their canonical parameter identities. Duplicate
  finite summary metrics are averaged by specification; fold-level
  `scores` fill missing or non-finite summary metrics. Ranking uses
  `bernoulli_nll`, then `mean_nll`.

- max_finalists:

  Maximum number of diverse prior finalists to retain.

- max_specs:

  Hard cap on returned specifications.

## Value

A data frame with M2 parameters, stable `spec_id`, and
semicolon-separated `provenance` for every row.

## Details

Boundary expansion proposes only new configurations that pass the M2
grid validity contract. A meaningful null boundary, such as an optional
smooth set to zero, need not be expanded past its valid domain. The EMA
smooth specifically supports `k_e = 0` (drop) or `k_e >= 2`; `k_e = 1`
is invalid. If `max_specs` truncates a search with a remaining boundary,
report that boundary as unresolved rather than as a bracketed optimum.
Grid expansion is a pre-holdout development activity.
