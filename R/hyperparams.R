#' @export
# Learn tau/delta ranges and penalties from historical seasons
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

  nll_tau_delta <- function(t, y, n, tau, delta) {
    u <- (t - tau) / (1 + delta)
    g <- g_ref_safe(u)
    fit <- glm(cbind(y, n - y) ~ g, family = binomial(), weights = n)
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

  stability_summary <- delta_stability %>%
    dplyr::group_by(week_cut) %>%
    dplyr::summarise(sd_delta = stats::sd(delta_hat, na.rm = TRUE), .groups = "drop") %>%
    dplyr::mutate(rel_sd = sd_delta / max(sd_delta, na.rm = TRUE))

  WEEK_THRESHOLD_DELTA <- stability_summary %>%
    dplyr::filter(rel_sd <= rel_sd_target) %>%
    dplyr::summarise(w = if (dplyr::n() == 0) NA_real_ else min(week_cut)) %>%
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
