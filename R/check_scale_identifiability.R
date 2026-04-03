#' Check if scaling (b) is identifiable yet, with a more sensitive rule
#'
#' @param currentD data frame with newWeek, y, neg.
#' @param g_ref_fun reference spline on link scale.
#' @param hyper list from learn_alignment_hyperparams().
#' @param min_week do not allow scaling before this epi week in newWeek space.
#' @param g_range_thresh minimum range of g(u) (on link scale) to trust scaling.
#' @param p_range_thresh minimum range of crude positivity to trust scaling.
#'
#' @return list with allow_scale_rec (TRUE/FALSE) and diagnostics.
#' @export
check_scale_identifiability <- function(currentD,
                                        g_ref_fun,
                                        hyper,
                                        min_week       = 20,
                                        g_range_thresh = 0.25,
                                        p_range_thresh = 0.05) {
  # --- basic data ---
  t <- currentD$newWeek
  y <- currentD$y
  n <- currentD$y + currentD$neg
  
  last_newWeek <- max(t, na.rm = TRUE)
  
  # 0) hard gate: too early in the season
  if (!is.finite(last_newWeek) || last_newWeek < min_week) {
    return(list(
      allow_scale_rec = FALSE,
      reason          = "too_early",
      last_newWeek    = last_newWeek,
      min_week        = min_week
    ))
  }
  
  # safe wrapper around g_ref_fun
  g_ref_safe <- function(u) g_ref_fun(pmin(pmax(u, 1), 52))
  
  # 1) get τ-hat from a τ-only fit (delta fixed at 0, no scaling)
  tb  <- hyper$TAU_BOUNDS
  db0 <- c(0, 0)  # force delta = 0
  
  fit_tau_only <- fit_tau_delta(
    currentD      = currentD,
    g_ref_fun     = g_ref_fun,
    tau_bounds    = tb,
    delta_bounds  = db0,
    allow_scale   = FALSE,
    week_threshold_delta = Inf,  # never turn delta on in this helper fit
    lam_delta     = hyper$LAMBDA_DELTA,
    use_weights   = TRUE
  )
  
  tau_hat <- fit_tau_only$tau
  
  # 2) aligned u and template range on link scale
  u_aligned <- (t - tau_hat) / (1 + 0)
  g_vals    <- g_ref_safe(u_aligned)
  range_g   <- diff(range(g_vals, na.rm = TRUE))
  
  # 3) crude observed positivity range as additional signal
  p_obs   <- y / pmax(n, 1)
  range_p <- diff(range(p_obs, na.rm = TRUE))
  
  # --- NEW, more sensitive rule ---
  # Allow scaling if:
  #   - we are past min_week, AND
  #   - EITHER g_range is moderately large OR p_range is moderately large
  allow_scale_rec <- (range_g >= g_range_thresh) || (range_p >= p_range_thresh)
  
  list(
    allow_scale_rec = allow_scale_rec,
    reason          = if (allow_scale_rec) "variation_sufficient" else "variation_too_small",
    last_newWeek    = last_newWeek,
    min_week        = min_week,
    tau_hat         = tau_hat,
    range_g         = range_g,
    g_range_thresh  = g_range_thresh,
    range_p         = range_p,
    p_range_thresh  = p_range_thresh
  )
}
