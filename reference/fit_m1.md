# Fit an M1 alignment configuration (draft artifact)

Constructs a draft M1 stage artifact. Requires a frozen M0 with matching
training selection.

## Usage

``` r
fit_m1(data, selection, m0, config, ...)
```

## Arguments

- data:

  Canonical surveillance data frame.

- selection:

  A `page_season_selection`.

- m0:

  A frozen `page_m0_fit`.

- config:

  Named list of M1 alignment parameters.

- ...:

  Reserved.

## Value

A `page_m1_fit` list in `draft` state.
