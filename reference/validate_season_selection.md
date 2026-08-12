# Validate and normalize a season selection

Checks that all requested season identifiers exist in the canonical
data, are scalar character values without duplicates, and that the
training, exclusion, holdout, and application sets are mutually
disjoint. Returns a normalized `page_season_selection` object with
deterministic (sorted) ordering.

## Usage

``` r
validate_season_selection(
  data,
  training_seasons,
  exclude_seasons = character(0),
  holdout_seasons = character(0),
  application_seasons = character(0)
)
```

## Arguments

- data:

  A canonical surveillance data frame (must contain a `season` column).

- training_seasons:

  Character vector of seasons used for training. Must be non-empty.

- exclude_seasons:

  Character vector of seasons permanently excluded.

- holdout_seasons:

  Character vector of holdout evaluation seasons.

- application_seasons:

  Character vector of prospective application seasons.

## Value

A `page_season_selection` list with sorted, validated season vectors and
the full set of data seasons.
