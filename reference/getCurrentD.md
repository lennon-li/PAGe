# Fetch and tidy current-season PHO respiratory surveillance data

Reads a Public Health Ontario ORVT lab-testing CSV from a URL or local
path, maps seasons from dated MMWR weeks rather than the PHO label,
aggregates the selected virus across public health units, and returns
data ready for PAGe. With no codedata, the previous/current and
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

  URL or local file path to an ORVT CSV, or codeNULL for default feed
  resolution.

- base_url:

  Base ORVT URL for default feed resolution. The codePAGe.orvt_base_url
  option overrides the package default.

- file_name:

  Optional ORVT filename replacing the two default candidates;
  codePAGe.orvt_file_name is also supported.

- cache_dir:

  Optional directory for timestamped downloaded raw CSV files.

- startWeek:

  Integer MMWR week used as the PAGe season origin (default 27).

- lastWeek:

  Integer or codeNA; drop rows with MMWR week greater than it.

- virus:

  Character string matching the PHO codeVirus column.

- season:

  Character season in code"YYYY-YY"; defaults to the season containing
  codeSys.Date() under the PAGe origin.

- include_predecessor:

  Logical; also return the derived predecessor season. Defaults to
  codeTRUE for backward compatibility.

- source_calendar:

  Optional explicit calendar for undated sources. It must be a data
  frame, Date vector, or function mapping source season/week rows to
  week-start dates (or MMWR years); labels alone are never used to guess
  dates.

## Value

A data frame with codeseason, codeweek, codeN, codey, codeneg, codep,
codeweekS, codeweekF, codecYear, codenewWeek, and codedate, plus PHO
audit columns. The PHU-only totals and the exact-Ontario-row provenance
are retained in codephu_N, codephu_y, codesource_has_ontario,
codesource_ontario_consistent, and codeprovincial_value_source.
Attributes record codesource_url_or_path, coderetrieved_utc, codesha256,
codepho_layout, coden_weeks, and codelast_week_end_date.
