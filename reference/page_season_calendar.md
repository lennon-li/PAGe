# Derive the PAGe July-start season calendar from surveillance dates

The modelling season starts at MMWR week \`start_week\` (27 by default).
The input CSV season label is never consulted when dates or explicit
MMWR years are supplied. \`weekS\` is retained only as the historical
PHO-style interpretation coordinate; \`weekF\` is the chronological
July-season index.

## Usage

``` r
page_season_calendar(
  dates = NULL,
  mmwr_year = NULL,
  week = NULL,
  start_week = 27L
)
```

## Arguments

- dates:

  Optional vector of week-start dates. Supply this or both \`mmwr_year\`
  and \`week\`.

- mmwr_year:

  Optional MMWR calendar year for each \`week\`.

- week:

  Optional MMWR week number for each observation.

- start_week:

  MMWR week at which the PAGe season starts (default 27).

## Value

A data frame with \`season\`, \`start_year\`, \`week\`, \`nW_true\`,
\`weekF\`, and \`weekS\`.
