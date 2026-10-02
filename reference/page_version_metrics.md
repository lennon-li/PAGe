# Verified PAGe version-comparison metrics

Returns the compact evidence table used by the PAGe version-comparison
vignette. Rows are deliberately scoped to matched or chronological
ledgers that support the stated comparison. Missing values mean that a
version was not independently scored on that exact ledger; PAGe does not
fill such cells by assuming cross-version equivalence.

## Usage

``` r
page_version_metrics()
```

## Value

A data frame containing comparison scope, component, horizon, metric,
v1/legacy, v2, v3 values, relative gains, evidence path, and caveat.
