# M1 online alignment support is the fixed 1:52 template domain.  Evaluation
# outside this domain is unavailable; it is never clamped to an endpoint.
.page_alignment_admissible <- function(t, tau, delta, n_weeks = 52L) {
  u <- (as.numeric(t) - as.numeric(tau)) / (1 + as.numeric(delta))
  is.finite(u) & u >= 1 & u <= as.numeric(n_weeks)
}

.page_alignment_eval <- function(g_ref_fun, u, n_weeks = 52L) {
  u <- as.numeric(u)
  out <- rep(NA_real_, length(u))
  ok <- is.finite(u) & u >= 1 & u <= as.numeric(n_weeks)
  if (any(ok)) {
    values <- tryCatch(g_ref_fun(u[ok]), error = function(e) rep(NA_real_, sum(ok)))
    if (length(values) == 1L) values <- rep(values, sum(ok))
    out[ok] <- as.numeric(values)
  }
  out
}

# Fixed candidate-independent observation support for tau/delta alignment.
# Candidate objectives must be compared on one common row set.  The support is
# the intersection of template-admissible rows over the complete optimiser
# window, so no candidate can improve its score by discarding an inconvenient
# observation that another candidate retains.
.page_alignment_common_support <- function(t, n, tau_bounds, delta_bounds,
                                           n_weeks = 52L) {
  t <- as.numeric(t)
  n <- as.numeric(n)
  tau_bounds <- sort(as.numeric(tau_bounds)[1:2])
  delta_bounds <- sort(as.numeric(delta_bounds)[1:2])
  denom_lo <- 1 + delta_bounds[1L]
  denom_hi <- 1 + delta_bounds[2L]
  if (!is.finite(denom_lo) || denom_lo <= 0) denom_lo <- 1e-6
  if (!is.finite(denom_hi) || denom_hi <= 0) denom_hi <- 1e-6
  u_min <- (t - tau_bounds[2L]) / denom_hi
  u_max <- (t - tau_bounds[1L]) / denom_lo
  is.finite(t) & is.finite(n) & n > 0 &
    is.finite(u_min) & is.finite(u_max) &
    u_min >= 1 & u_max <= as.numeric(n_weeks)
}

#' Negative log-likelihood for tau/delta alignment
#'
#' Binomial negative log-likelihood for the time-alignment model
#' `logit(p) = a + b * g(u)` with `u = (t - tau) / (1 + delta)`,
#' with an optional ridge penalty on `delta`. Used as the objective inside
#' the nonlinear optimiser in [align_forecast_pipeline_dilate()].
#'
#' @param par Numeric vector of parameters. When `allow_scale = TRUE`:
#'   `c(tau, a, b, delta)`; otherwise `c(tau, a, delta)` with `b` fixed to 1.
#' @param t Numeric vector of observation times (`newWeek`).
#' @param y Integer vector of weekly positive counts.
#' @param n Integer vector of weekly total tests.
#' @param gfun Reference curve function on the logit scale.
#' @param allow_scale Logical; if `TRUE`, estimate slope `b`
#'   (default `TRUE`).
#' @param lam Ridge penalty on `delta^2` (default `0.1`).
#' @param w Numeric vector of per-observation weights
#'   (default `n`, i.e. weight by total tests).
#'
#' @return A numeric scalar; the penalised binomial negative log-likelihood.
negloglik_tau_delta <- function(par, t, y, n, gfun, allow_scale = TRUE,
                                lam = 0.1, w = n) {
  tau <- par[1]
  a <- par[2]
  if (allow_scale) {
    b <- par[3]
    del <- par[4]
  } else {
    b <- 1
    del <- par[3]
  }
  u <- (t - tau) / (1 + del)
  eta <- a + b * gfun(u)
  p <- plogis(eta)
  nll <- -sum(w * dbinom(y, size = n, prob = p, log = TRUE) / pmax(n, 1))
  nll + lam * del^2
}

#' Estimate tau and its profile standard error
#'
#' Fits the temporal alignment shift \code{tau} by 1-D golden-section
#' optimisation over profile log-likelihood (marginalising over the intercept
#' via GLM), then approximates the standard error of \code{tau_hat} from the
#' numerical second derivative of the profile \emph{deviance}.
#'
#' @param currentD Data frame for one season with columns \code{newWeek},
#'   \code{y} (positives), and \code{neg} (negatives).
#' @param g_ref Reference curve function on the logit scale,
#'   \code{g_ref(u) = logit(p_ref(u))}.
#' @param allow_scale Logical; if \code{TRUE} fits an intercept + slope
#'   (\code{a + b * g_ref}) rather than offset-only (default \code{FALSE}).
#' @param h Numeric step size for numerical second derivative (default
#'   \code{1e-3}).
#' @param tau0 Numeric starting value for the search interval centre
#'   (default 0).
#' @param tau_bounds Numeric vector of length 2; hard limits for \code{tau}
#'   (default \code{c(-12, 12)}).
#' @param support Optional logical vector selecting the saved common support
#'   rows. When supplied, every profile evaluation uses exactly these rows.
#' @param weights Optional likelihood weights, one per row of \code{currentD}.
#'   They are converted to the same per-observation GLM weights used by the
#'   alignment fit.
#'
#' @return A list with \code{tau_hat} (numeric) and \code{se_tau}
#'   (numeric, \code{NA} when the Hessian is non-positive).
#' @keywords internal
tau_profile_se <- function(currentD, g_ref, allow_scale = FALSE,
                           h = 1e-3, tau0 = 0, tau_bounds = c(-12, 12),
                           support = NULL, weights = NULL) {
  dat <- currentD |>
    dplyr::mutate(n = y + neg)
  n_rows <- nrow(dat)
  support <- support %||% .page_alignment_common_support(
    dat$newWeek, dat$n, tau_bounds, c(0, 0),
    n_weeks = 52L
  )
  if (length(support) != n_rows) {
    stop("Alignment profile support length does not match currentD.", call. = FALSE)
  }
  weights <- weights %||% dat$n
  if (length(weights) != n_rows) {
    stop("Alignment profile weights length does not match currentD.", call. = FALSE)
  }
  dat$.profile_support <- as.logical(support)
  dat$.profile_weight <- as.numeric(weights)
  dat <- dat |>
    dplyr::filter(.data$.profile_support, n > 0)
  t <- dat$newWeek
  y <- dat$y
  n <- dat$n
  # `fit_tau_delta()` uses w * logLik / n.  Convert its stored likelihood
  # weights to the equivalent GLM prior weights for cbind(y, n - y).
  w <- dat$.profile_weight / pmax(n, 1)

  nll_of_tau <- function(tau) {
    eta_shift <- g_ref(t - tau)
    if (length(eta_shift) != length(t) || any(!is.finite(eta_shift))) {
      return(.page_alignment_failure("profile_nonfinite_prediction"))
    }
    fit <- try(
      if (allow_scale) {
        glm(cbind(y, n - y) ~ eta_shift, family = binomial(), weights = w)
      } else {
        glm(cbind(y, n - y) ~ 1 + offset(eta_shift), family = binomial(), weights = w)
      },
      silent = TRUE
    )
    if (inherits(fit, "try-error")) {
      return(.page_alignment_failure("profile_glm_error"))
    }
    ll <- try(logLik(fit), silent = TRUE)
    if (inherits(ll, "try-error") || !is.finite(ll)) {
      return(.page_alignment_failure("profile_nonfinite_loglik"))
    }
    -as.numeric(ll)
  }

  tr <- c(max(tau0 - 8, tau_bounds[1]), min(tau0 + 8, tau_bounds[2]))
  opt <- optimize(nll_of_tau, interval = tr)
  tau_hat <- opt$minimum

  nll2 <- function(tau) 2 * nll_of_tau(tau)
  # The optimizer can finish arbitrarily close to a hard bound. Evaluate a
  # one-sided, unequal-step second difference in that case instead of stepping
  # outside the template domain and letting glm silently drop a support row.
  h_plus <- min(as.numeric(h), tau_bounds[2L] - tau_hat)
  h_minus <- min(as.numeric(h), tau_hat - tau_bounds[1L])
  Dpp <- if (is.finite(h_plus) && is.finite(h_minus) &&
    h_plus > 0 && h_minus > 0) {
    f0 <- nll2(tau_hat)
    f_plus <- nll2(tau_hat + h_plus)
    f_minus <- nll2(tau_hat - h_minus)
    if (all(is.finite(c(f0, f_plus, f_minus)))) {
      2 * (h_minus * f_plus + h_plus * f_minus -
        (h_minus + h_plus) * f0) / (h_plus * h_minus * (h_plus + h_minus))
    } else {
      NA_real_
    }
  } else {
    NA_real_
  }
  se_tau <- if (is.finite(Dpp) && Dpp > 0) sqrt(1 / Dpp) else NA_real_
  list(tau_hat = tau_hat, se_tau = se_tau)
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
                                  rise_weight = 3.0,
                                  peak_decay = 0.3,
                                  n_weeks = 52L) {
  # Find peak of the reference curve (probability scale)
  grid_u <- seq_len(n_weeks)
  g_vals <- g_ref_fun(grid_u)
  p_vals <- stats::plogis(g_vals)
  u_peak <- grid_u[which.max(p_vals)]
  p_peak <- max(p_vals)
  p_min <- min(p_vals)

  # Rising limb start: last week before peak where p is below 10% of peak
  # range above baseline.  This avoids false positives from cyclic wrap-around.
  p_thresh <- p_min + 0.10 * (p_peak - p_min)
  pre_peak <- grid_u[seq_len(u_peak)]
  below <- which(p_vals[pre_peak] < p_thresh)
  u_rise <- if (length(below) > 0) max(below) + 1L else 1L

  # Build weight vector
  w_t <- rep(1.0, length(t))
  # Pre-rising-limb trough
  w_t[t < u_rise] <- trough_weight
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
                          time_weights = NULL,
                          trough_weight = 0.1,
                          rise_weight = 1.0,
                          peak_decay = 0.3,
                          min_support = 4L) {
  min_support <- as.integer(min_support[1L])
  if (!is.finite(min_support) || min_support < 2L) {
    stop("`min_support` must be an integer of at least 2.", call. = FALSE)
  }

  t <- currentD$newWeek
  y <- currentD$y
  n <- currentD$y + currentD$neg

  # Sample-size weights

  w_n <- if (use_weights) n else rep(1, length(n))
  # Time-based weights (ignition-to-peak emphasis)
  w_t <- if (!is.null(time_weights)) {
    time_weights
  } else if (rise_weight > 1) {
    compute_align_weights(t, g_ref_fun, trough_weight, rise_weight, peak_decay)
  } else {
    rep(1, length(n))
  }
  w <- w_n * w_t
  # Binomial count responses already contribute N trials. Apply only the
  # remaining time weight (or 1/N for the equal-observation option).
  w_init <- w / pmax(n, 1)

  # if we haven't seen far enough into the season, don't try scale yet
  if (is.null(allow_scale)) allow_scale <- max(t, na.rm = TRUE) >= 28

  time_ok <- max(t, na.rm = TRUE) >= week_threshold_delta
  if (any(!is.finite(delta_bounds)) || delta_bounds[1L] <= -1) {
    stop("M1 dilation bounds must remain above -1.", call. = FALSE)
  }
  # Establish the support once, before any profile or curvature calculation.
  # Dilation is parameter 3 when `allow_scale = FALSE`; its window must not be
  # inferred from the length of the optimiser vector.
  support_delta_bounds <- if (time_ok) sort(as.numeric(delta_bounds)[1:2]) else c(0, 0)
  alignment_support <- .page_alignment_common_support(
    t, n, tau_bounds, support_delta_bounds, 52L
  )
  if (sum(alignment_support) < min_support) {
    stop("M1 alignment has insufficient common support in the optimizer window.",
      call. = FALSE
    )
  }

  # ------- Quick 1-D tau scan (profile over a, b at delta = 0) -------
  # Used to: (1) get good starting values for the full optimizer, and
  #          (2) evaluate the delta curvature at the right (tau-optimal) point.
  # The scan uses one fixed observation set for every tau so a shift cannot
  # appear better merely by dropping an inconvenient week.
  nll_tau_only <- function(tau_try) {
    u_t <- t - tau_try
    ok_t <- alignment_support & n > 0
    g_t <- .page_alignment_eval(g_ref_fun, u_t)
    if (sum(ok_t) < min_support || any(!is.finite(g_t[ok_t]))) {
      return(Inf)
    }
    fit_t <- if (allow_scale) {
      try(glm(cbind(y[ok_t], n[ok_t] - y[ok_t]) ~ g_t[ok_t],
        family = binomial(), weights = w_init[ok_t]
      ), silent = TRUE)
    } else {
      try(glm(cbind(y[ok_t], n[ok_t] - y[ok_t]) ~ 1 + offset(g_t[ok_t]),
        family = binomial(), weights = w_init[ok_t]
      ), silent = TRUE)
    }
    if (inherits(fit_t, "try-error")) {
      return(Inf)
    }
    ll <- try(logLik(fit_t), silent = TRUE)
    if (inherits(ll, "try-error") || !is.finite(ll)) {
      return(Inf)
    }
    -as.numeric(ll)
  }

  tau_opt <- tryCatch(
    optimize(nll_tau_only, interval = tau_bounds)$minimum,
    error = function(e) median(c(0, tau_bounds[1] + 1e-3, tau_bounds[2] - 1e-3))
  )
  tau_opt <- median(c(tau_opt, tau_bounds[1] + 1e-3, tau_bounds[2] - 1e-3))

  # GLM at tau_opt to get starting (a, b)
  g_opt <- .page_alignment_eval(g_ref_fun, t - tau_opt)
  ok_opt <- alignment_support & is.finite(g_opt) & n > 0
  if (sum(ok_opt) < min_support) {
    return(NULL)
  }
  if (allow_scale) {
    fit_opt <- try(
      glm(cbind(y[ok_opt], n[ok_opt] - y[ok_opt]) ~ g_opt[ok_opt],
        family = binomial(), weights = w_init[ok_opt]
      ),
      silent = TRUE
    )
    if (inherits(fit_opt, "try-error")) {
      a0 <- qlogis(pmax(mean(y[ok_opt] / n[ok_opt]), 1e-6))
      b0 <- 1
    } else {
      a0 <- unname(coef(fit_opt)[1])
      b0 <- unname(coef(fit_opt)[2])
    }
  } else {
    fit_opt <- try(
      glm(cbind(y[ok_opt], n[ok_opt] - y[ok_opt]) ~ 1 + offset(g_opt[ok_opt]),
        family = binomial(), weights = w_init[ok_opt]
      ),
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
  a0 <- median(c(a0, -10, 10))
  b0 <- if (allow_scale) median(c(b0, 0.2, 5.0)) else 1

  # lam_delta is now on the same per-observation scale as safe_obj():
  # learn_alignment_hyperparams() uses unweighted GLM for LAMBDA_DELTA calibration.
  lam_eff <- lam_delta

  # --- Delta gate: time threshold + data curvature check at tau-optimal point ---
  # Delta (dilation) and tau (shift) are confounded on the rising edge of the
  # curve. We only allow delta to vary when:
  #   (1) enough time has passed (existing time gate), AND
  #   (2) the data actually constrains delta -- d2NLL/ddelta2 at the tau-optimal
  #       point (unweighted) exceeds curvature_ratio x lam_eff. Both are now
  #       in the same per-observation scale. Computing at tau_opt is critical:
  #       at the wrong tau, the NLL surface is flat in delta regardless of
  #       how much data exists.
  delta_on <- FALSE
  if (time_ok) {
    # Unweighted GLM-profiled NLL (per-observation, same scale as lam_delta)
    nll_d_nw <- function(d) {
      u_d <- (t - tau0) / (1 + d)
      g_d <- .page_alignment_eval(g_ref_fun, u_d)
      ok_d <- alignment_support & n > 0
      if (sum(ok_d) < min_support || any(!is.finite(g_d[ok_d]))) {
        return(Inf)
      }
      fit_d <- try(
        glm(cbind(y[ok_d], n[ok_d] - y[ok_d]) ~ g_d[ok_d],
          family = binomial()
        ),
        silent = TRUE
      )
      if (inherits(fit_d, "try-error")) {
        return(Inf)
      }
      ll <- try(logLik(fit_d), silent = TRUE)
      if (inherits(ll, "try-error") || !is.finite(ll)) {
        return(Inf)
      }
      -as.numeric(ll)
    }
    h_d <- 0.01
    Dpp <- (nll_d_nw(h_d) - 2 * nll_d_nw(0) + nll_d_nw(-h_d)) / h_d^2
    delta_on <- is.finite(Dpp) && Dpp > curvature_ratio * lam_eff
  }

  del0 <- if (delta_on) median(c(0, delta_bounds[1] + 1e-4, delta_bounds[2] - 1e-4)) else 0

  if (allow_scale && delta_on) {
    x0 <- c(tau0, a0, b0, del0)
    lb <- c(tau_bounds[1], -10, 0.2, delta_bounds[1])
    ub <- c(tau_bounds[2], 10, 5.0, delta_bounds[2])
  } else if (allow_scale && !delta_on) {
    x0 <- c(tau0, a0, b0, 0)
    lb <- c(tau_bounds[1], -10, 0.2, 0)
    ub <- c(tau_bounds[2], 10, 5.0, 0)
  } else if (!allow_scale && delta_on) {
    x0 <- c(tau0, a0, del0)
    lb <- c(tau_bounds[1], -10, delta_bounds[1])
    ub <- c(tau_bounds[2], 10, delta_bounds[2])
  } else {
    x0 <- c(tau0, a0, 0)
    lb <- c(tau_bounds[1], -10, 0)
    ub <- c(tau_bounds[2], 10, 0)
  }

  obj <- function(par) {
    safe_obj(
      par,
      t = t,
      y = y,
      n = n,
      gfun = g_ref_fun,
      allow_scale = allow_scale,
      lam = lam_eff, # scale-corrected penalty (lam_delta / mean_n)
      w = w,
      min_support = min_support,
      support = alignment_support
    )
  }

  # make sure starting point is finite
  if (!is.finite(obj(x0))) {
    for (sc in c(0, 0.25, 0.5, 1)) {
      x_try <- x0
      x_try[1] <- median(c(
        x0[1] + sc,
        tau_bounds[1] + 1e-3,
        tau_bounds[2] - 1e-3
      ))
      if (is.finite(obj(x_try))) {
        x0 <- x_try
        break
      }
    }
  }
  if (!is.finite(obj(x0))) {
    stop("M1 alignment objective failed on the fixed common support.",
      call. = FALSE
    )
  }

  opt <- nloptr::sbplx(
    x0 = x0,
    fn = obj,
    lower = lb,
    upper = ub,
    control = list(xtol_rel = 1e-7, maxeval = 3000)
  )

  par <- opt$par
  tau_hat <- par[1]
  a_hat <- par[2]
  if (allow_scale) {
    b_hat <- par[3]
    del_hat <- par[4]
  } else {
    b_hat <- 1
    del_hat <- par[3]
  }

  predict_prob <- function(tt) {
    u <- (tt - tau_hat) / (1 + del_hat)
    g <- .page_alignment_eval(g_ref_fun, u)
    plogis(a_hat + b_hat * g)
  }
  # Do not retain an equivalent caller representation in the closure
  # environment; NULL and explicit unit weights must be an exact pass-through.
  time_weights <- NULL

  list(
    tau = tau_hat,
    a = a_hat,
    b = b_hat,
    delta = del_hat,
    allow_scale = allow_scale,
    delta_on = delta_on,
    value = opt$value,
    status = opt$convergence,
    min_support = min_support,
    support = alignment_support,
    support_delta_bounds = support_delta_bounds,
    n_admissible = sum(.page_alignment_admissible(t, tau_hat, del_hat, 52L) & n > 0),
    predict_prob = predict_prob,
    # store data for profiling t_peak, etc.
    t = t, y = y, n = n, w = w,
    g_ref_fun = g_ref_fun # for downstream if you need it
  )
}


#' Compute 2x2 profile-likelihood covariance for (tau, delta)
#'
#' Estimates the joint covariance matrix of the alignment parameters
#' \eqn{(\hat\tau, \hat\delta)} via a numerical 2x2 Hessian of the profile
#' NLL (marginalised over the intercept \code{a} and scale \code{b} using
#' Nelder-Mead at each grid point). Uses nine NLL evaluations via central
#' differences.
#'
#' @param fit List returned by \code{fit_tau_delta()} (or
#'   \code{fit_tau_delta_old()}). Must contain \code{tau}, \code{delta},
#'   \code{a}, \code{b}, \code{allow_scale}, \code{t}, \code{y}, \code{n},
#'   \code{w}, and \code{g_ref_fun}.
#' @param h_tau Numeric step size for the \code{tau} derivative (default
#'   0.1).
#' @param h_del Numeric step size for the \code{delta} derivative (default
#'   0.005).
#'
#' @return A list with \code{V} (2x2 covariance matrix, \code{NA}-filled when
#'   the Hessian is singular) and \code{center} (\code{c(tau_hat, delta_hat)}).
#' @keywords internal
cov_tau_delta_from_profile <- function(fit, h_tau = 0.1, h_del = 0.005) {
  tau0 <- fit$tau
  del0 <- fit$delta
  t <- fit$t
  y <- fit$y
  n <- fit$n
  w <- fit$w
  min_support <- fit$min_support %||% 4L
  support <- fit$support %||% rep(TRUE, length(t))
  if (length(support) != length(t)) {
    stop("Alignment profile support length does not match the fit.", call. = FALSE)
  }

  # Profile NLL at (tau, delta), marginalised over (a, b)
  profile_nll <- function(tau, delta) {
    u <- (t - tau) / (1 + delta)
    ok <- as.logical(support) & is.finite(t) & is.finite(n) & n > 0
    g <- .page_alignment_eval(fit$g_ref_fun, u)
    if (sum(ok) < min_support || any(!is.finite(g[ok]))) {
      return(Inf)
    }
    inner_fn <- function(par_ab) {
      a <- par_ab[1]
      b <- if (fit$allow_scale) par_ab[2] else 1
      p <- plogis(a + b * g[ok])
      -sum(w[ok] * dbinom(y[ok], size = n[ok], prob = p, log = TRUE) /
        pmax(n[ok], 1))
    }
    o <- tryCatch(
      optim(c(fit$a, if (fit$allow_scale) fit$b else NULL), inner_fn,
        method = "Nelder-Mead", control = list(maxit = 500, reltol = 1e-8)
      ),
      error = function(e) list(value = Inf)
    )
    if (!is.finite(o$value)) Inf else o$value
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
  H <- matrix(c(H11, H12, H12, H22), 2, 2)

  V <- if (any(!is.finite(H)) || det(H) <= 1e-12) diag(NA_real_, 2) else solve(H)
  list(V = V, center = c(tau0, del0))
}

#' Safe penalised NLL objective for tau/delta optimisation
#'
#' Evaluates the normalised negative binomial log-likelihood penalised by a
#' ridge term on \code{delta}. Failed candidates return an infinite value with
#' a `reason` attribute; callers must treat them as fit failures rather than as
#' a large finite score.
#'
#' @param par Numeric vector \code{c(tau, a, b, delta)} when
#'   \code{allow_scale = TRUE}, or \code{c(tau, a, delta)} otherwise.
#' @param t Numeric vector of \code{newWeek} values (observed data).
#' @param y Integer vector of positive-test counts.
#' @param n Integer vector of total-test counts.
#' @param gfun Reference curve function on the logit scale.
#' @param allow_scale Logical; whether the \code{b} scale parameter is
#'   included in \code{par}.
#' @param lam Numeric; ridge penalty coefficient on \code{delta}.
#' @param w Numeric vector of observation weights.
#'
#' @return A single numeric scalar; failed candidates are `Inf` with a
#'   diagnostic `reason` attribute.
#' @keywords internal
.page_alignment_failure <- function(reason) {
  structure(Inf, reason = as.character(reason)[1L])
}

safe_obj <- function(par, t, y, n, gfun, allow_scale, lam, w,
                     min_support = 4L, support = NULL) {
  out <- try(
    {
      tau <- par[1]
      a <- par[2]
      if (allow_scale) {
        b <- par[3]
        del <- par[4]
      } else {
        b <- 1
        del <- par[3]
      }
      if (is.null(support)) {
        support <- rep(TRUE, length(t))
      }
      support <- as.logical(support)
      if (length(support) != length(t)) {
        stop("Alignment support length does not match the observation vector.", call. = FALSE)
      }
      base <- support & is.finite(t) & is.finite(n)
      if (sum(base) < as.integer(min_support)) {
        return(.page_alignment_failure("insufficient_common_support"))
      }
      u <- (t - tau) / (1 + del)
      gmu <- .page_alignment_eval(gfun, u)
      # Candidates must share one observation set: a required row whose
      # reference value is unavailable fails the candidate instead of being
      # silently dropped.
      if (any(!is.finite(gmu[base]))) {
        return(.page_alignment_failure("reference_outside_common_support"))
      }
      eta <- a + b * gmu[base]
      p <- plogis(eta)
      eps <- 1e-12
      p <- pmin(pmax(p, eps), 1 - eps)
      n_eff <- pmax(n[base], 1)
      ll <- dbinom(y[base], size = n[base], prob = p, log = TRUE)
      if (any(!is.finite(ll))) {
        return(.page_alignment_failure("nonfinite_binomial_loglik"))
      }
      nll <- -sum(w[base] * ll / n_eff)
      if (!is.finite(nll)) {
        return(.page_alignment_failure("nonfinite_objective"))
      }
      nll + lam * del^2
    },
    silent = TRUE
  )
  if (inherits(out, "try-error")) {
    return(.page_alignment_failure("objective_error"))
  }
  if (!is.finite(out)) {
    return(.page_alignment_failure(attr(out, "reason") %||% "objective_failure"))
  }
  out
}
