# Build reference link-scale function from a fitted GAM

Build reference link-scale function from a fitted GAM

## Usage

``` r
make_g_ref_fun(gam_obj, week_grid = 1:52)
```

## Arguments

- gam_obj:

  a fitted mgcv::gam (or gamm4::\$gam) with predictor \`newWeek\`

- week_grid:

  numeric vector of weeks to interpolate over (default 1:52)

## Value

A function that returns logit probability for arbitrary values of u.
