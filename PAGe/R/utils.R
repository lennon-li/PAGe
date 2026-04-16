#' PAGe: Seasonal Flu Curve Alignment and Forecasting
#' @import ggplot2
#' @import dplyr
#' @import tidyr
#' @import purrr
#' @import tibble
#' @import nloptr
#' @import mgcv
#' @import gamm4
#' @import plotly
#' @import MMWRweek
#'
#' @keywords internal
"_PACKAGE"


# Utilities and numerics

#' Numerical central-difference derivative
#'
#' Approximates the derivative of \code{f} at \code{x} using a symmetric
#' two-point central-difference formula.
#'
#' @param x Numeric scalar at which to evaluate the derivative.
#' @param f A function of a single numeric argument.
#' @param eps Numeric step size (default \code{1e-3}).
#'
#' @return A numeric scalar approximating \code{f'(x)}.
#' @export
num_deriv <- function(x, f, eps = 1e-3) (f(x + eps) - f(x - eps)) / (2 * eps)

#' Find the peak of a reference template curve
#'
#' Evaluates \code{g_ref_fun} over a fine grid and returns the \code{u} value
#' where the curve is maximised.
#'
#' @param g_ref_fun Reference curve function on the logit scale.
#' @param u_range Numeric vector of length 2; grid endpoints
#'   (default \code{c(1, 52)}).
#' @param by Numeric grid step size (default 0.01).
#'
#' @return A numeric scalar; the \code{u} value of the template peak.
#' @keywords internal
template_peak_u <- function(g_ref_fun, u_range = c(1, 52), by = 0.01) {
  u <- seq(u_range[1], u_range[2], by = by)
  u[which.max(g_ref_fun(u))]
}

#' Check whether a covariance matrix is valid
#'
#' Returns \code{TRUE} only if \code{V} is a finite, square, positive-definite
#' matrix with a positive determinant. Used to guard downstream delta-method
#' calculations.
#'
#' @param V Object to test.
#'
#' @return Logical scalar.
#' @keywords internal
is_cov_ok <- function(V) {
  is.matrix(V) && all(is.finite(V)) && nrow(V) == ncol(V) &&
    is.finite(det(V)) && det(V) > 1e-12 &&
    all(eigen(V, symmetric = TRUE, only.values = TRUE)$values > 0
  )
}

#' Wilson score confidence interval for a proportion
#'
#' Computes the Wilson score interval for observed count \code{y} out of
#' \code{n} trials at the requested confidence level.
#'
#' @param y Integer or numeric; number of successes.
#' @param n Integer or numeric; number of trials.
#' @param level Numeric; confidence level (default 0.95).
#'
#' @return A two-column numeric matrix with columns \code{lo} and \code{hi},
#'   both clamped to \eqn{[0, 1]}.
#' @keywords internal
wilson_ci <- function(y, n, level = 0.95) {
  z <- qnorm((1 + level)/2)
  ph <- y / n
  den <- 1 + z^2 / n
  ctr <- (ph + z^2/(2*n)) / den
  half <- (z * sqrt(pmax(ph*(1 - ph)/n, 0) + z^2/(4*n^2))) / den
  cbind(lo = pmax(0, ctr - half), hi = pmin(1, ctr + half))
}

#' Number of MMWR weeks in a flu-season start year
#'
#' Returns 52 for most years and 53 for years in which the last day of
#' December falls in MMWR week 53 (a 53-week year). Used to correctly
#' compute within-season week indices that wrap across the year boundary.
#'
#' @param start_year Integer; the calendar year that contains the start of
#'   the flu season (i.e. the year containing the season anchor week 27).
#'
#' @return Integer scalar, either 52L or 53L.
#' @keywords internal
n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
}

#' Logit transformation with clipping
#'
#' Applies \code{qlogis()} after clamping \code{p} to \eqn{[10^{-6},\,
#' 1 - 10^{-6}]} to avoid \eqn{\pm\infty} at the boundary.
#'
#' @param p Numeric vector of probability values in \eqn{(0, 1)}.
#'
#' @return Numeric vector of logit-transformed values.
#' @keywords internal
logit <- function(p) qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))

#' @export
g_ref_safe <- function(u) g_ref_fun(pmin(pmax(u, 1), 52))



#' Build reference link-scale function from a fitted GAM
#'
#' @param gam_obj a fitted mgcv::gam (or gamm4::$gam) with predictor `newWeek`
#' @param week_grid numeric vector of weeks to interpolate over (default 1:52)
#'
#' @return a function f(u) that returns logit(p̂(u)) for arbitrary (possibly fractional) u
#' @export
make_g_ref_fun <- function(gam_obj, week_grid = 1:52) {
  grid <- data.frame(newWeek = week_grid)
  eta_hat <- drop(stats::predict(gam_obj, newdata = grid, type = "link"))
  stats::splinefun(week_grid, eta_hat, method = "natural")
}


#' Build reference mean/SE function from GAM (link scale)
#'
#' @param gam_obj a fitted mgcv::gam (or gamm4::$gam)
#'
#' @return a function f(u) that returns list(mu = ..., se = ...) on link scale
#' @export
make_g_ref_mu_se <- function(gam_obj) {
  function(u) {
    nd <- data.frame(newWeek = u)
    pr <- stats::predict(gam_obj, newdata = nd, type = "link", se.fit = TRUE)
    list(mu = drop(pr$fit), se = drop(pr$se.fit))
  }
}

#' @export
makeTable <-function(res){
  tibble::tibble(
    `tau_hat`          = res$tau,
    `delta_hat`        = res$delta,
    `fallback`         = ifelse(is.na(res$fallback_reason), "", "[τ-only fallback]"),
    `Peak week`        = res$peak$t_peak,
    `Peak week (LCL)`  = res$peak$t_peak_ci[1],
    `Peak week (UCL)`  = res$peak$t_peak_ci[2],
    `Peak probability` = res$peak$p_peak
  )
}

#' Mark in-season weeks based on a positivity threshold
#'
#' Given the output `res` from [align_forecast_pipeline_dilate()], this function
#' finds the first week the fitted curve exceeds `threshold` and the first week
#' after the peak where it falls back below `threshold`. It also marks each week
#' as "in-season" or not.
#'
#' @param res A list returned by [align_forecast_pipeline_dilate()], containing
#'   at least `pred_df` (with columns `newWeek`, `p_hat`) and `peak` (with
#'   `t_peak`).
#' @param threshold Numeric positivity threshold (e.g. `0.05` for 5\%).
#' @param min_run Integer, minimum run length of consecutive weeks above the
#'   threshold to declare the start of the season.
#'
#' @return A list with elements:
#' \itemize{
#'   \item `start_week` – first surveillance week above `threshold`.
#'   \item `end_week`   – first week after the peak where fitted positivity
#'         falls below `threshold`.
#'   \item `in_season`  – logical vector the same length as `res$pred_df$newWeek`,
#'         indicating in-season weeks.
#' }
#'
#' @export
mark_season_weeks <- function(res, threshold = 0.05, min_run = 1L) {
  df <- res$pred_df
  
  # Use fitted p_hat curve to define season
  wk  <- df$newWeek
  ph  <- df$p_hat
  
  above <- ph >= threshold
  
  # run-length encoding to enforce min_run consecutive weeks
  r <- rle(above)
  idx <- which(r$values & r$lengths >= min_run)
  if (length(idx) == 0L) {
    return(list(
      start_week = NA_integer_,
      end_week   = NA_integer_,
      in_season  = rep(FALSE, length(wk))
    ))
  }
  
  # first run of "TRUE" with sufficient length
  first_run_start <- sum(r$lengths[seq_len(idx[1] - 1)]) + 1L
  start_week <- wk[first_run_start]
  
  # end: first week **after the peak** dropping below threshold
  peak_week <- floor(res$peak$t_peak)
  after_peak <- wk >= peak_week
  below_after <- (!above) & after_peak
  
  if (!any(below_after)) {
    end_week <- max(wk)
  } else {
    end_week <- wk[which(below_after)[1]]
  }
  
  in_season <- wk >= start_week & wk < end_week
  
  list(
    start_week = start_week,
    end_week   = end_week-1,
    in_season  = in_season
  )
}

#' Map surveillance week to newWeek index in a season
#'
#' @param season_df data frame with columns `week` and `newWeek`
#' @param week_vec  vector of surveillance weeks to map
#' @return integer vector of newWeek indices
#' @export
get_newWeek_from_week <- function(season_df, week_vec) {
  key <- season_df %>%
    dplyr::distinct(week, newWeek)
  
  idx <- match(week_vec, key$week)
  key$newWeek[idx]
}



#' Number of MMWR weeks in a flu-season start year (unqualified MMWRweek call)
#'
#' Variant of \code{n_weeks_in_start_year()} used in contexts where
#' \code{MMWRweek} is available without package qualification (e.g. inside
#' scripts that attach the \pkg{MMWRweek} namespace).
#'
#' @param start_year Integer; the calendar year containing the season
#'   anchor week 27.
#'
#' @return Integer scalar, either 52L or 53L.
#' @keywords internal
n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
}

#' Remove all functions from the global environment
#'
#' Lists every object in \code{.GlobalEnv} and removes any that are
#' functions. Intended for sourced-script cleanup. Calls \code{gc()} before
#' returning.
#'
#' @return \code{invisible(NULL)}.
#' @keywords internal
remove_global_functions <- function() {
  env <- .GlobalEnv
  objs <- ls(envir = env, all.names = TRUE)
  funs <- objs[vapply(objs, function(nm) is.function(get(nm, envir = env, inherits = FALSE)),
                      logical(1))]
  if (length(funs)) rm(list = funs, envir = env)
  invisible(gc())
}
