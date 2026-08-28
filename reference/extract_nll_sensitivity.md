# Extract metric sensitivity across tuning-grid parameters

For every numeric grid axis, this function reports the mean and best
cross-validation metric at each tested value, the best specification,
and the adjacent improvement when moving upward through the tested
values. The default metric is Bernoulli NLL. A named list of tuning
results can be supplied to compare independent holdout cycles.

## Usage

``` r
extract_nll_sensitivity(x, metric = "bernoulli_nll", parameters = NULL)
```

## Arguments

- x:

  A tuning result, or a named list of tuning results.

- metric:

  Character scalar metric column. Defaults to `"bernoulli_nll"`; pass
  another metric for M0/M1 analyses.

- parameters:

  Optional numeric grid columns to inspect. By default all numeric
  columns with at least two finite values are included.

## Value

An object with `overall`, `by_season`, `gains`, and `matched_gains` data
frames. The matched table compares specifications that differ only in
the named parameter, which is the preferred estimate for a
parameter-specific gain cap. Positive `adjacent_gain` means the newer
value reduced the metric; `gain_per_unit` divides that change by the
parameter step. The object has class `page_nll_sensitivity`.
