#' @export
check_scale_identifiability_old <- function(currentD,
                                        g_ref_fun,   # you pass g_ref_fun; we use g_ref_safe inside
                                        hyper,
                                        min_week    = 20,   # don't turn on scale too early
                                        min_range_p = 0.10, # 10 percentage-points variation in p_obs
                                        min_range_g = 0.50  # 0.5 on logit scale for template
) {
  # Use the same "safe" reference you already use elsewhere
  g_ref_safe <- function(u) g_ref_fun(pmin(pmax(u, 1), 52))
  
  dat <- currentD %>%
    dplyr::mutate(n = y + neg) %>%
    dplyr::filter(n > 0)
  
  t <- dat$newWeek
  y <- dat$y
  n <- dat$n
  
  # 1) observed positivity variation
  p_obs   <- y / n
  range_p <- diff(range(p_obs, na.rm = TRUE))
  last_wk <- max(t, na.rm = TRUE)
  
  # 2) τ-only alignment to get tau_hat (δ = 0, b = 1)
  tp <- tau_profile_se(
    currentD   = dat,
    g_ref      = g_ref_safe,
    allow_scale = FALSE,
    tau0       = 0,
    tau_bounds = hyper$TAU_BOUNDS
  )
  tau_hat <- tp$tau_hat
  
  # 3) template variation over aligned weeks
  u_aligned <- (t - tau_hat)          # delta = 0
  g_vals    <- g_ref_safe(u_aligned)
  range_g   <- diff(range(g_vals, na.rm = TRUE))
  
  # 4) rule-of-thumb decision
  allow_scale_rec <- (last_wk >= min_week) &&
    (range_p  > min_range_p) &&
    (range_g  > min_range_g)
  
  tibble::tibble(
    last_week        = last_wk,
    tau_hat          = tau_hat,
    range_p_obs      = range_p,
    range_g_template = range_g,
    allow_scale_rec  = allow_scale_rec
  )
}
