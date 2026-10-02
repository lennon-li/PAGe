# Stable public API ----------------------------------------------------------
#
# These wrappers define the supported user-facing PAGe interface. Historical
# implementation names (including v1/v2/v3 development labels) remain internal
# so frozen artifacts, provenance, and repository-owned reproduction scripts can
# continue to resolve the exact implementation they were built against.

#' Train the PAGe forecasting system
#'
#' Stable entry point for governed PAGe training. This wraps the production
#' training workflow while hiding stage-specific tuning/build/freeze helpers.
#'
#' @inheritParams page_train_workflow
#' @return A governed PAGe training workflow result.
#' @export
page_train <- function(...) {
  page_train_workflow(...)
}

#' Forecast with the current PAGe production release
#'
#' Runs the current governed production forecast for a canonical surveillance
#' panel, OLIS snapshot, or supported ORVT input.
#'
#' @inheritParams page_v3_forecast
#' @return The current PAGe forecast result.
#' @export
page_forecast <- function(...) {
  out <- page_v3_forecast(...)
  class(out) <- "page_forecast_result"
  out
}

#' @method print page_forecast_result
#' @export
print.page_forecast_result <- function(x, ...) {
  cat("<PAGe forecast>\n")
  cat("  season/origin: ", x$season, " / weekF", x$origin_weekF, "\n", sep = "")
  cat("  status: ", x$status, "; ", if (isTRUE(x$issued)) "issued" else "not issued", "\n", sep = "")
  if (isTRUE(x$issued)) {
    m0 <- x$monitoring$A$m0
    cat("  A ignition: ", if (isTRUE(m0$ignited)) paste0("yes @ weekF", format(m0$ignition_weekF, digits = 4)) else "no", "\n", sep = "")
    m1 <- x$monitoring$A$m1
    if (isTRUE(m1$available)) {
      cat("  A peak: weekF", format(m1$peak_mean_weekF, digits = 4),
          " (90% ", format(m1$peak_q05_weekF, digits = 4), "-", format(m1$peak_q95_weekF, digits = 4), ")\n", sep = "")
    } else {
      cat("  A peak: unavailable (", m1$state, ")\n", sep = "")
    }
    if (is.data.frame(x$forecasts) && nrow(x$forecasts)) {
      show <- x$forecasts[, intersect(c("type", "horizon", "forecast_pct", "route"), names(x$forecasts)), drop = FALSE]
      print(show, row.names = FALSE, digits = 5)
    }
  }
  invisible(x)
}

#' Inspect the current PAGe production model bundle
#'
#' Returns the validated frozen production model bundle and release metadata.
#'
#' @return The current production model bundle.
#' @export
page_models <- function() {
  page_v3_models()
}

#' Render the PAGe walk-forward report
#'
#' Generates the current self-contained A/B/A+B walk-forward HTML report.
#'
#' @inheritParams page_v3_walkforward_report
#' @return Invisibly, the normalized path to the generated HTML report.
#' @export
page_walkforward_report <- function(...) {
  page_v3_walkforward_report(...)
}

#' Validate a PAGe kit
#'
#' @inheritParams validate_page_kit
#' @return Invisibly, the validated kit.
#' @export
page_validate_kit <- function(...) {
  validate_page_kit(...)
}

#' Aggregate stratified forecasts
#'
#' Stable public wrapper for analytic aggregation across arbitrary strata.
#'
#' @inheritParams page_aggregate_strata
#' @return A `page_strata_aggregate` object.
#' @export
aggregate_strata <- function(...) {
  page_aggregate_strata(...)
}

#' Aggregate joint forecast draws across strata
#'
#' Preferred aggregation path when posterior or simulation draws are available.
#'
#' @inheritParams page_aggregate_strata_draws
#' @return A `page_strata_aggregate_draws` object.
#' @export
aggregate_strata_draws <- function(...) {
  page_aggregate_strata_draws(...)
}

#' Shared-denominator multinomial correlation
#'
#' @inheritParams page_shared_denominator_correlation
#' @return A stratum correlation matrix.
#' @export
shared_denominator_correlation <- function(...) {
  page_shared_denominator_correlation(...)
}

#' Fit M0
#'
#' Advanced model-level interface for fitting the ignition component.
#'
#' @inheritParams fit_m0
#' @return A draft M0 fit artifact.
#' @export
m0_fit <- function(...) {
  fit_m0(...)
}

#' Detect epidemic ignition with M0
#'
#' Advanced model-level runtime interface for the ignition component.
#'
#' @inheritParams run_m0
#' @return The current M0 ignition state.
#' @export
m0_detect <- function(...) {
  run_m0(...)
}

#' Fit M1
#'
#' Advanced model-level interface for fitting the timing component.
#'
#' @inheritParams fit_m1
#' @return A draft M1 fit artifact.
#' @export
m1_fit <- function(...) {
  fit_m1(...)
}

#' Predict timing with M1
#'
#' Runs the current governed M1 timing implementation.
#'
#' @inheritParams run_m1_v2_timing
#' @return The current M1 timing result.
#' @export
m1_predict <- function(...) {
  run_m1_v2_timing(...)
}

#' Compute the M1 peak-time posterior
#'
#' @inheritParams m1_v2_peak_posterior
#' @return A peak-time posterior result.
#' @export
m1_peak_posterior <- function(...) {
  m1_v2_peak_posterior(...)
}

#' Compute the M1 peak-passage posterior
#'
#' @inheritParams m1_v2_passage_posterior
#' @return A peak-passage posterior result.
#' @export
m1_passage_posterior <- function(...) {
  m1_v2_passage_posterior(...)
}

#' Fit M2
#'
#' Advanced model-level interface for fitting the short-horizon forecasting
#' component.
#'
#' @inheritParams fit_m2
#' @return A draft M2 fit artifact.
#' @export
m2_fit <- function(...) {
  fit_m2(...)
}

#' Predict with M2
#'
#' Advanced model-level runtime interface for the short-horizon component.
#'
#' @inheritParams run_m2
#' @return One- and two-week-ahead M2 forecast output.
#' @export
m2_predict <- function(...) {
  run_m2(...)
}

#' Evaluate forecasts with nested season validation
#'
#' Stable public wrapper around the governed nested season evaluation.
#'
#' @inheritParams nested_season_evaluation
#' @return A nested season evaluation result.
#' @export
evaluate_forecasts <- function(...) {
  nested_season_evaluation(...)
}

#' Replay a frozen holdout season
#'
#' @inheritParams replay_season_holdout
#' @return A holdout replay result.
#' @export
replay_holdout <- function(...) {
  replay_season_holdout(...)
}

#' Verify promotion evidence
#'
#' @inheritParams verify_promotion_evidence
#' @return Promotion-evidence verification output.
#' @export
verify_promotion <- function(...) {
  verify_promotion_evidence(...)
}
