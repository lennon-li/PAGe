% Generated manually because roxygen2/pkgload is unavailable under this R 4.6 sandbox.
\name{predict_m2_a_ntrend_shadow}
\alias{predict_m2_a_ntrend_shadow}
\title{Predict from an M2-A test-volume-trend shadow artifact}
\usage{
predict_m2_a_ntrend_shadow(artifact, weekly_data, origin_week, horizons = c(1L, 2L))
}
\arguments{
\item{artifact}{Result of \code{fit_m2_a_ntrend_shadow()}.}
\item{weekly_data}{One-season weekly data with weekF, y, and N.}
\item{origin_week}{Forecast origin week.}
\item{horizons}{Integer forecast horizons.}
}
\value{A data frame of shadow forecasts with the selected N-trend window and enabled/off state.}
\description{Uses only observations at or before the forecast origin. Window zero reproduces the A1-style state model without a test-volume-trend term.}
