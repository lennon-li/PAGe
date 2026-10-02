# Assert a LOSO test season is absent from supplied ignition labels

Prevents retrospective ignition leakage by verifying the held-out test
season does not appear in a supplied manual-label vector. By default
this is a hard assertion (`action = "stop"`); use `action = "warn"` for
a soft notice.

## Usage

``` r
assert_loso_test_season_absent(
  test_season,
  labels,
  label_name = "labels",
  action = c("stop", "warn")
)
```

## Arguments

- test_season:

  Character scalar; the held-out LOSO test season.

- labels:

  Named integer vector of manual ignition labels, or `NULL`.

- label_name:

  Character; name shown in the message.

- action:

  `"stop"` (default) or `"warn"`.

## Value

Invisible `TRUE`, or raises an error/warning.
