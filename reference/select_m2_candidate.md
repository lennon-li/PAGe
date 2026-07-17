# Select an M2 candidate from full nested-LOSO results

Select an M2 candidate from full nested-LOSO results

## Usage

``` r
select_m2_candidate(results, method = c("min_nll", "one_se", "pareto"))
```

## Arguments

- results:

  A build_m2()-like result.

- method:

  Selection rule: minimum NLL (default), one-standard-error, or Pareto
  selection on NLL, worst-horizon MAE, and worst-phase MAE.

## Value

Selection metadata including selected_spec_id and selected_spec. Pareto
ties are resolved by NLL, complexity, then lexicographic specification
ID.
