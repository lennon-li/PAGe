# Fetch and tidy current-season PHO respiratory surveillance data

Downloads (or reads a local copy of) the Public Health Ontario
lab-testing CSV, filters to one virus and the requested season plus its
predecessor, aggregates weekly totals across all PHUs, and returns a
tidy data frame ready for the M0/M1/M2 pipeline.

## Usage

``` r
getCurrentD(
  data =
    "https://ws1.publichealthontario.ca/appdata/powerbi/ORVT/ORVT_Lab_Testing_Data_2024-25_2025-26.csv",
  startWeek = 27L,
  lastWeek = NA,
  virus = "Influenza A",
  season = "2025-26"
)
```

## Arguments

- data:

  URL or local file path to the PHO lab-testing CSV. Defaults to the
  2024-25 / 2025-26 ORVT public feed.

- startWeek:

  Integer MMWR week used as the epidemic-year origin for computing
  `weekF` (default 27L, early July).

- lastWeek:

  Integer or `NA`. When non-`NA`, rows with MMWR `week > lastWeek` are
  dropped before returning.

- virus:

  Character string matching the `Virus` column of the CSV (default
  `"Influenza A"`).

- season:

  Character season identifier in `"YYYY-YY"` format (default
  `"2025-26"`).

## Value

A data frame with one row per MMWR week containing: `season`, `week`,
`N` (total tests), `y` (positives), `neg`, `p` (positivity), `weekS`,
`weekF`, `cYear`, `newWeek`, and `date`.
