# Aggregate joint posterior or simulation draws across strata

Applies the aggregation operator inside each joint posterior or
simulation draw, then summarizes the aggregate draw distribution. This
is the preferred uncertainty propagation path when joint draws are
available because it preserves arbitrary dependence, asymmetry and
non-Gaussian uncertainty without an analytic covariance approximation.

## Usage

``` r
page_aggregate_strata_draws(
  draws,
  method = c("sum", "weighted_mean", "linear"),
  weights = NULL,
  level = 0.95,
  bounds = NULL,
  keep_draws = FALSE
)
```

## Arguments

- draws:

  Numeric matrix/data frame with rows as draws and columns as strata.

- method:

  Aggregation operator: sum, weighted mean, or arbitrary linear
  combination.

- weights:

  Weights for weighted mean or linear aggregation.

- level:

  Central interval level.

- bounds:

  Optional output bounds.

- keep_draws:

  Logical; retain the aggregate draw vector in the returned object.

## Value

An object of class `page_strata_aggregate_draws` containing the
aggregate mean, median, standard deviation, interval and optionally the
aggregate draws.

## Examples

``` r
set.seed(1)
draws <- cbind(
  A = rnorm(1000, 0.05, 0.005),
  B = rnorm(1000, 0.02, 0.003)
)
page_aggregate_strata_draws(draws, method = "sum", bounds = c(0, 1))
#> Error in page_aggregate_strata_draws(draws, method = "sum", bounds = c(0,     1)): could not find function "page_aggregate_strata_draws"
```
