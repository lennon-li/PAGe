# Build a soft positivity cap function from a fitted Stage-2 GAM

Extracts the training-data positivity distribution from a fitted mgcv
GAM and returns a tanh-based soft ceiling function consistent with the
deployment cap applied in
[`run_m2_forecast()`](https://lennon-li.github.io/PAGe/reference/run_m2_forecast.md).

## Usage

``` r
make_soft_cap_fn(fit_obj)
```

## Arguments

- fit_obj:

  A fitted mgcv GAM with a binomial response matrix as `model[[1]]`.

## Value

A function `f(p)` mapping predicted probabilities through the soft cap.
