# Fetch and tidy current-season PHO respiratory surveillance data

Reads a Public Health Ontario ORVT lab-testing CSV from a URL or local
path, maps seasons from dated MMWR weeks rather than the PHO label,
aggregates the selected virus across public health units, and returns
data ready for PAGe. With no `data`, the previous/current and
current/next feed names are tried in that order. PHO labels and source
dates are retained for audit.

## Usage

``` r
getCurrentD(
  data = NULL,
  base_url = NULL,
  file_name = NULL,
  cache_dir = NULL,
  startWeek = 27L,
  lastWeek = NA_integer_,
  virus = "Influenza A",
  season = NULL,
  include_predecessor = TRUE,
  source_calendar = NULL
)
```

## Arguments

- data:

  URL or local file path to an ORVT CSV, or `NULL` for default feed
  resolution.

- base_url:

  Base ORVT URL for default feed resolution. The `PAGe.orvt_base_url`
  option overrides the package default.

- file_name:

  Optional ORVT filename replacing the two default candidates;
  `PAGe.orvt_file_name` is also supported.

- cache_dir:

  Optional directory for timestamped downloaded raw CSV files.

- startWeek:

  Integer MMWR week used as the PAGe season origin (default 27).

- lastWeek:

  Integer or `NA`; drop rows with MMWR week greater than it.

- virus:

  Character string matching the PHO `Virus` column.

- season:

  Character season in `"YYYY-YY"`; defaults to the season containing
  [`Sys.Date()`](https://rdrr.io/r/base/Sys.time.html) under the PAGe
  origin.

- include_predecessor:

  Logical; also return the derived predecessor season. Defaults to
  `TRUE` for backward compatibility.

- source_calendar:

  Optional explicit calendar for undated sources. It must be a data
  frame, Date vector, or function mapping source season/week rows to
  week-start dates (or MMWR years); labels alone are never used to guess
  dates.

## Value

A data frame with `season`, `week`, `N`, `y`, `neg`, `p`, `weekS`,
`weekF`, `cYear`, `newWeek`, and `date`, plus PHO audit columns. The
PHU-only totals and the exact-Ontario-row provenance are retained in
`phu_N`, `phu_y`, `source_has_ontario`, `source_ontario_consistent`, and
`provincial_value_source`. Attributes record `source_url_or_path`,
`retrieved_utc`, `sha256`, `pho_layout`, `n_weeks`, and
`last_week_end_date`.
