# Create season timing labels from user input

Create season timing labels from user input

## Usage

``` r
label_season_timing(
  season = NULL,
  ignition = NULL,
  peak = NULL,
  n_weeks = NULL,
  calendar = NULL,
  peak_observed = NULL
)
```

## Arguments

- season:

  Optional season identifier.

- ignition:

  Optional ignition label.

- peak:

  Optional peak label.

- n_weeks:

  Number of weeks in the season.

- calendar:

  Optional timing calendar. Its week count must agree with `n_weeks`.

- peak_observed:

  Optional observed peak week selected from `peak`.

## Value

A validated `page_timing_labels_v2` object.
