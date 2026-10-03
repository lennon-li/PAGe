# Render a PAGe Quarto walk-forward report

Builds a cumulative Quarto (\`.qmd\`) walk-forward report for one season
and, by default, renders it to a self-contained HTML document. The
report covers Week 8 through the latest observed week with one as-of tab
per origin week, and is sourced from the latest \`hist\*.RData\`
snapshot, a supplied OLIS/ORVT input, or the live ORVT feed.

## Usage

``` r
page_walkforward_qmd(
  data = NULL,
  season = NULL,
  output_dir = "reports",
  file_name = NULL,
  render = TRUE,
  ...
)

page_render_report(...)
```

## Arguments

- data:

  Surveillance input. One of: \`NULL\` (default) to use the latest
  \`hist\*.RData\` snapshot found in the default IRVRI \`OP\` directory,
  falling back to the live PHO ORVT feed; a directory containing
  \`hist\*.RData\` snapshots; a path to an OLIS \`.RData\`/\`.rda\`
  snapshot or ORVT \`.csv\`; or a canonical typed A/B panel accepted by
  \[page_v3_forecast()\].

- season:

  Optional season label (for example \`"2026-27"\`). When \`NULL\` and
  an OLIS snapshot is supplied, the latest season present is used.

- output_dir:

  Directory that receives the \`.qmd\`, any plot assets, and the
  rendered \`.html\`.

- file_name:

  Optional \`.qmd\` file name. Defaults to
  \`page_walkforward\_\<season\>\_week\<origin\>.qmd\`.

- render:

  When \`TRUE\` (default), render the \`.qmd\` to self-contained HTML
  using the Quarto CLI.

- ...:

  Reserved for future use.

## Value

Invisibly, a named list with \`qmd_path\`, \`html_path\` (or
\`NA_character\_\` when \`render = FALSE\`), the resolved \`data\`
panel, and the \`forecasts\` data frame.
