% Generated manually because roxygen2/pkgload is unavailable under this R 4.6 sandbox.
\name{fit_m2_a_ntrend_shadow}
\alias{fit_m2_a_ntrend_shadow}
\title{Tune a causal test-volume trend for the M2-A state forecast}
\usage{
fit_m2_a_ntrend_shadow(
  weekly_data,
  windows = 0:4,
  min_origin_week = 13L,
  min_chronological_train_seasons = 3L,
  off_tolerance = 1e-04
)
}
\arguments{
\item{weekly_data}{Weekly A surveillance data with season, weekF, y, and N.}
\item{windows}{Integer causal lookback windows. Must include zero, the explicit OFF candidate.}
\item{min_origin_week}{Earliest forecast origin.}
\item{min_chronological_train_seasons}{Minimum number of prior seasons for chronological evaluation.}
\item{off_tolerance}{Absolute mean-NLL tolerance within which the zero/OFF candidate is preferred.}
}
\value{A \code{page_m2_a_ntrend_shadow} artifact containing LOSO and chronological scores, the selected window, and a full-history shadow fit.}
\description{Evaluates causal log-test-volume slopes while preserving window zero as an explicit null model. This is shadow-only and does not modify the canonical v3 release.}
