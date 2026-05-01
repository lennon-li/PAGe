#' Learn tau/delta bounds and penalty from historical seasons
#'
#' Fits \eqn{(\tau, \delta)} for each historical season to empirically derive
#' the alignment search bounds (\code{TAU_BOUNDS}, \code{DELTA_BOUNDS}), the
#' week at which \code{delta} becomes estimable
#' (\code{WEEK_THRESHOLD_DELTA}), and the ridge penalty coefficient
#' (\code{LAMBDA_DELTA}). Bounds are the empirical quantile range (controlled
#' by \code{robust_q}) plus a buffer. The penalty is calibrated from the
#' median curvature of the NLL surface with respect to \code{delta}.
#'
#' @param theD Data frame of aligned historical seasons with columns
#'   \code{season}, \code{newWeek}, \code{y}, and \code{neg}.
#' @param g_ref_fun Reference curve function on the logit scale.
#' @param tau_range_init,delta_range_init Numeric vectors of length 2;
#'   initial search bounds for the optimisation over historical seasons
#'   (defaults \code{c(-12, 12)} and \code{c(-0.35, 0.35)}).
#' @param robust_q Numeric vector of length 2; lower/upper quantile
#'   probabilities used to derive empirical bounds (default \code{c(0.05,
#'   0.95)}).
#' @param buffer_tau,buffer_delta Numeric; extra margin added to each side of
#'   the empirical bounds (defaults 1.0 and 0.05).
#' @param obs_cuts Integer vector; observation-week cutoffs used to assess
#'   when \code{delta} stabilises (default \code{seq(12, 44, by = 4)}).
#' @param rel_sd_target Numeric; relative SD threshold below which \code{delta}
#'   is considered stable across seasons (default 0.25).
#' @param lambda_scale Numeric; fraction of the median NLL curvature used as
#'   \code{LAMBDA_DELTA} (default 0.20).
#' @param h_delta Numeric; step size for the NLL curvature finite difference
#'   (default 0.01).
#'
#' @return A list with \code{TAU_BOUNDS}, \code{DELTA_BOUNDS},
#'   \code{WEEK_THRESHOLD_DELTA}, \code{LAMBDA_DELTA}, \code{tau_delta_hist},
#'   \code{delta_stability}, \code{stability_summary}, and
#'   \code{curvature_Dpp}.
learn_alignment_hyperparams <- function(
    theD, g_ref_fun,
    tau_range_init   = c(-12, 12),
    delta_range_init = c(-0.35, 0.35),
    robust_q         = c(0.05, 0.95),
    buffer_tau       = 1.0,
    buffer_delta     = 0.05,
    obs_cuts         = seq(12, 44, by = 4),
    rel_sd_target    = 0.25,
    lambda_scale     = 0.20,
    h_delta          = 0.01
) {
  # ⇩⇩⇩ ADD THIS LINE SO THE FUNCTION ACTUALLY USES THE ARGUMENT ⇩⇩⇩
  g_ref_safe <- function(u) g_ref_fun(pmin(pmax(u, 1), 52))

  seasons <- unique(theD$season)

  # Unweighted NLL: consistent with safe_obj() which normalises by n_eff.
  # Removing weights=n ensures LAMBDA_DELTA is on the same per-observation scale,
  # so the penalty in safe_obj() is correctly calibrated against the data signal.
  nll_tau_delta <- function(t, y, n, tau, delta) {
    u <- (t - tau) / (1 + delta)
    g <- g_ref_safe(u)
    ok <- is.finite(g) & n > 0
    if (sum(ok) < 2) return(1e9)
    fit <- try(glm(cbind(y[ok], n[ok] - y[ok]) ~ g[ok], family = binomial()), silent = TRUE)
    if (inherits(fit, "try-error")) return(1e9)
    -as.numeric(logLik(fit))
  }

  tau_delta_hist <- purrr::map_dfr(seasons, function(s) {
    df <- dplyr::filter(theD, season == s)
    t <- df$newWeek; y <- df$y; n <- df$y + df$neg
    obj <- function(par) nll_tau_delta(t, y, n, tau = par[1], delta = par[2])
    opt <- optim(c(0, 0), obj, method = "L-BFGS-B",
                 lower = c(tau_range_init[1],   delta_range_init[1]),
                 upper = c(tau_range_init[2],   delta_range_init[2]))
    tibble::tibble(season = s, tau_hat = opt$par[1], delta_hat = opt$par[2], nll = opt$value)
  })

  tau_emp   <- stats::quantile(tau_delta_hist$tau_hat,   probs = robust_q, na.rm = TRUE)
  delta_emp <- stats::quantile(tau_delta_hist$delta_hat, probs = robust_q, na.rm = TRUE)
  TAU_BOUNDS   <- c(tau_emp[1]  - buffer_tau,   tau_emp[2]  + buffer_tau)
  DELTA_BOUNDS <- c(delta_emp[1]- buffer_delta, delta_emp[2]+ buffer_delta)

  delta_stability <- purrr::map_dfr(obs_cuts, function(cut) {
    purrr::map_dfr(seasons, function(s) {
      df <- dplyr::filter(theD, season == s, newWeek <= cut)
      t <- df$newWeek; y <- df$y; n <- df$y + df$neg
      if (length(t) < 6) return(tibble::tibble(season = s, week_cut = cut, delta_hat = NA_real_))
      obj <- function(par) nll_tau_delta(t, y, n, tau = par[1], delta = par[2])
      opt <- optim(c(0, 0), obj, method = "L-BFGS-B",
                   lower = c(tau_range_init[1],   delta_range_init[1]),
                   upper = c(tau_range_init[2],   delta_range_init[2]))
      tibble::tibble(season = s, week_cut = cut, delta_hat = opt$par[2])
    })
  })

  stability_summary <- delta_stability |>
    dplyr::group_by(week_cut) |>
    dplyr::summarise(sd_delta = stats::sd(delta_hat, na.rm = TRUE), .groups = "drop") |>
    dplyr::mutate(rel_sd = sd_delta / max(sd_delta, na.rm = TRUE))

  WEEK_THRESHOLD_DELTA <- stability_summary |>
    dplyr::filter(rel_sd <= rel_sd_target) |>
    dplyr::summarise(w = if (dplyr::n() == 0) NA_real_ else min(week_cut)) |>
    dplyr::pull(w)
  if (is.na(WEEK_THRESHOLD_DELTA)) WEEK_THRESHOLD_DELTA <- ceiling(stats::median(obs_cuts))

  curv_by_season <- purrr::map_dbl(seasons, function(s) {
    df <- dplyr::filter(theD, season == s)
    t <- df$newWeek; y <- df$y; n <- df$y + df$neg
    tau_hat_s <- dplyr::filter(tau_delta_hist, season == s)$tau_hat
    nll_delta <- function(d) nll_tau_delta(t, y, n, tau = tau_hat_s, delta = d)
    nll2 <- function(d) 2 * nll_delta(d)
    Dpp <- (nll2(h_delta) - 2*nll2(0) + nll2(-h_delta)) / (h_delta^2)
    Dpp
  })
  Dpp_med <- stats::median(curv_by_season[is.finite(curv_by_season) & curv_by_season > 0], na.rm = TRUE)
  LAMBDA_DELTA <- as.numeric(lambda_scale * Dpp_med)

  # guards
  DELTA_BOUNDS <- as.numeric(DELTA_BOUNDS)
  if (DELTA_BOUNDS[1] > 0) DELTA_BOUNDS[1] <- 0
  if (DELTA_BOUNDS[2] < 0) DELTA_BOUNDS[2] <- 0
  if (diff(DELTA_BOUNDS) < 0.10) {
    mid <- mean(DELTA_BOUNDS)
    DELTA_BOUNDS <- mid + c(-1, 1) * 0.05
    DELTA_BOUNDS <- pmax(pmin(DELTA_BOUNDS, 0.40), -0.40)
  }
  TAU_BOUNDS <- as.numeric(TAU_BOUNDS)
  if (diff(TAU_BOUNDS) < 8) {
    mid <- mean(TAU_BOUNDS)
    TAU_BOUNDS <- mid + c(-1, 1) * 4
    TAU_BOUNDS <- pmax(pmin(TAU_BOUNDS, 20), -20)
  }

  list(
    TAU_BOUNDS = as.numeric(TAU_BOUNDS),
    DELTA_BOUNDS = as.numeric(DELTA_BOUNDS),
    WEEK_THRESHOLD_DELTA = as.numeric(WEEK_THRESHOLD_DELTA),
    LAMBDA_DELTA = as.numeric(LAMBDA_DELTA),
    tau_delta_hist = tau_delta_hist,
    delta_stability = delta_stability,
    stability_summary = stability_summary,
    curvature_Dpp = curv_by_season
  )
}
