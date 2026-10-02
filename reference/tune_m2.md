# Tune M2 with an explicit governed season selection

Runs the existing M2 LOSO implementation using only the selected
training seasons and records the selection and training-data identity on
the result.

## Usage

``` r
tune_m2(
  data,
  selection,
  m0,
  m1,
  grid,
  family = c("offset_subset_v1", "legacy"),
  allow_legacy = FALSE,
  ...
)
```

## Arguments

- data:

  Canonical surveillance data frame.

- selection:

  A `page_season_selection`.

- m0:

  A frozen `page_m0_fit`.

- m1:

  A frozen `page_m1_fit`.

- grid:

  M2 candidate grid.

- family:

  Model family. The default `"offset_subset_v1"` is the governed
  short-horizon offset correction pathway. `"legacy"` is
  research/compatibility-only.

- allow_legacy:

  Logical; explicitly allow the legacy research path.

- ...:

  Additional arguments passed to
  [`build_m2()`](https://lennon-li.github.io/PAGe/reference/build_m2.md).

## Value

A governed `page_m2_tuning` result.
