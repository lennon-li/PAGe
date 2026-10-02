# Produce a real-time forecast from a frozen kit and any supported source

Thin operational wrapper: resolve the source, confirm the kit is frozen,
run the frozen walk-forward, and return the pipeline result together
with the resolved provenance and a tidy latest-origin summary.
Pre-ignition seasons legitimately return zero forecast rows; that is a
valid result and not an error.

## Usage

``` r
page_forecast_now(
  kit,
  source = NULL,
  season = NULL,
  walk_start = 5L,
  manual_ign_week = NA_integer_,
  timing_mode = c("fractional", "legacy"),
  verbose = TRUE,
  ...
)
```

## Arguments

- kit:

  A frozen PAGe kit.

- source:

  Passed to
  [`page_load_surveillance()`](https://lennon-li.github.io/PAGe/reference/page_load_surveillance.md);
  `NULL` (default) reads the live PHO ORVT feed.

- season:

  Optional PAGe season label.

- walk_start:

  Minimum M1 evaluation week (default 5). The effective start is
  `max(walk_start, locked ignition week)`.

- manual_ign_week:

  Optional integer week overriding M0 detection.

- timing_mode:

  `"fractional"` (default) or `"legacy"`.

- verbose:

  Print stage progress.

- ...:

  Passed to
  [`page_load_surveillance()`](https://lennon-li.github.io/PAGe/reference/page_load_surveillance.md).

## Value

A list with `forecast` (latest-origin h1/h2 rows, possibly zero-row),
`ignition` (status scalars), `result` (the full
[`run_prospective_pipeline()`](https://lennon-li.github.io/PAGe/reference/run_prospective_pipeline.md)
object) and `source` (provenance).
