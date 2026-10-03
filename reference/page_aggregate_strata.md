# Aggregate stratified forecasts with explicit dependence

Combines related stratum-level forecasts while respecting their
dependence structure. The same interface supports sums such as influenza
A+B, denominator-weighted age or geographic aggregation, arbitrary
linear contrasts, independent strata, shared-denominator multinomial
categories, and user-supplied correlation/covariance matrices.

## Usage

``` r
page_aggregate_strata(
  estimate,
  se = NULL,
  lower = NULL,
  upper = NULL,
  method = c("sum", "weighted_mean", "linear"),
  weights = NULL,
  dependence = c("independent", "shared_denominator", "correlation", "covariance"),
  correlation = NULL,
  covariance = NULL,
  level = 0.95,
  bounds = NULL
)
```

## Arguments

- estimate:

  Named numeric vector of stratum estimates.

- se:

  Optional response-scale standard errors for each stratum.

- lower, upper:

  Optional component confidence bounds. Asymmetric component intervals
  remain asymmetric after aggregation.

- method:

  Aggregation operator: `"sum"`, `"weighted_mean"`, or `"linear"`.

- weights:

  Weights for weighted-mean or linear aggregation. Weighted-mean weights
  are normalized to sum to one.

- dependence:

  Dependence model: independent, shared-denominator multinomial,
  explicit correlation, or explicit covariance.

- correlation:

  Correlation matrix for `dependence = "correlation"`.

- covariance:

  Covariance matrix for `dependence = "covariance"`.

- level:

  Central confidence level.

- bounds:

  Optional output bounds, for example `c(0, 1)` for probabilities.

## Value

An object of class `page_strata_aggregate` containing the aggregate
estimate, interval, operator weights, and dependence structure.

## Examples

``` r
# Mutually exclusive A/B categories from one shared denominator
aggregate_strata(
  estimate = c(A = 0.05, B = 0.02),
  se = c(A = 0.004, B = 0.002),
  method = "sum",
  dependence = "shared_denominator",
  bounds = c(0, 1)
)
#> PAGe stratified aggregate
#>   method:      sum
#>   dependence:  shared_denominator
#>   estimate:    0.07
#>   95.0% CI:    [0.0613504, 0.0786496]

# Independent age strata, weighted by testing volume
aggregate_strata(
  estimate = c(`0-17` = 0.10, `18-64` = 0.20, `65+` = 0.30),
  se = c(`0-17` = 0.01, `18-64` = 0.02, `65+` = 0.03),
  method = "weighted_mean",
  weights = c(`0-17` = 100, `18-64` = 300, `65+` = 100),
  dependence = "independent",
  bounds = c(0, 1)
)
#> PAGe stratified aggregate
#>   method:      weighted_mean
#>   dependence:  independent
#>   estimate:    0.2
#>   95.0% CI:    [0.173414, 0.226586]
```
