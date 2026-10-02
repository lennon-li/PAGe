\name{page_v3_walkforward_report}
\alias{page_v3_walkforward_report}
\title{Render the PAGe v3 walk-forward HTML report}
\usage{
page_v3_walkforward_report(
  data,
  season = NULL,
  origins = NULL,
  output_file = "PAGe_walkforward_report.html",
  self_contained = TRUE,
  strict = TRUE
)
}
\arguments{
\item{data}{A canonical typed A/B panel, an OLIS \code{.RData} snapshot, or a local official ORVT CSV accepted by \code{page_v3_forecast()}.}
\item{season}{Optional season label. Required where \code{page_v3_forecast()} requires it, for example for an ORVT CSV path.}
\item{origins}{Integer origin weeks to expose as report tabs. Defaults to Weeks 8 through the latest available origin.}
\item{output_file}{Destination HTML file. Parent directories are created.}
\item{self_contained}{Logical. When \code{TRUE}, embeds Plotly JavaScript so the report has no network dependency. When \code{FALSE}, references the Plotly CDN.}
\item{strict}{Passed to \code{page_v3_forecast()} and the typed-panel validator.}
}
\value{
Invisibly, the normalized path to the generated HTML report.
}
\description{
Generates the interactive A/B/A+B walk-forward report used by the governed 2026-27 Week-12 shadow workflow. The report includes current hero metrics, historical origin diagnostics, A/B forecast uncertainty, Flu A peak CDF/hazard views, and the peak-normalized full-season M1 shape view. Report-support assets are shipped separately from the frozen forecasting release and do not alter model identity.
}
