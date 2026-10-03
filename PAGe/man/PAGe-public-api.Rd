\name{PAGe-public-api}
\alias{PAGe-public-api}
\title{Stable PAGe public API}
\description{
These functions define the stable user-facing PAGe interface. Development-generation labels such as v1, v2, and v3 are intentionally absent from public function names. Historical versioned implementation functions remain internal so frozen releases and repository-owned reproduction workflows can retain exact provenance.
}
\details{
\code{page_train()}, \code{page_forecast()}, \code{page_walkforward_report()}, \code{page_walkforward_qmd()}, and the kit helpers are high-level PAGe workflows. \code{m0_*}, \code{m1_*}, and \code{m2_*} functions provide the advanced scientific component interface. \code{aggregate_strata()} and \code{aggregate_strata_draws()} support general stratified aggregation, including pathogen types, age groups, regions, sites, independent strata, explicit correlation/covariance structures, and joint simulation draws. \code{page_render_report()} is an alias for \code{page_walkforward_qmd()}, which emits a cumulative Quarto \code{.qmd} with per-origin as-of tabsets and optionally renders it to HTML.

The complete supported namespace is documented in \code{docs/public-api.qmd} in the source repository.
}
\seealso{
\code{\link{page_train}}, \code{\link{page_forecast}}, \code{\link{page_models}},
\code{\link{page_walkforward_report}}, \code{\link{page_walkforward_qmd}},
\code{\link{page_validate_kit}}, \code{\link{aggregate_strata}},
\code{\link{aggregate_strata_draws}}, \code{\link{shared_denominator_correlation}},
\code{\link{m0_fit}}, \code{\link{m0_detect}}, \code{\link{m1_fit}},
\code{\link{m1_predict}}, \code{\link{m1_peak_posterior}},
\code{\link{m1_passage_posterior}}, \code{\link{m2_fit}}, \code{\link{m2_predict}},
\code{\link{evaluate_forecasts}}, \code{\link{replay_holdout}},
\code{\link{verify_promotion}}.
}
\keyword{internal}
