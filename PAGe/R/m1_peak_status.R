#' Stabilize a decimal peak estimate using only causal prior state
#'
#' The causal candidate limits the movement of the current raw peak estimate
#' relative to the previous stabilized estimate. The current raw interval
#' width is retained and translated by the bounded center update, so the
#' output remains decimal and continues to represent current uncertainty.
#'
#' @param t_peak Numeric scalar raw peak estimate.
#' @param t_peak_ci Numeric length-2 raw peak interval.
#' @param previous_state Optional prior same-season stabilized peak state.
#' @param max_jump_weeks Positive numeric maximum center movement per origin.
#' @return A list with stabilized `t_peak`, `t_peak_ci`, and the bounded
#'   `jump` from the previous stabilized center.
#' @keywords internal
.m1_stabilize_peak <- function(t_peak,
                               t_peak_ci,
                               previous_state = NULL,
                               max_jump_weeks = 2) {
  t_peak <- as.numeric(t_peak)[1L]
  t_peak_ci <- as.numeric(t_peak_ci)[seq_len(min(2L, length(t_peak_ci)))]
  if (length(t_peak_ci) < 2L) {
    t_peak_ci <- c(NA_real_, NA_real_)
  }
  if (!is.finite(t_peak)) {
    return(list(
      t_peak = NA_real_,
      t_peak_ci = c(NA_real_, NA_real_),
      jump = NA_real_
    ))
  }

  max_jump_weeks <- as.numeric(max_jump_weeks)[1L]
  if (!is.finite(max_jump_weeks) || max_jump_weeks <= 0) {
    stop("`max_jump_weeks` must be a positive finite number.", call. = FALSE)
  }

  previous_peak <- if (is.null(previous_state)) {
    NA_real_
  } else {
    as.numeric(
      previous_state$t_peak_stabilized %||%
        previous_state$t_peak %||%
        NA_real_
    )[1L]
  }

  if (!is.finite(previous_peak)) {
    return(list(
      t_peak = t_peak,
      t_peak_ci = t_peak_ci,
      jump = NA_real_
    ))
  }

  raw_jump <- t_peak - previous_peak
  jump <- max(-max_jump_weeks, min(max_jump_weeks, raw_jump))
  stabilized_peak <- previous_peak + jump
  shift <- stabilized_peak - t_peak
  stabilized_ci <- t_peak_ci + shift

  # Keep a valid interval containing the stabilized center when raw bounds
  # are available, without replacing missing uncertainty with invented values.
  if (all(is.finite(stabilized_ci))) {
    stabilized_ci <- c(
      min(stabilized_ci[1L], stabilized_peak),
      max(stabilized_ci[2L], stabilized_peak)
    )
  }

  list(
    t_peak = as.numeric(stabilized_peak),
    t_peak_ci = as.numeric(stabilized_ci),
    jump = as.numeric(jump)
  )
}

#' Prepare raw and stabilized peak fields for one alignment origin
#'
#' @param res Alignment result with a `peak` list.
#' @param peak_stabilization Character mode, either `"legacy"` or `"causal"`.
#' @param previous_state Optional same-season prior stabilized state.
#' @param max_jump_weeks Positive maximum causal center movement.
#' @return A list containing raw and downstream stabilized peak fields.
#' @keywords internal
.m1_prepare_peak <- function(res,
                             peak_stabilization = c("legacy", "causal"),
                             previous_state = NULL,
                             max_jump_weeks = 2) {
  peak_stabilization <- match.arg(peak_stabilization)
  raw <- list(
    t_peak = as.numeric(res$peak$t_peak)[1L],
    t_peak_ci = as.numeric(res$peak$t_peak_ci)[seq_len(min(2L, length(res$peak$t_peak_ci)))]
  )
  if (length(raw$t_peak_ci) < 2L) {
    raw$t_peak_ci <- c(NA_real_, NA_real_)
  }

  stabilized <- if (identical(peak_stabilization, "causal")) {
    .m1_stabilize_peak(
      t_peak = raw$t_peak,
      t_peak_ci = raw$t_peak_ci,
      previous_state = previous_state,
      max_jump_weeks = max_jump_weeks
    )
  } else {
    list(t_peak = raw$t_peak, t_peak_ci = raw$t_peak_ci, jump = NA_real_)
  }

  list(
    t_peak_raw = raw$t_peak,
    t_peak_ci_raw = raw$t_peak_ci,
    t_peak_stabilized = stabilized$t_peak,
    t_peak_ci_stabilized = stabilized$t_peak_ci,
    stabilization_jump = stabilized$jump
  )
}

#' Determine whether the epidemic peak has passed
#'
#' Uses the peak estimate from [align_forecast_pipeline_dilate()] and the
#' last observed week in the current season to decide if the peak is
#' already in the past.
#'
#' @param res List returned by [align_forecast_pipeline_dilate()]; must have
#'   a `peak` element with `t_peak` and `t_peak_ci`.
#' @param currentD Data frame of current season data with at least a
#'   `newWeek` column (the same scale used in the alignment).
#' @param use_ci Logical; if `TRUE` (default), we declare the peak "passed"
#'   once the last observed week is beyond the *upper* CI bound for the
#'   peak. If `FALSE`, we use the point estimate only.
#' @param buffer_weeks Non-negative integer; additional weeks beyond the
#'   peak (or upper CI) required before declaring the peak passed.
#' @param previous_peak_passed Logical scalar. A prior same-season passage
#'   decision that remains latched when the current origin is unavailable.
#' @param peak_override Optional peak list with `t_peak` and `t_peak_ci` to
#'   use in place of `res$peak`.
#'
#' @return A list with components:
#'   \item{peak_passed}{logical, `TRUE` if we consider the peak passed.}
#'   \item{last_obs_week}{last observed `newWeek` in `currentD`.}
#'   \item{t_peak}{estimated peak week on the same `newWeek` scale.}
#'   \item{t_peak_ci}{numeric length-2 vector with the 95\% CI for the peak.}
#'   \item{threshold_week}{week threshold used for the decision.}
peak_status_from_align <- function(res,
                                   currentD,
                                   use_ci = TRUE,
                                   buffer_weeks = 0L,
                                   previous_peak_passed = FALSE,
                                   peak_override = NULL) {
  # last observed week in alignment scale
  last_obs <- max(currentD$newWeek, na.rm = TRUE)

  # pull peak info
  peak <- if (is.null(peak_override)) res$peak else peak_override
  t_peak <- peak$t_peak
  ci <- peak$t_peak_ci

  # sanity
  if (!is.finite(t_peak)) {
    return(list(
      peak_passed = isTRUE(previous_peak_passed),
      peak_passed_now = FALSE,
      last_obs_week = last_obs,
      t_peak = NA_real_,
      t_peak_ci = c(NA_real_, NA_real_),
      threshold_week = NA_real_
    ))
  }

  # threshold: use upper CI or point estimate, plus buffer
  if (use_ci && length(ci) == 2L && all(is.finite(ci))) {
    thresh <- ci[2] + buffer_weeks
  } else {
    thresh <- t_peak + buffer_weeks
  }

  peak_passed_now <- is.finite(thresh) && last_obs >= thresh
  peak_passed <- isTRUE(previous_peak_passed) || peak_passed_now

  list(
    peak_passed = peak_passed,
    peak_passed_now = peak_passed_now,
    last_obs_week = last_obs,
    t_peak = t_peak,
    t_peak_ci = ci,
    threshold_week = thresh
  )
}
