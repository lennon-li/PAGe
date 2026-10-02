# Load current-season surveillance data from any supported source

Resolves one operational data source into the canonical PAGe
surveillance schema and records where it came from. The default is the
live PHO ORVT feed; an operator who has a downloaded ORVT CSV, the PAGe
historical CSV, or the daily age-stratified `.RData` extract can pass
that path instead without changing anything downstream.

## Usage

``` r
page_load_surveillance(
  source = NULL,
  season = NULL,
  start_week = 27L,
  pathogen = "fluA",
  complete_weeks_only = TRUE,
  cache_dir = NULL,
  include_predecessor = FALSE,
  ...
)
```

## Arguments

- source:

  `NULL` (default) to read the live PHO ORVT feed, or a path to an ORVT
  CSV, a PAGe historical CSV, or an `.RData`/`.rda` daily extract, or a
  data frame already in the canonical schema.

- season:

  Optional PAGe season label (for example `"2026-27"`). Defaults to the
  current season implied by the calendar.

- start_week:

  Integer MMWR week that starts a PAGe season (default 27).

- pathogen:

  Element name to read from a daily `.RData` extract (default `"fluA"`).
  Ignored for other sources.

- complete_weeks_only:

  Drop trailing partial weeks from a daily extract (default `TRUE`). A
  partial week is not comparable with a full-week training history.

- cache_dir:

  Optional directory for archiving a fetched ORVT download.

- include_predecessor:

  Passed to
  [`getCurrentD()`](https://lennon-li.github.io/PAGe/reference/getCurrentD.md)
  for ORVT sources.

- ...:

  Additional arguments passed to
  [`getCurrentD()`](https://lennon-li.github.io/PAGe/reference/getCurrentD.md).

## Value

A prepared surveillance data frame carrying a `page_source` attribute: a
list of `kind`, `path`, `sha256`, `retrieved_utc`, `season`, `n_weeks`,
`latest_week_end` and `notes`.
