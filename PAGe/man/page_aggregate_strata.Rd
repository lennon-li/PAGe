\name{page_aggregate_strata}
\alias{page_aggregate_strata}
\title{Aggregate stratified forecasts with explicit dependence}
\usage{
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
}
\arguments{
\item{estimate}{Named numeric vector of stratum estimates.}
\item{se}{Optional response-scale standard errors for each stratum.}
\item{lower, upper}{Optional component confidence bounds. Asymmetric component intervals remain asymmetric after aggregation.}
\item{method}{Aggregation operator: \code{"sum"}, \code{"weighted_mean"}, or \code{"linear"}.}
\item{weights}{Weights for weighted-mean or linear aggregation. Weighted-mean weights are normalized to sum to one.}
\item{dependence}{Dependence model: independent, shared-denominator multinomial, explicit correlation, or explicit covariance.}
\item{correlation}{Correlation matrix for \code{dependence = "correlation"}.}
\item{covariance}{Covariance matrix for \code{dependence = "covariance"}.}
\item{level}{Central confidence level.}
\item{bounds}{Optional output bounds, for example \code{c(0, 1)} for probabilities.}
}
\value{An object of class \code{page_strata_aggregate} containing the aggregate estimate, interval, operator weights, and dependence structure.}
\description{
Combines related stratum-level forecasts while respecting their dependence structure. The same interface supports sums such as influenza A+B, denominator-weighted age or geographic aggregation, arbitrary linear contrasts, independent strata, shared-denominator multinomial categories, and user-supplied correlation/covariance matrices.
}
\examples{
# Mutually exclusive A/B categories from one shared denominator
aggregate_strata(
  estimate = c(A = 0.05, B = 0.02),
  se = c(A = 0.004, B = 0.002),
  method = "sum",
  dependence = "shared_denominator",
  bounds = c(0, 1)
)

# Independent age strata, weighted by testing volume
aggregate_strata(
  estimate = c(`0-17` = 0.10, `18-64` = 0.20, `65+` = 0.30),
  se = c(`0-17` = 0.01, `18-64` = 0.02, `65+` = 0.03),
  method = "weighted_mean",
  weights = c(`0-17` = 100, `18-64` = 300, `65+` = 100),
  dependence = "independent",
  bounds = c(0, 1)
)
}
