% Generated from R/stage_contracts.R.
\name{stage_contracts}
\alias{validate_season_selection}
\alias{season_selection}
\alias{fit_m0}
\alias{freeze_m0}
\alias{validate_m0_tuning}
\alias{fit_m1}
\alias{freeze_m1}
\alias{validate_m1_tuning}
\alias{tune_m2}
\alias{fit_m2}
\alias{freeze_m2}
\alias{validate_m2_tuning}
\title{Governed PAGe stage lifecycle contracts}
\usage{
validate_season_selection(
  data,
  training_seasons,
  exclude_seasons = character(0),
  holdout_seasons = character(0),
  application_seasons = character(0)
)

season_selection(x, ...)

fit_m0(data, selection, config, ...)
freeze_m0(fit, tuning = NULL, ...)
validate_m0_tuning(x, ...)

fit_m1(data, selection, m0, config, ...)
freeze_m1(fit, tuning = NULL, ...)
validate_m1_tuning(x, ...)

tune_m2(data, selection, m0, m1, grid, ...)
fit_m2(data, selection, m0, m1, config, ...)
freeze_m2(fit, tuning = NULL, ...)
validate_m2_tuning(x, ...)
}
\arguments{
\item{data}{Canonical PAGe surveillance data containing a \code{season}
column.}
\item{training_seasons,exclude_seasons,holdout_seasons,application_seasons}{
Character vectors defining mutually disjoint governed season sets.}
\item{x}{A governed selection, stage artifact, or stage tuning result.}
\item{...}{Additional arguments passed to the underlying existing stage
implementation, or reserved for methods.}
\item{selection}{A validated \code{page_season_selection}.}
\item{config}{A non-empty named list containing the fixed stage
configuration.}
\item{fit}{A draft governed stage fit.}
\item{tuning}{An optional governed tuning result whose selection and selected
configuration must match the fit.}
\item{m0}{A frozen governed M0 fit.}
\item{m1}{A frozen governed M1 fit.}
\item{grid}{The M2 tuning candidate grid.}
}
\value{
\code{validate_season_selection()} returns a
\code{page_season_selection}. The \code{fit_*()} functions return draft stage
artifacts containing the real fitted payload; \code{freeze_*()} returns the
same artifact in a validated frozen state. Tuning validators return their
input invisibly. \code{tune_m2()} returns a \code{page_m2_tuning}.
}
\description{
These functions enforce explicit season selection, deterministic
training-data and artifact identities, validated tuning gates, and frozen
upstream dependencies across M0, M1, and M2. They call the existing stage
algorithms without changing their statistical specifications.
}
