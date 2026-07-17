# Nested LOSO grid search over M2 specs

Loops over a named list of M2 spec objects and runs
[`nested_loso_cv()`](https://lennon-li.github.io/PAGe/reference/nested_loso_cv.md)
for each. Returns aggregated scores with spec identifiers for
comparison.

## Usage

``` r
nested_loso_grid_search(allD, params, specs, checkpoint_file = NULL, ...)
```

## Arguments

- allD:

  Full multi-season data frame.

- params:

  M0 detection parameters.

- specs:

  Named list of M2 spec objects (from
  [`stage2_make_spec()`](https://lennon-li.github.io/PAGe/reference/stage2_make_spec.md)).

- checkpoint_file:

  Optional path to an RDS file for incremental saves. After each spec
  completes, results are written to this file. If the file already
  exists at startup, completed specs are skipped (resume support).

- ...:

  Additional arguments passed to
  [`nested_loso_cv()`](https://lennon-li.github.io/PAGe/reference/nested_loso_cv.md)
  (e.g. `test_seasons`, `eval_window`, `k_ref`, `verbose`).

## Value

A named list:

- scores:

  Tibble with columns spec_id, season, n, mean_nll, brier, rmse_p.

- summary:

  Tibble with one row per spec: spec_id, mean_nll, brier, rmse_p
  (averaged across seasons).

- best_spec_id:

  The spec_id with lowest mean_nll.

- best_spec:

  The corresponding spec object.

- cv_results:

  Named list of full
  [`nested_loso_cv()`](https://lennon-li.github.io/PAGe/reference/nested_loso_cv.md)
  outputs per spec.
