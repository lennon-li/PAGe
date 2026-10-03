# Render the PAGe walk-forward report

Generates the current self-contained A/B/A+B walk-forward HTML report.

## Usage

``` r
page_walkforward_report(data = NULL, ...)
```

## Arguments

- data:

  A canonical typed A/B panel, an OLIS \`.RData\` snapshot, or a local
  official ORVT CSV accepted by \[page_v3_forecast()\]. When \`NULL\`
  (the default), the current season is fetched from the live PHO ORVT
  feed via \[getCurrentD()\].

- ...:

  Arguments passed to
  [`page_v3_walkforward_report()`](https://lennon-li.github.io/PAGe/reference/page_v3_walkforward_report.md).

## Value

Invisibly, the normalized path to the generated HTML report.
