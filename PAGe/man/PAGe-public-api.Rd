\name{PAGe-public-api}
\alias{page_train}
\alias{page_forecast}
\alias{page_models}
\alias{page_walkforward_report}
\alias{page_validate_kit}
\alias{aggregate_strata}
\alias{aggregate_strata_draws}
\alias{shared_denominator_correlation}
\alias{m0_fit}
\alias{m0_detect}
\alias{m1_fit}
\alias{m1_predict}
\alias{m1_peak_posterior}
\alias{m1_passage_posterior}
\alias{m2_fit}
\alias{m2_predict}
\alias{evaluate_forecasts}
\alias{replay_holdout}
\alias{verify_promotion}
\title{Stable PAGe public API}
\usage{
page_train(...)
page_forecast(...)
page_models()
page_walkforward_report(...)
page_validate_kit(...)
aggregate_strata(...)
aggregate_strata_draws(...)
shared_denominator_correlation(...)
m0_fit(...)
m0_detect(...)
m1_fit(...)
m1_predict(...)
m1_peak_posterior(...)
m1_passage_posterior(...)
m2_fit(...)
m2_predict(...)
evaluate_forecasts(...)
replay_holdout(...)
verify_promotion(...)
}
\arguments{
\item{...}{Arguments passed to the corresponding governed PAGe implementation. See the function-specific examples and the public API walkthrough for the supported workflow.}
}
\description{
These functions define the stable user-facing PAGe interface. Development-generation labels such as v1, v2, and v3 are intentionally absent from public function names. Historical versioned implementation functions remain internal so frozen releases and repository-owned reproduction workflows can retain exact provenance.
}
\details{
\code{page_train()}, \code{page_forecast()}, \code{page_walkforward_report()}, and the kit helpers are high-level PAGe workflows. \code{m0_*}, \code{m1_*}, and \code{m2_*} functions provide the advanced scientific component interface. \code{aggregate_strata()} and \code{aggregate_strata_draws()} support general stratified aggregation, including pathogen types, age groups, regions, sites, independent strata, explicit correlation/covariance structures, and joint simulation draws.

The complete supported namespace is documented in \code{docs/public-api.qmd} in the source repository.
}
