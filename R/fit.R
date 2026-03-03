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




#' Internal: fit tau & delta for one season, given reference curve
#' @keywords internal
fit_tau_delta <- function(currentD, g_ref_fun,
                          tau_bounds, delta_bounds,
                          allow_scale = NULL,
                          week_threshold_delta,
                          lam_delta,
                          use_weights = TRUE) {
  # safe wrapper around the user-supplied g_ref_fun
  # (clamp to [1, 52] or whatever range your template is on)
  g_ref_safe <- function(u) g_ref_fun(pmin(pmax(u, 1), 52))
  
  t <- currentD$newWeek
  y <- currentD$y
  n <- currentD$y + currentD$neg
  w <- if (use_weights) n else rep(1, length(n))
  
  # if we haven’t seen far enough into the season, don’t try scale yet
  if (is.null(allow_scale)) allow_scale <- max(t, na.rm = TRUE) >= 28
  # only allow delta (dilation) once we’re past the stability threshold
  delta_on <- max(t, na.rm = TRUE) >= week_threshold_delta
  
  # ------- starting values at tau = 0, delta = 0 -------
  g0 <- g_ref_safe(t)
  ok <- is.finite(g0) & n > 0
  t0 <- t[ok]; y0 <- y[ok]; n0 <- n[ok]; w0 <- w[ok]; g0 <- g0[ok]
  
  if (allow_scale) {
    fit0 <- try(
      glm(cbind(y0, n0 - y0) ~ g0,
          family  = binomial(),
          weights = w0),
      silent = TRUE
    )
    if (inherits(fit0, "try-error")) {
      a0 <- qlogis(pmax(mean(y0 / n0), 1e-6))
      b0 <- 1
    } else {
      a0 <- unname(coef(fit0)[1])
      b0 <- unname(coef(fit0)[2])
    }
  } else {
    fit0 <- try(
      glm(cbind(y0, n0 - y0) ~ 1 + offset(g0),
          family  = binomial(),
          weights = w0),
      silent = TRUE
    )
    a0 <- if (inherits(fit0, "try-error")) {
      qlogis(pmax(mean(y0 / n0), 1e-6))
    } else {
      unname(coef(fit0)[1])
    }
    b0 <- 1
  }
  
  # clip starts into bounds
  tau0 <- median(c(0, tau_bounds[1] + 1e-3, tau_bounds[2] - 1e-3))
  del0 <- if (delta_on) median(c(0, delta_bounds[1] + 1e-4, delta_bounds[2] - 1e-4)) else 0
  a0   <- median(c(a0, -10, 10))
  b0   <- if (allow_scale) median(c(b0, 0.2, 5.0)) else 1
  
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
      gfun = g_ref_safe,        # <- use the closure around the argument
      allow_scale = allow_scale,
      lam  = lam_delta,
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


cov_tau_delta_from_profile <- function(fit, width_tau = 2.5, width_del = 0.15,
                                       m_tau = 31, m_del = 31) {
  tau0 <- fit$tau; del0 <- fit$delta
  tau_g <- seq(tau0 - width_tau, tau0 + width_tau, length.out = m_tau)
  del_g <- seq(del0 - width_del,   del0 + width_del,   length.out = m_del)
  grid  <- expand.grid(tau = tau_g, delta = del_g)

  fast_profile <- function(tau, delta) {
    t <- fit$t; y <- fit$y; n <- fit$n; w <- fit$w; gfun <- fit$g_ref_fun
    inner_fn <- function(par_ab) {
      if (fit$allow_scale) { a <- par_ab[1]; b <- par_ab[2] } else { a <- par_ab[1]; b <- 1 }
      u <- (t - tau) / (1 + delta)
      p <- plogis(a + b * gfun(u))
      -sum(w * dbinom(y, size = n, prob = p, log = TRUE) / pmax(n, 1))
    }
    o <- optim(c(fit$a, if (fit$allow_scale) fit$b else NULL), inner_fn,
               method = "Nelder-Mead", control = list(maxit = 200, reltol = 1e-6))
    o$value
  }

  nll_vals <- vapply(seq_len(nrow(grid)), function(i)
    fast_profile(grid$tau[i], grid$delta[i]), numeric(1))
  dev <- 2 * (nll_vals - min(nll_vals))

  x1 <- grid$tau   - tau0
  x2 <- grid$delta - del0
  qfit <- lm(dev ~ x1 + x2 + I(x1^2) + I(x2^2) + I(x1 * x2))
  cf <- coef(qfit)
  c11 <- cf["I(x1^2)"]; c22 <- cf["I(x2^2)"]; c12 <- cf["I(x1 * x2)"]
  H   <- matrix(c(2*c11, c12, c12, 2*c22), 2, 2)
  V   <- if (any(!is.finite(H)) || det(H) <= 1e-12) diag(NA_real_, 2) else solve(H)
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
