# Fit an M0 ignition configuration (draft artifact)

Fits the existing fixed M0 implementation using only the selected
training seasons and records the fitted payload and its provenance.

## Usage

``` r
fit_m0(data, selection, config, ...)
```

## Arguments

- data:

  Canonical surveillance data frame.

- selection:

  A `page_season_selection` from
  [`validate_season_selection()`](https://lennon-li.github.io/PAGe/reference/validate_season_selection.md).

- config:

  Named list of M0 detection parameters.

- ...:

  Reserved for future use.

## Value

A `page_m0_fit` list in `draft` state.
