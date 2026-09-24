#' Build a predictive distribution for the season's peak week
#'
#' Forecast engines may implement this generic and return a weighted or
#' unweighted code{page_predictive_distribution}. For PAGe, the current
#' implementation is an experimental, uncalibrated distribution over M1
#' template peak estimates.
#'
#' @param forecast A forecast object.
#' @param ... Method-specific arguments.
#' @return A code{page_predictive_distribution} with outcome
#'   code{"season_peak_week"}.
#' @export
peak_week_distribution <- function(forecast, ...) {
  UseMethod("peak_week_distribution")
}

#' @rdname peak_week_distribution
#' @param origin_week Optional forecast origin week. By default the latest M1
#'   origin is used, including an unavailable result if M1 failed at that week.
#' @export
peak_week_distribution.page_forecast <- function(forecast,
                                                 origin_week = NULL,
                                                 ...) {
  dots <- list(...)
  if (length(dots)) {
    stop("Unused arguments supplied to `peak_week_distribution.page_forecast()`.", call. = FALSE)
  }
  empty_distribution <- function(reason, origin = NULL, target = NULL) {
    new_page_predictive_distribution(
      draws = numeric(), outcome = "season_peak_week", scale = "weekF",
      support = c(0, 1), origin = origin, target = target,
      calibration = list(status = "uncalibrated", method = "weighted_template_peaks"),
      provenance = list(reason = reason), status = "unavailable"
    )
  }
  season <- forecast$season
  if (is.null(season) || length(season) != 1L || is.na(season) || !nzchar(season)) {
    stop("`forecast` must identify exactly one season.", call. = FALSE)
  }
  ensembles <- forecast$m1_peak_ensemble
  if (is.data.frame(ensembles) && nrow(ensembles) == 0L) {
    return(empty_distribution("no_m1_origins"))
  }
  if (is.null(ensembles) || !is.data.frame(ensembles) ||
    !all(c(
      "eval_week", "season", "latest_data_week", "iWeek_hat", "anchorWeek",
      "nW_true", "timing_mode", "alignment_config_id", "status", "fallback_reason",
      "template", "t_peak", "weight"
    ) %in% names(ensembles))) {
    return(empty_distribution("peak_ensemble_not_recorded"))
  }
  ensemble_seasons <- unique(as.character(ensembles$season))
  if (anyNA(ensemble_seasons) || length(ensemble_seasons) != 1L ||
    !identical(ensemble_seasons, as.character(season))) {
    stop("`m1_peak_ensemble` season does not match `forecast$season`.", call. = FALSE)
  }
  if (is.null(origin_week)) {
    eval_week <- as.numeric(ensembles$eval_week)
    if (!any(is.finite(eval_week))) {
      return(empty_distribution("no_valid_m1_origins"))
    }
    origin_week <- max(eval_week[is.finite(eval_week)])
  }
  if (!is.numeric(origin_week) || length(origin_week) != 1L || !is.finite(origin_week)) {
    stop("`origin_week` must be NULL or one finite week.", call. = FALSE)
  }
  row <- which(as.numeric(ensembles$eval_week) == origin_week)
  if (length(row) != 1L) {
    return(empty_distribution("origin_not_found", origin = list(week = origin_week, season = season)))
  }
  record <- ensembles[row, , drop = FALSE]
  origin <- list(week = as.numeric(record$eval_week), season = season)
  target <- list(
    season = season,
    n_weeks = as.integer(record$nW_true),
    definition = "M1 smooth template peak; calibrated target is earliest weekF of maximum observed positivity"
  )
  if (!identical(as.character(record$status), "available")) {
    reason <- as.character(record$fallback_reason)[1L]
    if (is.na(reason) || !nzchar(reason)) reason <- "alignment_unavailable"
    return(empty_distribution(
      reason, origin, target
    ))
  }
  n_weeks <- as.numeric(record$nW_true)
  timing_mode <- as.character(record$timing_mode)
  peak <- as.numeric(record$t_peak[[1L]])
  weights <- as.numeric(record$weight[[1L]])
  templates <- as.character(record$template[[1L]])
  if (length(peak) != length(weights) || length(templates) != length(peak) || length(peak) < 2L ||
    any(!is.finite(peak)) || any(!is.finite(weights)) || any(weights <= 0) ||
    !is.finite(n_weeks) || n_weeks < 2 ||
    !is.finite(record$iWeek_hat) || !is.finite(record$anchorWeek)) {
    return(empty_distribution("invalid_peak_ensemble", origin, target))
  }
  weights <- weights / sum(weights)
  week <- peak - as.numeric(record$anchorWeek) + as.numeric(record$iWeek_hat)
  rounding_rule <- if (identical(timing_mode, "legacy")) "base::round (ties to even)" else "none"
  if (identical(timing_mode, "legacy")) week <- round(week)
  if (!identical(timing_mode, "legacy") && !identical(timing_mode, "fractional")) {
    return(empty_distribution("unknown_timing_mode", origin, target))
  }
  inside <- week >= 1 & week <= n_weeks
  dropped_mass <- sum(weights[!inside])
  week <- week[inside]
  weights <- weights[inside]
  templates <- templates[inside]
  if (!length(week) || sum(weights) <= 0) {
    return(empty_distribution("all_peak_atoms_outside_season", origin, target))
  }
  merged <- stats::aggregate(weights, list(weekF = week), sum)
  atoms <- merged$weekF
  atom_weights <- merged$x / sum(merged$x)
  n_atoms <- length(atoms)
  effective_n <- 1 / sum(atom_weights^2)
  if (n_atoms < 2L || effective_n < 2) {
    return(empty_distribution("insufficient_effective_peak_atoms", origin, target))
  }
  new_page_predictive_distribution(
    draws = atoms, weights = atom_weights,
    outcome = "season_peak_week", scale = "weekF",
    support = c(1, n_weeks), origin = origin,
    target = c(target, list(origin_week = origin$week)),
    calibration = list(
      status = "uncalibrated", method = "weighted_template_peaks",
      uncertainty = "between-template spread only", n_atoms = n_atoms,
      effective_n = effective_n, dropped_mass = dropped_mass
    ),
    provenance = list(
      engine = "PAGe M1 multi-template alignment",
      alignment_config_id = as.character(record$alignment_config_id),
      timing_mode = timing_mode, rounding_rule = rounding_rule,
      latest_data_week = as.numeric(record$latest_data_week),
      templates = templates, peak_basis = "raw_ensemble"
    ),
    status = "experimental"
  )
}

#' @rdname peak_week_distribution
#' @export
peak_week_distribution.default <- function(forecast, ...) {
  stop(
    "No `peak_week_distribution()` method is registered for class `",
    class(forecast)[[1L]], "`.",
    call. = FALSE
  )
}

#' Compute the probability that the season peak is before a week
#'
#' For a forecast object, the peak distribution is first created using its
#' registered method. For a distribution object, the supplied outcome must be
#' code{"season_peak_week"} and its target metadata must declare
#' code{n_weeks}. Strict mode returns eqn{P(peak < week)}; inclusive mode
#' returns eqn{P(peak <= week)}. PAGe's current distribution is experimental,
#' between-template spread only, and is not calibrated against observed peaks.
#'
#' @param forecast_or_distribution Forecast or predictive-distribution object.
#' @param week One finite threshold in the distribution's declared scale.
#' @param inclusive If TRUE, calculate eqn{P(peak <= week)}; otherwise
#'   calculate eqn{P(peak < week)}.
#' @param origin_week Optional origin passed to code{peak_week_distribution()}.
#' @return One probability with code{mc_se}, code{mc_interval},
#'   code{dropped_mass}, code{partly_observed}, and code{uncertainty}
#'   attributes. For PAGe, code{partly_observed} is TRUE when
#'   code{week <= origin week}; the model's peak atoms do not condition on
#'   the observed maximum.
#' @export
probability_peak_before <- function(forecast_or_distribution,
                                    week,
                                    inclusive = FALSE,
                                    origin_week = NULL) {
  distribution <- if (inherits(forecast_or_distribution, "page_predictive_distribution")) {
    if (!is.null(origin_week)) {
      stop("`origin_week` cannot be used with a distribution object.", call. = FALSE)
    }
    forecast_or_distribution
  } else {
    if (is.null(origin_week)) {
      peak_week_distribution(forecast_or_distribution)
    } else {
      peak_week_distribution(forecast_or_distribution, origin_week = origin_week)
    }
  }
  if (!identical(distribution$outcome, "season_peak_week")) {
    stop("`distribution` must have outcome `season_peak_week`.", call. = FALSE)
  }
  if (identical(distribution$status, "unavailable")) {
    return(probability_below(distribution, week, inclusive = inclusive))
  }
  if (is.null(distribution$target$n_weeks) || !is.finite(distribution$target$n_weeks)) {
    stop("Peak distribution must declare `target$n_weeks`.", call. = FALSE)
  }
  p <- probability_below(distribution, week, inclusive = inclusive)
  origin_week_value <- distribution$origin$week %||% NA_real_
  attr(p, "dropped_mass") <- distribution$calibration$dropped_mass %||% NA_real_
  attr(p, "partly_observed") <- is.finite(origin_week_value) && week <= origin_week_value
  attr(p, "uncertainty") <- distribution$calibration$uncertainty %||% NA_character_
  p
}
