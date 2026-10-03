\name{page_aggregate_strata_draws}
\alias{page_aggregate_strata_draws}
\title{Aggregate joint posterior or simulation draws across strata}
\usage{
page_aggregate_strata_draws(
  draws,
  method = c("sum", "weighted_mean", "linear"),
  weights = NULL,
  level = 0.95,
  bounds = NULL,
  keep_draws = FALSE
)
}
\arguments{
\item{draws}{Numeric matrix/data frame with rows as draws and columns as strata.}
\item{method}{Aggregation operator: sum, weighted mean, or arbitrary linear combination.}
\item{weights}{Weights for weighted mean or linear aggregation.}
\item{level}{Central interval level.}
\item{bounds}{Optional output bounds.}
\item{keep_draws}{Logical; retain the aggregate draw vector in the returned object.}
}
\value{An object of class \code{page_strata_aggregate_draws} containing the aggregate mean, median, standard deviation, interval and optionally the aggregate draws.}
\description{
Applies the aggregation operator inside each joint posterior or simulation draw, then summarizes the aggregate draw distribution. This is the preferred uncertainty propagation path when joint draws are available because it preserves arbitrary dependence, asymmetry and non-Gaussian uncertainty without an analytic covariance approximation.
}
\examples{
set.seed(1)
draws <- cbind(
  A = rnorm(1000, 0.05, 0.005),
  B = rnorm(1000, 0.02, 0.003)
)
aggregate_strata_draws(draws, method = "sum", bounds = c(0, 1))
}
