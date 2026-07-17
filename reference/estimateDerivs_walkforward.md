# Compute derivatives for a single season in a causal (walk-forward) manner

For each week `w` in `season_df`, fits `estimateDerivs` on the subset of
rows with `weekF <= w` and records the derivative values for row `w`
only. This prevents future weeks from influencing the GAM smoother at
earlier time points — a requirement for honest LOSO evaluation.

## Usage

``` r
estimateDerivs_walkforward(season_df, k = 10L, min_rows = 4L)
```

## Arguments

- season_df:

  Data frame for a single season with columns `weekF`, `y`, `N` (or
  `neg`) as expected by
  [`estimateDerivs()`](https://lennon-li.github.io/PAGe/reference/estimateDerivs.md).

- k:

  Integer; basis dimension forwarded to
  [`estimateDerivs()`](https://lennon-li.github.io/PAGe/reference/estimateDerivs.md)
  (default `10L`).

- min_rows:

  Integer; minimum rows required before attempting a fit (default `4L`).
  Rows with too few observations receive `NA` for all derivative
  columns.

## Value

A data frame with the same rows as `season_df` augmented with columns
`fit`, `fit_low`, `fit_high`, `d1`, `d1_low`, `d1_high`, `d2`, `d2_low`,
`d2_high`. These values at row `i` are computed using only `weekF[1:i]`.

## Details

Results are memoised by `walk_end` inside each call: each unique
`walk_end` value triggers exactly one `estimateDerivs` fit.
