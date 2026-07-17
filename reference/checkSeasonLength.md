# Compute in-season length for each season

For each season in \`dat\`, finds the first week at which positivity
(\`y / N\`) crosses \`thresh\`, the first week after that where it drops
back below the threshold, and the gap between them. Used to validate the
threshold-based season definition against observed data.

## Usage

``` r
checkSeasonLength(dat, thresh = 0.05, inclusive = F)
```

## Arguments

- dat:

  Data frame with one row per season-week. Must include columns
  \`season\`, \`weekF\`, \`y\`, and \`N\`.

- thresh:

  Positivity threshold on the probability scale (default \`0.05\`).

- inclusive:

  Logical; if \`TRUE\`, include both endpoints in the length count
  (default \`FALSE\`).

## Value

A tibble with one row per season and columns \`season\`, \`start_week\`,
\`end_week\`, and \`season_length_weeks\`.
