\name{PAGe-public-api}
\alias{page_train}
\alias{page_forecast}
\alias{page_models}
\alias{page_walkforward_report}
\alias{page_walkforward_qmd}
\alias{page_render_report}
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
page_walkforward_report(data = NULL, ...)
page_walkforward_qmd(data = NULL, season = NULL, output_dir = "reports",
  file_name = NULL, render = TRUE, ...)
page_render_report(...)
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
\item{data}{Optional canonical typed A/B panel, OLIS \code{.RData} snapshot, or official ORVT CSV path. When \code{NULL} (the default), the latest \code{hist*.RData} snapshot in the default IRVRI \code{OP} directory is used when present, otherwise the current season is fetched from the live PHO ORVT feed.}
\item{season}{Optional season label (for example \code{"2026-27"}). When \code{NULL} and an OLIS snapshot is supplied, the latest season present is used.}
\item{output_dir}{Directory that receives the generated \code{.qmd}, any plot assets, and the rendered \code{.html}.}
\item{file_name}{Optional \code{.qmd} file name. Defaults to \code{page_walkforward_<season>_week<origin>.qmd}.}
\item{render}{When \code{TRUE} (default), render the \code{.qmd} to a self-contained HTML document using the Quarto CLI.}
\item{...}{Arguments passed to the corresponding governed PAGe implementation. See the function-specific examples and the public API walkthrough for the supported workflow.}
}
\description{
These functions define the stable user-facing PAGe interface. Development-generation labels such as v1, v2, and v3 are intentionally absent from public function names. Historical versioned implementation functions remain internal so frozen releases and repository-owned reproduction workflows can retain exact provenance.
}
\details{
\code{page_train()}, \code{page_forecast()}, \code{page_walkforward_report()}, \code{page_walkforward_qmd()}, and the kit helpers are high-level PAGe workflows. \code{m0_*}, \code{m1_*}, and \code{m2_*} functions provide the advanced scientific component interface. \code{aggregate_strata()} and \code{aggregate_strata_draws()} support general stratified aggregation, including pathogen types, age groups, regions, sites, independent strata, explicit correlation/covariance structures, and joint simulation draws. \code{page_render_report()} is an alias for \code{page_walkforward_qmd()}, which emits a cumulative Quarto \code{.qmd} with per-origin as-of tabsets and optionally renders it to HTML.

The complete supported namespace is documented in \code{docs/public-api.qmd} in the source repository.
}
