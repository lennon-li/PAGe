# Render the PAGe v3 walk-forward HTML report

Generates the interactive A/B/A+B walk-forward report used by the
governed 2026-27 Week-12 shadow workflow. The report includes current
hero metrics, historical origin diagnostics, A/B forecast uncertainty,
Flu A peak CDF/hazard views, and the peak-normalized full-season M1
shape view. Report-support assets are shipped separately from the frozen
forecasting release and do not alter model identity.

## Usage

``` r
page_v3_walkforward_report(
  data = NULL,
  season = NULL,
  origins = NULL,
  output_file = "PAGe_walkforward_report.html",
  self_contained = TRUE,
  strict = TRUE
)
```

## Arguments

- data:

  A canonical typed A/B panel, an OLIS `.RData` snapshot, or a local
  official ORVT CSV accepted by
  [`page_v3_forecast()`](https://lennon-li.github.io/PAGe/reference/page_v3_forecast.md).
  When `NULL` (the default), the current season is fetched from the live
  PHO ORVT feed via
  [`getCurrentD()`](https://lennon-li.github.io/PAGe/reference/getCurrentD.md).

- season:

  Optional season label. Required where
  [`page_v3_forecast()`](https://lennon-li.github.io/PAGe/reference/page_v3_forecast.md)
  requires it, for example for an ORVT CSV path.

- origins:

  Integer origin weeks to expose as report tabs. Defaults to Weeks 8
  through the latest available origin.

- output_file:

  Destination HTML file. Parent directories are created.

- self_contained:

  Logical. When `TRUE`, embeds Plotly JavaScript so the report has no
  network dependency. When `FALSE`, references the Plotly CDN.

- strict:

  Passed to
  [`page_v3_forecast()`](https://lennon-li.github.io/PAGe/reference/page_v3_forecast.md)
  and the typed-panel validator.

## Value

Invisibly, the normalized path to the generated HTML report.
