#' @export
negloglik_tau_delta <- function(par, t, y, n, gfun, allow_scale = TRUE,
                                lam = 0.1, w = n) {
  tau <- par[1]; a <- par[2]
  if (allow_scale) { b <- par[3]; del <- par[4] } else { b <- 1; del <- par[3] }
  u   <- (t - tau) / (1 + del)
  eta <- a + b * gfun(u)
  p   <- plogis(eta)
  nll <- -sum(w * dbinom(y, size = n, prob = p, log = TRUE) / pmax(n, 1))
  nll + lam * del^2
}

tau_profile_se <- function(currentD, g_ref, allow_scale = FALSE,
                           h = 1e-3, tau0 = 0, tau_bounds = c(-12, 12)) {
  dat <- currentD %>% dplyr::mutate(n = y + neg) %>% dplyr::filter(n > 0)
  t <- dat$newWeek; y <- dat$y; n <- dat$n; w <- n

  nll_of_tau <- function(tau) {
    eta_shift <- g_ref(t - tau)
    fit <- try(
      if (allow_scale) {
        glm(cbind(y, n - y) ~ eta_shift, family = binomial(), weights = w)
      } else {
        glm(cbind(y, n - y) ~ 1 + offset(eta_shift), family = binomial(), weights = w)
      },
      silent = TRUE
    )
    if (inherits(fit, "try-error")) return(1e9)
    ll <- try(logLik(fit), silent = TRUE)
    if (inherits(ll, "try-error") || !is.finite(ll)) return(1e9)
    -as.numeric(ll)
  }

  tr <- c(max(tau0 - 8, tau_bounds[1]), min(tau0 + 8, tau_bounds[2]))
  opt <- optimize(nll_of_tau, interval = tr)
  tau_hat <- opt$minimum

  nll2 <- function(tau) 2 * nll_of_tau(tau)
  Dpp <- (nll2(tau_hat + h) - 2*nll2(tau_hat) + nll2(tau_hat - h)) / (h^2)
  se_tau <- if (is.finite(Dpp) && Dpp > 0) sqrt(1 / Dpp) else NA_real_
  list(tau_hat = tau_hat, se_tau = se_tau)
}

fit_tau_delta_old <- function(currentD, g_ref_fun,
                          tau_bounds, delta_bounds,
                          allow_scale = NULL,
                          week_threshold_delta,
                          lam_delta,
                          use_weights = TRUE) {

  t <- currentD$newWeek; y <- currentD$y; n <- currentD$y + currentD$neg
  w <- if (use_weights) n else rep(1, length(n))

  if (is.null(allow_scale)) allow_scale <- max(t, na.rm = TRUE) >= 28
  delta_on <- max(t, na.rm = TRUE) >= week_threshold_delta

  g0   <- g_ref_safe(t)
  ok   <- is.finite(g0) & n > 0
  t0   <- t[ok]; y0 <- y[ok]; n0 <- n[ok]; w0 <- w[ok]; g0 <- g0[ok]

  if (allow_scale) {
    fit0 <- try(glm(cbind(y0, n0 - y0) ~ g0, family = binomial(), weights = w0), silent = TRUE)
    if (inherits(fit0, "try-error")) { a0 <- qlogis(pmax(mean(y0/n0), 1e-6)); b0 <- 1 } else {
      a0 <- unname(coef(fit0)[1]); b0 <- unname(coef(fit0)[2])
    }
  } else {
    fit0 <- try(glm(cbind(y0, n0 - y0) ~ 1 + offset(g0), family = binomial(), weights = w0), silent = TRUE)
    a0 <- if (inherits(fit0, "try-error")) qlogis(pmax(mean(y0/n0), 1e-6)) else unname(coef(fit0)[1])
    b0 <- 1
  }

  tau0 <- median(c(0, tau_bounds[1] + 1e-3, tau_bounds[2] - 1e-3))
  del0 <- if (delta_on) median(c(0, delta_bounds[1] + 1e-4, delta_bounds[2] - 1e-4)) else 0
  a0   <- median(c(a0, -10, 10))
  b0   <- if (allow_scale) median(c(b0, 0.2, 5.0)) else 1

  if (allow_scale && delta_on) {
    x0 <- c(tau0, a0, b0, del0)
    lb <- c(tau_bounds[1], -10, 0.2, delta_bounds[1])
    ub <- c(tau_bounds[2],  10, 5.0,  delta_bounds[2])
  } else if (allow_scale && !delta_on) {
    x0 <- c(tau0, a0, b0, 0)
    lb <- c(tau_bounds[1], -10, 0.2, 0)
    ub <- c(tau_bounds[2],  10, 5.0,  0)
  } else if (!allow_scale && delta_on) {
    x0 <- c(tau0, a0, del0)
    lb <- c(tau_bounds[1], -10, delta_bounds[1])
    ub <- c(tau_bounds[2],  10, delta_bounds[2])
  } else {
    x0 <- c(tau0, a0, 0)
    lb <- c(tau_bounds[1], -10, 0)
    ub <- c(tau_bounds[2],  10, 0)
  }

  obj <- function(par) safe_obj(par, t, y, n, gfun = g_ref_safe,
                                allow_scale = allow_scale, lam = lam_delta, w = w)

  if (!is.finite(obj(x0))) {
    for (sc in c(0, 0.25, 0.5, 1)) {
      x_try <- x0
      x_try[1] <- median(c(x0[1] + sc, tau_bounds[1] + 1e-3, tau_bounds[2] - 1e-3))
      if (is.finite(obj(x_try))) { x0 <- x_try; break }
    }
  }

  opt <- nloptr::sbplx(x0 = x0, fn = obj, lower = lb, upper = ub,
                       control = list(xtol_rel = 1e-7, maxeval = 3000))

  par <- opt$par
  tau_hat <- par[1]; a_hat <- par[2]
  if (allow_scale) { b_hat <- par[3]; del_hat <- par[4] } else { b_hat <- 1; del_hat <- par[3] }

  predict_prob <- function(tt) {
    u <- (tt - tau_hat) / (1 + del_hat)
    plogis(a_hat + b_hat * g_ref_safe(u))
  }

  list(
    tau = tau_hat, a = a_hat, b = b_hat, delta = del_hat,
    allow_scale = allow_scale, delta_on = delta_on,
    value = opt$value, status = opt$convergence,
    predict_prob = predict_prob,
    t = t, y = y, n = n, w = w, g_ref_fun = g_ref_safe
  )
}




#' Compute ignition-to-peak time weights for alignment loss
#'
#' Creates per-observation weights that emphasise the rising limb (ignition to
#' peak) of the reference curve.  Pre-peak trough weeks receive a low weight,
#' the ignition-to-peak region receives a boosted weight, and weeks after the
#' peak decay exponentially back toward 1.
#'
#' @param t Numeric vector of newWeek values (observed data).
#' @param g_ref_fun Reference curve function on logit scale.
#' @param trough_weight Weight for pre-rising-limb weeks (default 0.1).
#' @param rise_weight Weight for ignition-through-peak weeks (default 3.0).
#' @param peak_decay Exponential decay rate after peak (default 0.3).
#' @param n_weeks Integer; template domain length (default 52).
#' @return Numeric vector of time weights, same length as \code{t}.
#' @keywords internal
compute_align_weights <- function(t,
                                  g_ref_fun,
                                  trough_weight = 0.1,
                                  rise_weight   = 3.0,
                                  peak_decay    = 0.3,
                                  n_weeks       = 52L) {
  # Find peak of the reference curve (probability scale)
  grid_u   <- seq_len(n_weeks)
  g_vals   <- g_ref_fun(grid_u)
  p_vals   <- stats::plogis(g_vals)
  u_peak   <- grid_u[which.max(p_vals)]
  p_peak   <- max(p_vals)
  p_min    <- min(p_vals)

  # Rising limb start: last week before peak where p is below 10% of peak
  # range above baseline.  This avoids false positives from cyclic wrap-around.
  p_thresh <- p_min + 0.10 * (p_peak - p_min)
  pre_peak <- grid_u[seq_len(u_peak)]
  below    <- which(p_vals[pre_peak] < p_thresh)
  u_rise   <- if (length(below) > 0) max(below) + 1L else 1L

  # Build weight vector
  w_t <- rep(1.0, length(t))
  # Pre-rising-limb trough
  w_t[t < u_rise]                <- trough_weight
  # Ignition-to-peak boost
  w_t[t >= u_rise & t <= u_peak] <- rise_weight
  # Post-peak exponential decay back toward 1
  past <- t > u_peak
  w_t[past] <- 1 + (rise_weight - 1) * exp(-peak_decay * (t[past] - u_peak))

  w_t
}


#' Internal: fit tau & delta for one season, given reference curve
#' @keywords internal
fit_tau_delta <- function(currentD, g_ref_fun,
                          tau_bounds, delta_bounds,
                          allow_scale = NULL,
                          week_threshold_delta,
                          lam_delta,
                          use_weights = TRUE,
                          curvature_ratio = 1.0,
                          time_weights  = NULL,
                          trough_weight = 0.1,
                          rise_weight   = 1.0,
                          peak_decay    = 0.3) {
  # safe wrapper around the user-supplied g_ref_fun
  # (clamp to [1, 52] or whatever range your template is on)
  g_ref_safe <- function(u) g_ref_fun(pmin(pmax(u, 1), 52))

  t <- currentD$newWeek
  y <- currentD$y
  n <- currentD$y + currentD$neg

  # Sample-size weights

  w_n <- if (use_weights) n else rep(1, length(n))
  # Time-based weights (ignition-to-peak emphasis)
  w_t <- if (!is.null(time_weights)) {
    time_weights
  } else if (rise_weight > 1) {
    compute_align_weights(t, g_ref_safe, trough_weight, rise_weight, peak_decay)
  } else {
    rep(1, length(n))
  }
  w <- w_n * w_t

  # if we haven’t seen far enough into the season, don’t try scale yet
  if (is.null(allow_scale)) allow_scale <- max(t, na.rm = TRUE) >= 28

  # ------- Quick 1-D tau scan (profile over a, b at delta = 0) -------
  # Used to: (1) get good starting values for the full optimizer, and
  #          (2) evaluate the delta curvature at the right (tau-optimal) point.
  nll_tau_only <- function(tau_try) {
    g_t <- g_ref_safe(t - tau_try)
    ok_t <- is.finite(g_t) & n > 0
    if (sum(ok_t) < 2) return(1e9)
    fit_t <- if (allow_scale) {
      try(glm(cbind(y[ok_t], n[ok_t] - y[ok_t]) ~ g_t[ok_t],
              family = binomial(), weights = w[ok_t]), silent = TRUE)
    } else {
      try(glm(cbind(y[ok_t], n[ok_t] - y[ok_t]) ~ 1 + offset(g_t[ok_t]),
              family = binomial(), weights = w[ok_t]), silent = TRUE)
    }
    if (inherits(fit_t, "try-error")) return(1e9)
    ll <- try(logLik(fit_t), silent = TRUE)
    if (inherits(ll, "try-error") || !is.finite(ll)) return(1e9)
    -as.numeric(ll)
  }

  tau_opt <- tryCatch(
    optimize(nll_tau_only, interval = tau_bounds)$minimum,
    error = function(e) median(c(0, tau_bounds[1] + 1e-3, tau_bounds[2] - 1e-3))
  )
  tau_opt <- median(c(tau_opt, tau_bounds[1] + 1e-3, tau_bounds[2] - 1e-3))

  # GLM at tau_opt to get starting (a, b)
  g_opt <- g_ref_safe(t - tau_opt)
  ok_opt <- is.finite(g_opt) & n > 0
  if (allow_scale) {
    fit_opt <- try(
      glm(cbind(y[ok_opt], n[ok_opt] - y[ok_opt]) ~ g_opt[ok_opt],
          family = binomial(), weights = w[ok_opt]),
      silent = TRUE
    )
    if (inherits(fit_opt, "try-error")) {
      a0 <- qlogis(pmax(mean(y[ok_opt] / n[ok_opt]), 1e-6)); b0 <- 1
    } else {
      a0 <- unname(coef(fit_opt)[1]); b0 <- unname(coef(fit_opt)[2])
    }
  } else {
    fit_opt <- try(
      glm(cbind(y[ok_opt], n[ok_opt] - y[ok_opt]) ~ 1 + offset(g_opt[ok_opt]),
          family = binomial(), weights = w[ok_opt]),
      silent = TRUE
    )
    a0 <- if (inherits(fit_opt, "try-error")) {
      qlogis(pmax(mean(y[ok_opt] / n[ok_opt]), 1e-6))
    } else {
      unname(coef(fit_opt)[1])
    }
    b0 <- 1
  }

  tau0 <- tau_opt
  a0   <- median(c(a0, -10, 10))
  b0   <- if (allow_scale) median(c(b0, 0.2, 5.0)) else 1

  # lam_delta is now on the same per-observation scale as safe_obj():
  # learn_alignment_hyperparams() uses unweighted GLM for LAMBDA_DELTA calibration.
  lam_eff <- lam_delta

  # --- Delta gate: time threshold + data curvature check at tau-optimal point ---
  # Delta (dilation) and tau (shift) are confounded on the rising edge of the
  # curve. We only allow delta to vary when:
  #   (1) enough time has passed (existing time gate), AND
  #   (2) the data actually constrains delta — d²NLL/dδ² at the tau-optimal
  #       point (unweighted) exceeds curvature_ratio × lam_eff. Both are now
  #       in the same per-observation scale. Computing at tau_opt is critical:
  #       at the wrong tau, the NLL surface is flat in delta regardless of
  #       how much data exists.
  time_ok  <- max(t, na.rm = TRUE) >= week_threshold_delta
  delta_on <- FALSE
  if (time_ok) {
    # Unweighted GLM-profiled NLL (per-observation, same scale as lam_delta)
    nll_d_nw <- function(d) {
      u_d  <- (t - tau0) / (1 + d)
      g_d  <- g_ref_safe(u_d)
      ok_d <- is.finite(g_d) & n > 0
      if (sum(ok_d) < 2) return(1e9)
      fit_d <- try(
        glm(cbind(y[ok_d], n[ok_d] - y[ok_d]) ~ g_d[ok_d],
            family = binomial()),
        silent = TRUE
      )
      if (inherits(fit_d, "try-error")) return(1e9)
      ll <- try(logLik(fit_d), silent = TRUE)
      if (inherits(ll, "try-error") || !is.finite(ll)) return(1e9)
      -as.numeric(ll)
    }
    h_d  <- 0.01
    Dpp  <- (nll_d_nw(h_d) - 2 * nll_d_nw(0) + nll_d_nw(-h_d)) / h_d^2
    delta_on <- is.finite(Dpp) && Dpp > curvature_ratio * lam_eff
  }

  del0 <- if (delta_on) median(c(0, delta_bounds[1] + 1e-4, delta_bounds[2] - 1e-4)) else 0
  
  if (allow_scale && delta_on) {
    x0 <- c(tau0, a0, b0, del0)
    lb <- c(tau_bounds[1], -10, 0.2,  delta_bounds[1])
    ub <- c(tau_bounds[2],  10, 5.0,  delta_bounds[2])
  } else if (allow_scale && !delta_on) {
    x0 <- c(tau0, a0, b0, 0)
    lb <- c(tau_bounds[1], -10, 0.2, 0)
    ub <- c(tau_bounds[2],  10, 5.0, 0)
  } else if (!allow_scale && delta_on) {
    x0 <- c(tau0, a0, del0)
    lb <- c(tau_bounds[1], -10, delta_bounds[1])
    ub <- c(tau_bounds[2],  10, delta_bounds[2])
  } else {
    x0 <- c(tau0, a0, 0)
    lb <- c(tau_bounds[1], -10, 0)
    ub <- c(tau_bounds[2],  10, 0)
  }
  
  obj <- function(par) {
    safe_obj(
      par,
      t   = t,
      y   = y,
      n   = n,
      gfun = g_ref_safe,
      allow_scale = allow_scale,
      lam  = lam_eff,     # scale-corrected penalty (lam_delta / mean_n)
      w    = w
    )
  }
  
  # make sure starting point is finite
  if (!is.finite(obj(x0))) {
    for (sc in c(0, 0.25, 0.5, 1)) {
      x_try <- x0
      x_try[1] <- median(c(x0[1] + sc,
                           tau_bounds[1] + 1e-3,
                           tau_bounds[2] - 1e-3))
      if (is.finite(obj(x_try))) {
        x0 <- x_try
        break
      }
    }
  }
  
  opt <- nloptr::sbplx(
    x0     = x0,
    fn     = obj,
    lower  = lb,
    upper  = ub,
    control = list(xtol_rel = 1e-7, maxeval = 3000)
  )
  
  par <- opt$par
  tau_hat <- par[1]
  a_hat   <- par[2]
  if (allow_scale) {
    b_hat   <- par[3]
    del_hat <- par[4]
  } else {
    b_hat   <- 1
    del_hat <- par[3]
  }
  
  predict_prob <- function(tt) {
    u <- (tt - tau_hat) / (1 + del_hat)
    plogis(a_hat + b_hat * g_ref_safe(u))
  }
  
  list(
    tau   = tau_hat,
    a     = a_hat,
    b     = b_hat,
    delta = del_hat,
    allow_scale = allow_scale,
    delta_on    = delta_on,
    value  = opt$value,
    status = opt$convergence,
    predict_prob = predict_prob,
    # store data for profiling t_peak, etc.
    t = t, y = y, n = n, w = w,
    g_ref_fun = g_ref_fun  # for downstream if you need it
  )
}


cov_tau_delta_from_profile <- function(fit, h_tau = 0.1, h_del = 0.005) {
  tau0 <- fit$tau; del0 <- fit$delta
  t <- fit$t; y <- fit$y; n <- fit$n; w <- fit$w
  gfun <- function(u) fit$g_ref_fun(pmin(pmax(u, 1), 52))

  # Profile NLL at (tau, delta), marginalised over (a, b)
  profile_nll <- function(tau, delta) {
    inner_fn <- function(par_ab) {
      a <- par_ab[1]
      b <- if (fit$allow_scale) par_ab[2] else 1
      u <- (t - tau) / (1 + delta)
      p <- plogis(a + b * gfun(u))
      -sum(w * dbinom(y, size = n, prob = p, log = TRUE) / pmax(n, 1))
    }
    o <- tryCatch(
      optim(c(fit$a, if (fit$allow_scale) fit$b else NULL), inner_fn,
            method = "Nelder-Mead", control = list(maxit = 500, reltol = 1e-8)),
      error = function(e) list(value = 1e9)
    )
    o$value
  }

  # 2x2 numerical Hessian via central differences (9 NLL evaluations)
  nll00 <- profile_nll(tau0, del0)
  nll_pp <- profile_nll(tau0 + h_tau, del0 + h_del)
  nll_pm <- profile_nll(tau0 + h_tau, del0 - h_del)
  nll_mp <- profile_nll(tau0 - h_tau, del0 + h_del)
  nll_mm <- profile_nll(tau0 - h_tau, del0 - h_del)
  nll_p0 <- profile_nll(tau0 + h_tau, del0)
  nll_m0 <- profile_nll(tau0 - h_tau, del0)
  nll_0p <- profile_nll(tau0, del0 + h_del)
  nll_0m <- profile_nll(tau0, del0 - h_del)

  H11 <- (nll_p0 - 2 * nll00 + nll_m0) / h_tau^2
  H22 <- (nll_0p - 2 * nll00 + nll_0m) / h_del^2
  H12 <- (nll_pp - nll_pm - nll_mp + nll_mm) / (4 * h_tau * h_del)
  H   <- matrix(c(H11, H12, H12, H22), 2, 2)

  V <- if (any(!is.finite(H)) || det(H) <= 1e-12) diag(NA_real_, 2) else solve(H)
  list(V = V, center = c(tau0, del0))
}

safe_obj <- function(par, t, y, n, gfun, allow_scale, lam, w) {
  out <- try({
    tau <- par[1]; a <- par[2]
    if (allow_scale) { b <- par[3]; del <- par[4] } else { b <- 1; del <- par[3] }
    u   <- (t - tau) / (1 + del)
    gmu <- gfun(u)
    if (any(!is.finite(gmu))) return(1e9)
    eta <- a + b * gmu
    p   <- plogis(eta)
    eps <- 1e-12
    p   <- pmin(pmax(p, eps), 1 - eps)
    n_eff <- pmax(n, 1)
    ll    <- dbinom(y, size = n, prob = p, log = TRUE)
    if (any(!is.finite(ll))) return(1e9)
    nll <- -sum(w * ll / n_eff)
    if (!is.finite(nll)) return(1e9)
    nll + lam * del^2
  }, silent = TRUE)
  if (inherits(out, "try-error") || !is.finite(out)) 1e9 else out
}
