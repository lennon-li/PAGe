# Fit an M2 forecast configuration (draft artifact)

Constructs a draft M2 stage artifact. Requires frozen M0 and M1 with
matching identities and selection.

## Usage

``` r
fit_m2(data, selection, m0, m1, config, ...)
```

## Arguments

- data:

  Canonical surveillance data frame.

- selection:

  A `page_season_selection`.

- m0:

  A frozen `page_m0_fit`.

- m1:

  A frozen `page_m1_fit`.

- config:

  Named list of M2 specification parameters.

- ...:

  Reserved.

## Value

A `page_m2_fit` list in `draft` state.
