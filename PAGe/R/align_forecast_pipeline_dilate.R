#' Align and forecast using dilated reference curve
#'
#' @param currentD tibble/data.frame with at least newWeek, y, neg.
#' @param g_ref_fun spline-like reference function on link scale.
#' @param g_ref_mu_se function(u) returning list(mu, se) from GAM.
#' @param hyper list with TAU_BOUNDS, DELTA_BOUNDS, WEEK_THRESHOLD_DELTA, LAMBDA_DELTA.
#' @param allow_scale logical or NULL; passed to fit_tau_delta().
#' @param use_weights logical; use y + neg as binomial weights.
#' @param level CI level.
#' @param future_weeks optional vector of future newWeek values; if NULL,
#'   uses (last_obs + 1):52.
#' @param include_observed logical; whether to include observed part in pred_df.
#' @param fallback_when_unstable logical; if TRUE, refit with delta=0 when
#'   2D tau/delta profile covariance is unstable.
#' @param curvature_ratio Numeric; gate coefficient for delta activation.
#' @param time_weights Numeric vector or NULL; pre-computed time weights.
#'   If NULL and \code{rise_weight > 1}, weights are computed from the reference
#'   curve via \code{compute_align_weights()}.
#' @param trough_weight Numeric; weight for pre-rising-limb weeks (default 0.1).
#' @param rise_weight Numeric; weight for ignition-to-peak weeks (default 1.0,
#'   i.e. no boost by default).
#' @param peak_decay Numeric; exponential decay rate after peak (default 0.3).
#'
#' @return list with tau, delta, a, b, pred_df, peak, nll, etc.
#' @export
align_forecast_pipeline_dilate <- function(currentD,
                                           g_ref_fun,
                                           g_ref_mu_se,
                                           hyper,
                                           allow_scale = NULL,
                                           use_weights = TRUE,
                                           level = 0.95,
                                           future_weeks = NULL,
                                           include_observed = TRUE,
                                           fallback_when_unstable = TRUE,
                                           curvature_ratio = 1.0,
                                           time_weights  = NULL,
                                           trough_weight = 0.1,
                                           rise_weight   = 1.0,
                                           peak_decay    = 0.3) {
  tb  <- hyper$TAU_BOUNDS
  db  <- hyper$DELTA_BOUNDS
  wk  <- hyper$WEEK_THRESHOLD_DELTA
  lam <- hyper$LAMBDA_DELTA
  
  # local safe wrapper around the passed-in g_ref_fun
  g_ref_safe <- function(u) g_ref_fun(pmin(pmax(u, 1), 52))
  
  # 1) Align (τ, δ, a, b)
  fit <- fit_tau_delta(
    currentD      = currentD,
    g_ref_fun     = g_ref_fun,
    tau_bounds    = tb,
    delta_bounds  = db,
    allow_scale   = allow_scale,
    week_threshold_delta = wk,
    lam_delta     = lam,
    use_weights   = use_weights,
    curvature_ratio = curvature_ratio,
    time_weights  = time_weights,
    trough_weight = trough_weight,
    rise_weight   = rise_weight,
    peak_decay    = peak_decay
  )

  # 2) (a,b) at aligned (τ,δ)
  t <- currentD$newWeek
  y <- currentD$y
  n <- currentD$y + currentD$neg
  # Compute same combined weights used in fit_tau_delta for GLM consistency
  w_n <- if (use_weights) n else rep(1, length(n))
  w_t <- if (!is.null(time_weights)) {
    time_weights
  } else if (rise_weight > 1) {
    compute_align_weights(t, g_ref_safe, trough_weight, rise_weight, peak_decay)
  } else {
    rep(1, length(n))
  }
  w <- w_n * w_t
  
  u_hat  <- (t - fit$tau) / (1 + fit$delta)
  eta_of <- g_ref_safe(u_hat)
  
  if (fit$allow_scale) {
    glm_hat <- glm(
      cbind(y, n - y) ~ eta_of,
      family  = binomial(),
      weights = w
    )
    V_ab  <- vcov(glm_hat)
    a_hat <- coef(glm_hat)[1]
    b_hat <- coef(glm_hat)[2]
  } else {
    glm_hat <- glm(
      cbind(y, n - y) ~ 1 + offset(eta_of),
      family  = binomial(),
      weights = w
    )
    V_ab  <- matrix(vcov(glm_hat)[1, 1], 1, 1)
    a_hat <- coef(glm_hat)[1]
    b_hat <- 1
  }
  
  # 3) (τ,δ) covariance via 2D profile if δ is on
  prof2d <- if (fit$delta_on) cov_tau_delta_from_profile(fit) else list(V = diag(c(NA, NA), 2))
  V_td   <- prof2d$V
  cov_ok <- fit$delta_on && is_cov_ok(V_td)
  
  # Fallback if δ unstable
  fb_reason <- NA_character_
  if (fallback_when_unstable && fit$delta_on && !cov_ok) {
    fit <- fit_tau_delta(
      currentD      = currentD,
      g_ref_fun     = g_ref_fun,
      tau_bounds    = tb,
      delta_bounds  = c(0, 0),      # force delta = 0
      allow_scale   = fit$allow_scale,
      week_threshold_delta = 1e9,   # never turn delta on
      lam_delta     = lam,
      use_weights   = use_weights,
      time_weights  = time_weights,
      trough_weight = trough_weight,
      rise_weight   = rise_weight,
      peak_decay    = peak_decay
    )
    u_hat  <- (t - fit$tau) / (1 + fit$delta)
    eta_of <- g_ref_safe(u_hat)
    
    if (fit$allow_scale) {
      glm_hat <- glm(
        cbind(y, n - y) ~ eta_of,
        family  = binomial(),
        weights = w
      )
      V_ab  <- vcov(glm_hat)
      a_hat <- coef(glm_hat)[1]
      b_hat <- coef(glm_hat)[2]
    } else {
      glm_hat <- glm(
        cbind(y, n - y) ~ 1 + offset(eta_of),
        family  = binomial(),
        weights = w
      )
      V_ab  <- matrix(vcov(glm_hat)[1, 1], 1, 1)
      a_hat <- coef(glm_hat)[1]
      b_hat <- 1
    }
    V_td      <- NULL
    cov_ok    <- FALSE
    fb_reason <- "delta_unstable_profile"
  }
  
  # 4) Predictions + PIs
  last_obs <- max(t)
  if (is.null(future_weeks)) {
    future_weeks <- if (last_obs < 52) (last_obs + 1):52 else integer(0)
  }
  z <- qnorm((1 + level) / 2)
  
  make_block <- function(tt, kind, n_future = NULL, add_sampling_future = FALSE) {
    if (length(tt) == 0) return(tibble::tibble())
    
    u   <- (tt - fit$tau) / (1 + fit$delta)
    g_mu <- g_ref_safe(u)
    eta  <- a_hat + b_hat * g_mu
    p    <- plogis(eta)
    
    # (1) Var from (a,b) (quasi-binomial)
    if (fit$allow_scale) {
      Xab <- cbind(1, g_mu)
      Vab <- V_ab
    } else {
      Xab <- matrix(1, nrow = length(tt), ncol = 1)
      Vab <- matrix(V_ab[1, 1], 1, 1)
    }
    phi_hat <- tryCatch(
      glm_hat$deviance / max(1, glm_hat$df.residual),
      error = function(e) 1
    )
    var_eta_ab <- phi_hat * rowSums((Xab %*% Vab) * Xab)
    
    # (2) alignment variance (τ,δ), or τ-only fallback
    var_eta_align <- 0
    if (!is.null(V_td) && is_cov_ok(V_td)) {
      gprime <- num_deriv(u, g_ref_safe)
      d_eta_d_tau <- -b_hat * gprime / (1 + fit$delta)
      d_eta_d_del <- -b_hat * gprime * (tt - fit$tau) / (1 + fit$delta)^2
      G <- cbind(d_eta_d_tau, d_eta_d_del)
      var_eta_align <- rowSums((G %*% V_td) * G)
    } else {
      tp <- tau_profile_se(
        currentD,
        g_ref       = g_ref_safe,
        allow_scale = fit$allow_scale,
        tau0        = fit$tau,
        tau_bounds  = tb
      )
      if (is.finite(tp$se_tau)) {
        gprime <- num_deriv(u, g_ref_safe)
        d_eta_d_tau <- -b_hat * gprime / (1 + fit$delta)
        var_eta_align <- (d_eta_d_tau^2) * (tp$se_tau^2)
      }
    }
    
    # (3) template uncertainty from GAM
    g_se <- g_ref_mu_se(u)$se
    var_eta_template <- (b_hat^2) * (g_se^2)
    
    se_eta <- sqrt(pmax(0, var_eta_ab + var_eta_align + var_eta_template))
    
    p_lo <- plogis(eta - z * se_eta)
    p_hi <- plogis(eta + z * se_eta)
    
    tibble::tibble(
      newWeek = tt,
      p_hat   = p,
      p_lo    = p_lo,
      p_hi    = p_hi,
      kind    = kind
    )
  }
  
  # Observed with Wilson CIs
  pred_obs <- if (include_observed) {
    ci <- wilson_ci(y, n, level = level)
    tibble::tibble(
      newWeek = t,
      p_hat   = y / n,
      p_lo    = ci[, "lo"],
      p_hi    = ci[, "hi"],
      kind    = "observed"
    )
  } else {
    tibble::tibble()
  }
  
  pred_fut <- make_block(future_weeks, "forecast")
  
  peak <- peak_summary_from_fit(
    fit_obj   = list(tau = fit$tau, delta = fit$delta, a = a_hat, b = b_hat),
    g_ref_fun = g_ref_safe,
    V_ab      = V_ab,
    V_td      = if (!is.null(V_td) && is_cov_ok(V_td)) V_td else diag(NA_real_, 2),
    level     = level
  )
  
  # Fallback peak CI with τ-only profile if needed
  if (any(is.na(peak$t_peak_ci))) {
    tp <- tau_profile_se(
      currentD,
      g_ref       = g_ref_safe,
      allow_scale = fit$allow_scale,
      tau0        = fit$tau,
      tau_bounds  = tb
    )
    if (is.finite(tp$se_tau)) {
      z <- qnorm((1 + level) / 2)
      peak$t_peak_ci <- peak$t_peak + c(-1, 1) * z * tp$se_tau
    }
  }
  
  list(
    tau             = fit$tau,
    delta           = fit$delta,
    a               = a_hat,
    b               = b_hat,
    allow_scale     = fit$allow_scale,
    delta_on        = fit$delta_on,
    nll             = fit$value,
    pred_df         = dplyr::bind_rows(pred_obs, pred_fut) %>%
      dplyr::arrange(newWeek),
    last_obs        = last_obs,
    V_ab            = V_ab,
    V_td            = V_td,
    peak            = peak,
    fallback_reason = fb_reason
  )
}
