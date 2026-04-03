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
#'
#' @return A list with components:
#'   \item{peak_passed}{logical, `TRUE` if we consider the peak passed.}
#'   \item{last_obs_week}{last observed `newWeek` in `currentD`.}
#'   \item{t_peak}{estimated peak week on the same `newWeek` scale.}
#'   \item{t_peak_ci}{numeric length-2 vector with the 95\% CI for the peak.}
#'   \item{threshold_week}{week threshold used for the decision.}
#' @export
peak_status_from_align <- function(res,
                                   currentD,
                                   use_ci = TRUE,
                                   buffer_weeks = 0L) {
  # last observed week in alignment scale
  last_obs <- max(currentD$newWeek, na.rm = TRUE)
  
  # pull peak info
  peak <- res$peak
  t_peak <- peak$t_peak
  ci     <- peak$t_peak_ci
  
  # sanity
  if (!is.finite(t_peak)) {
    return(list(
      peak_passed    = FALSE,
      last_obs_week  = last_obs,
      t_peak         = NA_real_,
      t_peak_ci      = c(NA_real_, NA_real_),
      threshold_week = NA_real_
    ))
  }
  
  # threshold: use upper CI or point estimate, plus buffer
  if (use_ci && length(ci) == 2L && all(is.finite(ci))) {
    thresh <- ci[2] + buffer_weeks
  } else {
    thresh <- t_peak + buffer_weeks
  }
  
  peak_passed <- is.finite(thresh) && last_obs >= thresh
  
  list(
    peak_passed    = peak_passed,
    last_obs_week  = last_obs,
    t_peak         = t_peak,
    t_peak_ci      = ci,
    threshold_week = thresh
  )
}
