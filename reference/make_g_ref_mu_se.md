# Build reference mean/SE function from GAM (link scale)

Build reference mean/SE function from GAM (link scale)

## Usage

``` r
make_g_ref_mu_se(gam_obj)
```

## Arguments

- gam_obj:

  a fitted mgcv::gam (or gamm4::\$gam)

## Value

a function f(u) that returns list(mu = ..., se = ...) on link scale
