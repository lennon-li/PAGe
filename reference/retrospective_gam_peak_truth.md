# Derive retrospective continuous peak truth from a completed season using GAM

This procedure is for retrospective truth construction only. It must
never be used with partial held-out-season data at runtime.

## Usage

``` r
retrospective_gam_peak_truth(data, season = NULL, k = 8L, grid_step = 0.01)
```

## Arguments

- data:

  One completed season of surveillance data accepted by
  \`prepare_surveillance_data()\`.

- season:

  Optional season identifier.

- k:

  Basis dimension for the cubic regression spline.

- grid_step:

  Decimal-week resolution used to locate the fitted maximum.

## Value

A list containing the fitted model, continuous peak week, fitted peak
positivity, grid predictions, and provenance.
