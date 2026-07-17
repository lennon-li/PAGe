# Terms to exclude for new-season prediction

When forecasting a brand-new season, season-dependent terms cannot be
used. This returns the mgcv smooth labels to exclude in predict(...,
exclude = ...).

## Usage

``` r
stage2_exclude_newseason(spec)
```

## Arguments

- spec:

  A spec list from stage2_make_spec().

## Value

Character vector of smooth labels to exclude.
