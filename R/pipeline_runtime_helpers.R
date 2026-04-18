# Shared runtime helpers for the prospective pipeline

# Prospective running utilities
# - Weekly/online ignition tracking and Stage-2 prospective execution helpers
# - Designed for current-season runs

#' Number of epidemiological weeks in a full season cycle
#'
#' Returns 52 or 53 depending on the ISO epidemiological week structure of the given year.
#' Uses the epidemiological week number of Dec 28, which is always in the last epiweek
#' of the year.
#'
#' @param year Integer calendar year (e.g., 2026).
#'
#' @return Integer, typically 52 or 53.
#' @export
#'
#' @examples
#' \dontrun{
#' get_full_cycle_weeks(2025)
#' get_full_cycle_weeks(2026)
#' }
get_full_cycle_weeks <- function(year) {
  # epiweek() is provided by lubridate
  max_weeks_this_year <- lubridate::epiweek(as.Date(paste0(as.integer(year), "-12-28")))
  # Weeks remaining after Week 20: (Max - 20) plus the 20 weeks of the following year
  (max_weeks_this_year - 20) + 20
}

#' Null-coalescing operator
#'
#' Returns \code{y} when \code{x} is \code{NULL}, otherwise returns \code{x}.
#'
#' @param x Any object.
#' @param y Fallback value used when \code{x} is \code{NULL}.
#'
#' @return \code{x} if not \code{NULL}, else \code{y}.
#' @keywords internal
#' @noRd
`%||%` <- function(x, y) if (!is.null(x)) x else y

#' Stable logit transform with clipping
#'
#' @param p Numeric in [0,1].
#' @param eps Clip to \code{[eps, 1-eps]} before applying \code{qlogis()}.
#'
#' @return Numeric logit-transformed values.
#' @keywords internal
#' @noRd
logit_stable <- function(p, eps = 1e-6) qlogis(pmin(pmax(p, eps), 1 - eps))

#' Extract a classifier GAM from various container objects
#'
#' Convenience helper that accepts either:
#' \itemize{
#' \item an \pkg{mgcv} \code{gam}/\code{bam} object;
#' \item a \code{gamm4} fit list with component \code{$gam};
#' \item a list returned by your \code{fitIgnition()} that contains
#'   \code{$fits$p_only_week_p$gam}.
#' }
#'
#' @param ign_fit_or_gam A trained classifier model or a container holding one.
#'
#' @return An \pkg{mgcv} \code{gam} or \code{bam} object.
#' @export
#'
#' @examples
#' \dontrun{
#' gam_cls <- get_gam_cls(ign_fit)                        # fitIgnition() output
#' gam_cls <- get_gam_cls(ign_fit$fits$p_only_week_p$gam) # direct
#' }
get_gam_cls <- function(ign_fit_or_gam) {
  if (inherits(ign_fit_or_gam, c("gam", "bam"))) return(ign_fit_or_gam)
  
  # gamm4 style list
  if (is.list(ign_fit_or_gam) &&
      "gam" %in% names(ign_fit_or_gam) &&
      inherits(ign_fit_or_gam$gam, c("gam", "bam"))) {
    return(ign_fit_or_gam$gam)
  }
  
  # fitIgnition style list
  if (is.list(ign_fit_or_gam) &&
      "fits" %in% names(ign_fit_or_gam) &&
      "p_only_week_p" %in% names(ign_fit_or_gam$fits) &&
      "gam" %in% names(ign_fit_or_gam$fits$p_only_week_p) &&
      inherits(ign_fit_or_gam$fits$p_only_week_p$gam, c("gam", "bam"))) {
    return(ign_fit_or_gam$fits$p_only_week_p$gam)
  }
  
  stop("Could not extract a GAM classifier. Pass a mgcv::gam/bam, a gamm4 list with $gam, or your full fitIgnition() output.")
}

#' Resolve a week estimate with an optional manual override
#'
#' Applies an override week to an estimated week using a selected policy:
#' \itemize{
#' \item \code{"replace"}: force the week to the override.
#' \item \code{"cap"}: final week cannot be later than override (\code{min(est, override)}).
#' \item \code{"floor"}: final week cannot be earlier than override (\code{max(est, override)}).
#' \item \code{"nearest_valid"}: snap override to the nearest value in \code{valid_weeks}.
#' }
#'
#' @param week_est Integer-ish scalar estimate (can be \code{NA}).
#' @param override_week Optional integer-ish scalar override (can be \code{NULL}/\code{NA}).
#' @param mode Override policy.
#' @param valid_weeks Integer vector of valid week values. Default 1:52.
#'
#' @return A list with elements \code{final}, \code{est}, \code{overridden}, \code{override}.
#' @export
#'
#' @examples
#' resolve_week_override(18, NULL)
#' resolve_week_override(18, 20, mode = "cap")
#' resolve_week_override(NA, 15, mode = "replace")
resolve_week_override <- function(week_est,
                                  override_week = NULL,
                                  mode = c("replace", "cap", "floor", "nearest_valid"),
                                  valid_weeks = 1:52) {
  mode <- match.arg(mode)
  est <- as.integer(week_est)
  
  if (is.null(override_week) || is.na(override_week)) {
    return(list(final = est, est = est, overridden = FALSE, override = NA_integer_))
  }
  
  ov <- as.integer(override_week)
  
  if (mode == "nearest_valid") {
    ov <- valid_weeks[which.min(abs(valid_weeks - ov))]
    return(list(final = ov, est = est, overridden = TRUE, override = ov))
  }
  
  ov <- max(min(ov, max(valid_weeks)), min(valid_weeks))
  final <- switch(
    mode,
    replace = ov,
    cap     = if (is.na(est)) ov else pmin(est, ov),
    floor   = if (is.na(est)) ov else pmax(est, ov)
  )
  
  list(final = as.integer(final), est = est, overridden = TRUE, override = ov)
}
