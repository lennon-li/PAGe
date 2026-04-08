# Prospective training utilities
# - Prospective-safe feature construction for training (no future leakage)
# - Stage-2 modular model specification (turn terms on/off)
# - Stage-2 tuning and training

`%||%` <- function(x, y) if (!is.null(x)) x else y

# =========================================================
# Core utilities
# =========================================================

#' Numerically stable logit (internal)
#' @keywords internal
logit_stable <- function(p, eps = 1e-6) {
  p <- pmin(pmax(p, eps), 1 - eps)
  stats::qlogis(p)
}

#' Build a soft positivity cap function from a fitted Stage-2 GAM
#'
#' Extracts the training-data positivity distribution from a fitted mgcv GAM
#' and returns a tanh-based soft ceiling function consistent with the deployment
#' cap applied in \code{run_m2_forecast()}.
#'
#' @param fit_obj A fitted mgcv GAM with a binomial response matrix as \code{model[[1]]}.
#' @return A function \code{f(p)} mapping predicted probabilities through the soft cap.
#' @export
make_soft_cap_fn <- function(fit_obj) {
  p_train  <- fit_obj$model[[1]][, 1L] / rowSums(fit_obj$model[[1]])
  p_knee   <- as.numeric(stats::quantile(p_train, 0.95, na.rm = TRUE))
  p_max_tr <- max(p_train, na.rm = TRUE)
  p_ceil   <- min(p_max_tr + 0.5 * (p_max_tr - p_knee), 1.0)
  function(p) {
    above    <- p > p_knee
    p[above] <- p_knee + (p_ceil - p_knee) *
      tanh((p[above] - p_knee) / (p_ceil - p_knee))
    p
  }
}

#' Predict M2 positivity from a fitted Stage-2 GAM (single row)
#'
#' Shared prediction core used by all M2 code paths: LOSO frozen evaluation,
#' LOSO weekly-refit evaluation, and prospective deployment. By centralising
#' the newdata construction, factor-level alignment, season-RE handling,
#' soft-cap application, and CI logic in one place, we guarantee that
#' training-evaluation-deployment are fully consistent.
#'
#' @param fit A fitted \code{mgcv::bam}/\code{gam} object.
#' @param ew Integer. Current evaluation week (weekF).
#' @param h Integer. Forecast horizon (1 or 2).
#' @param iWeek Integer. Locked ignition week.
#' @param anchorWeek Integer. Reference-curve anchor week.
#' @param logit_f_eff Numeric. logit(M1 predicted positivity at target week).
#' @param z_ema Numeric. EWMA of logit-observed positivity.
#' @param logN_now Numeric. log(N) at eval week.
#' @param d1_now Numeric. First derivative (logit scale) at eval week.
#' @param d2_now Numeric. Second derivative (logit scale) at eval week.
#' @param season_label Character. Season label for newdata: the test/current
#'   season name (used when the season is in the model's training data,
#'   i.e. weekly-refit mode), or \code{NULL} to fall back to the first
#'   historical level (frozen mode).
#' @param ex_terms Character vector. Terms to exclude from \code{predict()}
#'   (e.g. exclude_newseason terms). Should NOT include \code{"s(season)"}
#'   when the season is in the refit training data.
#' @param include_season_re Logical. If \code{TRUE}, the season random effect
#'   is included in the prediction (weekly-refit mode). If \code{FALSE},
#'   \code{"s(season)"} is appended to \code{ex_terms} (frozen mode).
#' @param soft_cap_fn Optional soft-cap function from \code{make_soft_cap_fn()}.
#' @param return_ci Logical. If \code{TRUE}, returns \code{m2_lo} and
#'   \code{m2_hi} (±1.96 SE on the link scale).
#'
#' @return A named list with \code{m2_p} (and \code{m2_lo}, \code{m2_hi}
#'   if \code{return_ci = TRUE}), or \code{NULL} on prediction failure.
#' @export
m2_predict_one <- function(fit,
                           ew,
                           h,
                           iWeek,
                           anchorWeek,
                           logit_f_eff,
                           z_ema,
                           logN_now,
                           d1_now,
                           d2_now,
                           season_label    = NULL,
                           ex_terms        = NULL,
                           include_season_re = FALSE,
                           soft_cap_fn     = NULL,
                           return_ci       = FALSE,
                           bias_logit      = 0) {

  # --- Exclude terms ---
  ex <- ex_terms %||% character(0)
  if (!isTRUE(include_season_re)) {
    ex <- unique(c(ex, "s(season)"))
  }

  # --- Factor levels from fitted model ---
  lev_lead <- levels(fit$model$lead)
  lev_seas <- levels(fit$model$season)

  lead_val <- paste0("h", h)
  if (!lead_val %in% lev_lead) return(NULL)

  # Season factor: use season_label if it's a valid level (refit mode),

  # otherwise fall back to first historical level (frozen mode).
  if (!is.null(season_label) && season_label %in% lev_seas) {
    nd_season <- factor(season_label, levels = lev_seas)
  } else {
    nd_season <- factor(lev_seas[1L], levels = lev_seas)
  }

  nd <- tibble::tibble(
    weekF       = as.integer(ew),
    newWeek     = as.integer(ew) - as.integer(iWeek) + as.integer(anchorWeek),
    lead        = factor(lead_val, levels = lev_lead),
    season      = nd_season,
    logit_f_eff = as.numeric(logit_f_eff),
    z_ema       = as.numeric(z_ema),
    z_resid     = as.numeric(z_ema) - as.numeric(logit_f_eff),
    logN_now    = as.numeric(logN_now),
    d1_now      = as.numeric(d1_now),
    d2_now      = as.numeric(d2_now),
    t_since     = as.numeric(ew - iWeek),
    post_ign    = TRUE
  )

  # season_h (factor-smooth interaction term) — use matching level if present
  if ("season_h" %in% names(fit$model)) {
    lev_sh <- levels(fit$model$season_h)
    sh_val <- paste0(as.character(nd_season), ":h", h)
    if (sh_val %in% lev_sh) {
      nd$season_h <- factor(sh_val, levels = lev_sh)
    } else {
      nd$season_h <- factor(lev_sh[1L], levels = lev_sh)
    }
  }

  # --- Predict ---
  pr <- tryCatch(
    stats::predict(fit, newdata = nd, type = "link",
                   se.fit = return_ci, exclude = ex),
    error = function(e) NULL
  )
  if (is.null(pr)) return(NULL)

  # --- Transform to probability scale ---
  cap <- soft_cap_fn %||% identity
  eps <- 1e-12
  bl  <- as.numeric(bias_logit %||% 0)

  if (isTRUE(return_ci)) {
    eta <- as.numeric(pr$fit) + bl
    se  <- as.numeric(pr$se.fit)
    list(
      m2_p  = cap(pmin(1 - eps, pmax(eps, stats::plogis(eta)))),
      m2_lo = cap(pmin(1 - eps, pmax(eps, stats::plogis(eta - 1.96 * se)))),
      m2_hi = cap(pmin(1 - eps, pmax(eps, stats::plogis(eta + 1.96 * se))))
    )
  } else {
    eta <- as.numeric(pr) + bl
    list(
      m2_p = cap(pmin(1 - eps, pmax(eps, stats::plogis(eta))))
    )
  }
}


#' Stage-2 ramp weights (internal)
#' @keywords internal
stage2_ramp_weight <- function(t_since, K = 3L) {
  # K controls ramp length. Convention:
  # - K <= 1 : no ramp (template weight is 1 from ignition onward)
  # - K >  1 : linear ramp from 0 at ignition to 1 after K weeks
  K <- as.integer(K[1])
  if (is.na(K) || K < 1L) stop("K must be >= 1")
  
  t_since <- as.numeric(t_since)
  
  if (K <= 1L) {
    return(ifelse(t_since >= 0, 1, 0))
  }
  
  w <- t_since / K
  pmin(1, pmax(0, w))
}

#' Prospective (real-time safe) derivatives of positivity on the logit scale
#' @export
add_prospective_derivs_link <- function(alignedD,
                                        k = 5L,
                                        eps = 1e-6,
                                        min_obs = 4L) {
  stopifnot(all(c("season","weekF","y","neg") %in% names(alignedD)))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("purrr", quietly = TRUE)) stop("Please install purrr.")
  
  d <- alignedD %>%
    dplyr::mutate(
      y_w = .data$y / (.data$y + .data$neg),
      z_w = stats::qlogis(pmin(pmax(.data$y_w, eps), 1 - eps))
    ) %>%
    dplyr::arrange(.data$season, .data$weekF)
  
  d %>%
    dplyr::group_by(.data$season) %>%
    dplyr::group_modify(function(.x, .g) {
      ww <- .x$weekF
      zz <- .x$z_w
      n  <- nrow(.x)
      
      d1 <- purrr::map_dbl(seq_len(n), function(i) {
        i0 <- max(1L, i - k + 1L)
        ii <- i0:i
        if (length(ii) < min_obs || anyNA(zz[ii])) return(NA_real_)
        w0 <- ww[i]
        u  <- ww[ii] - w0
        fit <- stats::lm(zz[ii] ~ u + I(u^2))
        unname(stats::coef(fit)[["u"]])
      })
      
      d2 <- purrr::map_dbl(seq_len(n), function(i) {
        i0 <- max(1L, i - k + 1L)
        ii <- i0:i
        if (length(ii) < min_obs || anyNA(zz[ii])) return(NA_real_)
        w0 <- ww[i]
        u  <- ww[ii] - w0
        fit <- stats::lm(zz[ii] ~ u + I(u^2))
        2 * unname(stats::coef(fit)[["I(u^2)"]])
      })
      
      dplyr::mutate(.x, d1_link = d1, d2_link = d2)
    }) %>%
    dplyr::ungroup()
}

# =========================================================
# Stage-2 prep
# =========================================================

#' Prepare Stage-2 joint stacked data using a spec or tuned row
#'
#' @param dat Multi-season data.frame with required cols:
#'   season, weekF, phase, newWeek, y, N, d1_link, d2_link.
#' @param template_df Template curve with columns newWeek and fit.
#' @param best_mean_nll 1-row object with delta, K, k_f, alpha_state.
#' @param use_ramp Logical, passed through.
#' @param leads Integer leads.
#' @param ign_week_df Optional data.frame with season and iWeek_hat.
#' @param pre_buffer Integer.
#' @param alpha_state Numeric in (0,1).
#' @param verbose Logical.
#'
#' @return data.frame stacked across leads with engineered covariates.
#' @export
prep_stage2_joint <- function(dat,
                              best_mean_nll,
                              template_df,
                              use_ramp = TRUE,
                              leads = c(1L, 2L),
                              ign_week_df = NULL,
                              pre_buffer = 0L,
                              alpha_state = 0.30,
                              m1_preds = NULL,
                              verbose = FALSE) {
  stopifnot(is.data.frame(dat))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  
  if (is.null(template_df) || !is.data.frame(template_df)) stop("template_df must be provided.")
  if (!all(c("newWeek","fit") %in% names(template_df))) stop("template_df must have columns newWeek, fit")
  template_df <- template_df %>% dplyr::select(.data$newWeek, fit_ref = .data$fit)
  
  need <- c("season","weekF","phase","newWeek","y","N","d1_link","d2_link")
  miss <- setdiff(need, names(dat))
  if (length(miss)) stop("prep_stage2_joint: missing cols: ", paste(miss, collapse = ", "))
  
  pre_buffer <- as.integer(pre_buffer)
  if (is.na(pre_buffer) || pre_buffer < 0L) stop("pre_buffer must be >= 0")
  
  alpha_state <- as.numeric(alpha_state)
  if (!is.finite(alpha_state) || alpha_state <= 0 || alpha_state >= 1) stop("alpha_state must be in (0,1).")
  
  get1 <- function(obj, nm, default = NULL) {
    if (is.list(obj) && !is.data.frame(obj) && !is.null(obj[[nm]])) return(obj[[nm]])
    if (is.data.frame(obj) && nm %in% names(obj)) return(obj[[nm]][1])
    default
  }
  
  delta <- get1(best_mean_nll, "delta", 0L)
  delta <- as.integer(delta)
  K <- get1(best_mean_nll, "Kr", NULL) %||% get1(best_mean_nll, "K", 3L)
  K <- if (is.na(K)) NA_integer_ else as.integer(K)
  
  # template can be disabled by delta=NA or K=NA
  template_on <- is.finite(delta) && !is.na(delta) && is.finite(K) && !is.na(K)
  
  leads <- as.integer(leads)
  
  # ---- ignition from phase==1 (fallback) ----
  ign_true <- dat %>%
    dplyr::group_by(.data$season) %>%
    dplyr::summarise(
      iWeek_true = suppressWarnings(min(.data$weekF[.data$phase == 1L], na.rm = TRUE)),
      .groups = "drop"
    )
  
  d0 <- dat %>%
    dplyr::left_join(ign_true, by = "season")
  
  # ---- optional override ignition week used ----
  if (!is.null(ign_week_df)) {
    stopifnot(all(c("season","iWeek_hat") %in% names(ign_week_df)))
    ign_week_df <- ign_week_df %>%
      dplyr::transmute(season = as.character(.data$season), iWeek_used = as.numeric(.data$iWeek_hat))
    
    d0 <- d0 %>%
      dplyr::mutate(season = as.character(.data$season)) %>%
      dplyr::left_join(ign_week_df, by = "season") %>%
      dplyr::mutate(iWeek_used = dplyr::coalesce(.data$iWeek_used, .data$iWeek_true))
  } else {
    d0 <- d0 %>% dplyr::mutate(iWeek_used = .data$iWeek_true)
  }
  
  # ---- core covariates ----
  d0 <- d0 %>%
    dplyr::filter(is.finite(.data$iWeek_used)) %>%
    dplyr::arrange(.data$season, .data$weekF) %>%
    dplyr::group_by(.data$season) %>%
    dplyr::mutate(
      post_ign  = (.data$weekF >= (.data$iWeek_used - pre_buffer)),
      logN_now  = log(pmax(.data$N, 1L)),
      p_now     = .data$y / pmax(.data$N, 1L),
      z_now     = logit_stable(.data$p_now),
      z0        = dplyr::coalesce(dplyr::first(.data$z_now[is.finite(.data$z_now)]), 0),
      z_fill    = dplyr::coalesce(.data$z_now, .data$z0),
      z_ema     = as.numeric(stats::filter(alpha_state * .data$z_fill,
                                           filter = 1 - alpha_state,
                                           method = "recursive",
                                           init = .data$z_fill[1])),
      d1_now    = .data$d1_link,
      d2_now    = .data$d2_link,
      t_since   = as.numeric(.data$weekF - .data$iWeek_used)
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(-.data$z0, -.data$z_fill) %>%
    dplyr::left_join(template_df, by = "newWeek")
  
  # ---- shift template by delta ----
  if (!is.na(delta) && delta != 0L) {
    n <- abs(delta)
    if (delta > 0L) {
      d0 <- d0 %>%
        dplyr::group_by(.data$season) %>%
        dplyr::mutate(fit_shift = dplyr::lead(.data$fit_ref, n = n)) %>%
        dplyr::ungroup()
    } else {
      d0 <- d0 %>%
        dplyr::group_by(.data$season) %>%
        dplyr::mutate(fit_shift = dplyr::lag(.data$fit_ref, n = n)) %>%
        dplyr::ungroup()
    }
  } else {
    d0 <- d0 %>% dplyr::mutate(fit_shift = .data$fit_ref)
  }
  
  # ---- template covariate ----
  K_eff <- if (isTRUE(use_ramp)) as.integer(K) else 1L
  
  # ---- template covariate ----
  d0 <- d0 %>%
    dplyr::mutate(
      # K controls ramping; convention:
      # - K <= 1: no ramp (omega=1 from ignition onward)
      # - K >  1: linear ramp from 0 at ignition to 1 after K weeks
      omega = if (isTRUE(template_on)) stage2_ramp_weight(.data$t_since, K = K_eff) else 0,
      logit_f = if (isTRUE(template_on)) logit_stable(.data$fit_shift) else 0,
      logit_f_eff = .data$omega * .data$logit_f,
      z_resid = .data$z_ema - .data$logit_f_eff
    ) %>%
    dplyr::filter(is.finite(.data$z_ema), is.finite(.data$logN_now))
  
  out <- lapply(leads, function(h) {
    d0 %>%
      dplyr::group_by(.data$season) %>%
      dplyr::mutate(
        y_lead = dplyr::lead(.data$y, n = h),
        N_lead = dplyr::lead(.data$N, n = h)
      ) %>%
      dplyr::ungroup() %>%
      dplyr::mutate(
        lead = factor(paste0("h", h), levels = paste0("h", sort(unique(leads))))
      ) %>%
      dplyr::filter(!is.na(.data$y_lead), !is.na(.data$N_lead), .data$N_lead > 0)
  })
  
  d <- dplyr::bind_rows(out) %>%
    dplyr::mutate(
      season = factor(.data$season),
      y_lead = as.integer(.data$y_lead),
      N_lead = as.integer(.data$N_lead),
      season_h = interaction(.data$season, .data$lead, drop = TRUE)
    )

  # ---- Override logit_f_eff with M1 walk-forward predictions ----
  # When m1_preds is supplied (output of m1_walkforward_predictions()),
  # replace the static template feature with M1's aligned prediction.
  # M1 provides p_hat at each (season, eval_weekF, h) — this is the
  # stacking architecture: M1 = base model, M2 = meta-learner.
  if (!is.null(m1_preds)) {
    stopifnot(is.data.frame(m1_preds))
    stopifnot(all(c("season", "eval_weekF", "h", "m1_p_hat") %in% names(m1_preds)))

    # Extract h integer from lead factor (e.g., "h1" → 1, "h2" → 2)
    d$.h_int <- as.integer(sub("^h", "", as.character(d$lead)))

    m1_join <- m1_preds %>%
      dplyr::transmute(
        season      = as.character(.data$season),
        weekF       = as.integer(.data$eval_weekF),
        .h_int      = as.integer(.data$h),
        .m1_p_hat   = as.numeric(.data$m1_p_hat)
      )

    d <- d %>%
      dplyr::mutate(season_chr = as.character(.data$season)) %>%
      dplyr::left_join(m1_join, by = c("season_chr" = "season",
                                        "weekF" = "weekF",
                                        ".h_int" = ".h_int")) %>%
      dplyr::mutate(
        logit_f_eff = dplyr::if_else(
          is.finite(.data$.m1_p_hat) & !is.na(.data$.m1_p_hat),
          logit_stable(.data$.m1_p_hat),
          .data$logit_f_eff  # fallback to static template if M1 missing
        ),
        z_resid = .data$z_ema - .data$logit_f_eff
      ) %>%
      dplyr::select(-dplyr::all_of(c("season_chr", ".h_int", ".m1_p_hat")))

    if (isTRUE(verbose)) {
      message("[prep_stage2_joint] M1 stacking mode: logit_f_eff replaced with M1 predictions")
    }
  }
  
  if (isTRUE(verbose)) {
    message("[prep_stage2_joint] delta=", delta, " K=", K,
            " pre_buffer=", pre_buffer,
            " use_ramp=", use_ramp,
            " alpha_state=", signif(alpha_state, 3),
            " leads={", paste(leads, collapse=","), "} rows=", nrow(d))
  }
  
  as.data.frame(d)
}

# =========================================================
# Stage-2 training
# =========================================================

# internal: score with optional exclude terms
# lambda_w: time-decay weight rate (0 = uniform). Weights w_i = exp(-lambda_w * t_since_i),
#   normalised to sum to n so that mean_nll is on the same scale regardless of lambda_w.
# eval_window: if non-NULL, restrict evaluation to rows where t_since <= eval_window.
#   This provides a *fixed* objective for comparing different lambda_w values fairly
#   (all lambdas are assessed on the same early-window observations).
score_stage2_metrics <- function(fit,
                                 d_test,
                                 exclude_season_re = TRUE,
                                 exclude_terms = NULL,
                                 lambda_w = 0,
                                 eval_window = NULL,
                                 soft_cap_fn = NULL) {
  ex <- exclude_terms
  if (is.null(ex)) ex <- if (isTRUE(exclude_season_re)) "s(season)" else NULL

  nd <- d_test

  # lead levels
  if ("lead" %in% names(nd) && "lead" %in% names(fit$model) && is.factor(fit$model$lead)) {
    lev <- levels(fit$model$lead)
    nd$lead <- factor(as.character(nd$lead), levels = lev)
    nd$lead[is.na(nd$lead)] <- lev[1]
  }

  # season levels
  if ("season" %in% names(nd) && "season" %in% names(fit$model) && is.factor(fit$model$season)) {
    lev <- levels(fit$model$season)
    nd$season <- factor(as.character(nd$season), levels = lev)
    nd$season[is.na(nd$season)] <- lev[1]
  }

  # season_h levels (lead-specific season factor for fs term)
  if ("season_h" %in% names(nd) && "season_h" %in% names(fit$model) && is.factor(fit$model$season_h)) {
    lev <- levels(fit$model$season_h)
    nd$season_h <- factor(as.character(nd$season_h), levels = lev)
    nd$season_h[is.na(nd$season_h)] <- lev[1]
  }


  p_hat <- as.numeric(stats::predict(fit, newdata = nd, type = "response", exclude = ex))
  if (!is.null(soft_cap_fn)) p_hat <- soft_cap_fn(p_hat)
  eps <- 1e-12
  p_hat <- pmin(1 - eps, pmax(eps, p_hat))

  ll <- stats::dbinom(nd$y_lead, size = nd$N_lead, prob = p_hat, log = TRUE)

  # restrict to early window for evaluation (fixed objective across lambda_w values)
  eval_mask <- rep(TRUE, length(ll))
  if (!is.null(eval_window) && "t_since" %in% names(nd)) {
    eval_mask <- is.finite(nd$t_since) & nd$t_since <= eval_window
  }
  ll_eval   <- ll[eval_mask]
  nd_eval   <- nd[eval_mask, , drop = FALSE]
  p_hat_eval <- p_hat[eval_mask]

  # time-decay weights on the eval set, normalised so mean_nll is interpretable
  if (lambda_w > 0 && "t_since" %in% names(nd_eval) && any(eval_mask)) {
    raw_w <- exp(-lambda_w * as.numeric(nd_eval$t_since))
    raw_w[!is.finite(raw_w)] <- 0
    w <- raw_w / mean(raw_w[raw_w > 0], na.rm = TRUE)  # normalise so mean(w)=1
  } else {
    w <- rep(1, sum(eval_mask))
  }

  nll      <- -sum(w * ll_eval, na.rm = TRUE)
  mean_nll <- nll / max(sum(eval_mask), 1L)

  p_obs_eval <- nd_eval$y_lead / nd_eval$N_lead
  brier   <- stats::weighted.mean((p_hat_eval - p_obs_eval)^2, w = w, na.rm = TRUE)
  rmse_p  <- sqrt(brier)

  list(nll = nll, mean_nll = mean_nll, brier = brier, rmse_p = rmse_p)
}

# internal
train_stage2_joint_prepped <- function(d_all,
                                       best_mean_nll,
                                       template_df = NULL,
                                       spec = NULL,
                                       # Back-compat (only used when spec is NULL)
                                       k_e = 6L,
                                       k_n = 6L,
                                       k_1 = 6L,
                                       k_2 = 6L,
                                       method = "REML",
                                       lambda_w = 0,
                                       w_floor  = 0,
                                       verbose = FALSE) {
  if (!requireNamespace("mgcv", quietly = TRUE)) stop("Please install mgcv.")
  stopifnot(is.data.frame(d_all))
  
  get1 <- function(obj, nm, default = NULL) {
    if (is.list(obj) && !is.data.frame(obj) && !is.null(obj[[nm]])) return(obj[[nm]])
    if (is.data.frame(obj) && nm %in% names(obj)) return(obj[[nm]][1])
    default
  }
  k_f <- as.integer(get1(best_mean_nll, "k_f", 6L))
  
  # DEFAULT: parsimonious model unless user supplies spec
  if (is.null(spec)) {
    spec <- stage2_make_spec(
      delta = get1(best_mean_nll, "delta", 0L),
      K = get1(best_mean_nll, "K", 3L),
      k_f = k_f,
      alpha_state = get1(best_mean_nll, "alpha_state", 0.30),
      template_mode = "smooth",
      k_w = 0L,
      k_s = 0L,
      k_e = as.integer(k_e),
      k_n = 0L,
      k_1 = 0L,
      k_2 = 0L,
      use_season_re = TRUE
    )
  }
  
  d_train <- d_all[d_all$post_ign, , drop = FALSE]
  if (nrow(d_train) == 0L) stop("train_stage2_joint_prepped: no post-ignition rows.")

  # time-decay training weights: w_i = exp(-lambda_w * t_since_i), normalised.
  # w_floor applies only for t_since > t_floor_start (default 14), leaving the
  # pre-peak window governed purely by exponential decay.
  # Stored as a column in d_train (.w) so mgcv::bam can find it via data-frame eval.
  t_floor_start <- as.numeric(spec$t_floor_start %||% 14)
  if (lambda_w > 0 && "t_since" %in% names(d_train)) {
    t_s   <- as.numeric(d_train$t_since)
    raw_w <- exp(-lambda_w * t_s)
    if (w_floor > 0) raw_w <- ifelse(t_s > t_floor_start, pmax(raw_w, w_floor), raw_w)
    raw_w[!is.finite(raw_w)] <- w_floor
    mn <- mean(raw_w[raw_w > 0], na.rm = TRUE)
    d_train$.w <- if (is.finite(mn) && mn > 0) raw_w / mn else rep(1, nrow(d_train))
    use_weights <- TRUE
  } else {
    use_weights <- FALSE
  }

  req <- c("post_ign","lead","y_lead","N_lead")
  if (spec$template_mode != "none") req <- c(req, "logit_f_eff")
  if (spec$k_w > 0L || spec$k_s > 0L) req <- c(req, "newWeek")
  if (spec$use_season_re) req <- c(req, "season")
  if (spec$k_s > 0L) req <- c(req, "season_h")
  if (spec$k_e > 0L) req <- c(req, "z_ema")
  if (!is.null(spec$k_r) && spec$k_r > 0L) req <- c(req, "z_resid")
  if (spec$k_n > 0L) req <- c(req, "logN_now")
  if (spec$k_1   > 0L) req <- c(req, "d1_now")
  if (spec$k_2   > 0L) req <- c(req, "d2_now")
  
  miss <- setdiff(unique(req), names(d_train))
  if (length(miss)) stop("train_stage2_joint_prepped: missing cols: ", paste(miss, collapse = ", "))
  
  form <- stage2_build_joint_formula(spec)
  
  if (isTRUE(verbose)) {
    message("[train_stage2_joint_prepped] rows=", nrow(d_train),
            " | template_mode=", spec$template_mode,
            " | k_f=", k_f,
            " | k_w=", spec$k_w,
            " | k_s=", spec$k_s,
            " | k_2=", spec$k_2)
    message("[train_stage2_joint_prepped] formula: ", deparse(form))
  }
  
  # NOTE: mgcv's discrete=TRUE path can be fragile with factor-smooth interactions (bs='fs').
  # If the fs term is enabled (k_s>0), fall back to discrete=FALSE for stability.
  use_discrete <- isTRUE(spec$k_s <= 0L)
  fit_method <- if (isTRUE(use_discrete) && identical(method, "REML")) "fREML" else method
  
  # Pass weights via column in d_train to avoid mgcv NSE scoping issue
  if (isTRUE(use_weights)) {
    fit <- mgcv::bam(
      formula  = form,
      data     = d_train,
      family   = stats::binomial(),
      weights  = .w,
      method   = fit_method,
      discrete = use_discrete,
      nthreads = 1,
      control  = mgcv::gam.control(maxit = 500)
    )
  } else {
    fit <- mgcv::bam(
      formula  = form,
      data     = d_train,
      family   = stats::binomial(),
      method   = fit_method,
      discrete = use_discrete,
      nthreads = 1,
      control  = mgcv::gam.control(maxit = 500)
    )
  }

  list(fit = fit, train_data = d_train, tuned = best_mean_nll, spec = spec,
       lambda_w = lambda_w)
}

#' Extract best Stage-2 spec from a tuning result
#'
#' Convenience wrapper: given the list returned by
#' \code{tune_stage2_loso_spec_grid_parallel()}, finds the best row in
#' \code{tuned2$by_spec_grid} and calls \code{stage2_make_spec()} with the
#' appropriate column mappings (\code{Kr} -> \code{K}, \code{Kb} ->
#' \code{pre_buffer}).
#'
#' @param tuned2 List with at least \code{$best} (1-row data frame with
#'   \code{spec_id}) and \code{$by_spec_grid} (full grid with hyperparameters).
#' @return A spec list as returned by \code{stage2_make_spec()}.
#' @export
stage2_spec_from_tuning <- function(tuned2) {
  stopifnot(is.list(tuned2), !is.null(tuned2$best), !is.null(tuned2$by_spec_grid))
  best_id  <- tuned2$best$spec_id[[1L]]
  best_row <- tuned2$by_spec_grid[tuned2$by_spec_grid$spec_id == best_id, , drop = FALSE]
  if (nrow(best_row) == 0L) stop("spec_id '", best_id, "' not found in by_spec_grid")
  stage2_make_spec(
    delta          = best_row$delta,
    K              = best_row$Kr,
    k_f            = best_row$k_f,
    alpha_state    = best_row$alpha_state,
    T              = best_row$T,
    k_e            = best_row$k_e,
    k_n            = best_row$k_n,
    k_1            = best_row$k_1,
    k_2            = best_row$k_2,
    k_w            = best_row$k_w,
    k_s            = best_row$k_s,
    pre_buffer     = best_row$Kb,
    bs_week        = best_row$bs_week,
    bs_fs_marginal = best_row$bs_fs_marginal,
    lambda_w       = if ("lambda_w" %in% names(best_row)) best_row$lambda_w else 0,
    w_floor        = if ("w_floor"  %in% names(best_row)) best_row$w_floor  else 0
  )
}

#' Train Stage-2 joint model
#'
#' Preferred usage: pass only \code{spec}. The function will use \code{spec$best_row}
#' to construct features and \code{spec$formula} to fit the model.
#'
#' Backward compatible: if \code{spec=NULL}, you may pass \code{best_mean_nll} and legacy
#' basis sizes (k_e, k_n, k_1, k_2).
#'
#' @param dat Multi-season input data.
#' @param template_df Template curve.
#' @param spec Stage-2 spec created by \code{stage2_make_spec()}.
#' @param best_mean_nll Legacy tuned row (delta,K,k_f,alpha_state) if \code{spec=NULL}.
#' @param ign_week_df Optional ignition week estimates for alignment in held-out/new seasons.
#' @param method mgcv method.
#' @param verbose logical.
#'
#' @export
train_stage2_joint <- function(dat,
                               template_df,
                               spec = NULL,
                               # legacy
                               best_mean_nll = NULL,
                               pre_buffer = NULL,
                               alpha_state = NULL,
                               k_e = 6L,
                               k_n = 6L,
                               k_1 = 6L,
                               k_2 = 6L,
                               ign_week_df = NULL,
                               method = "REML",
                               lambda_w = 0,
                               w_floor  = NULL,
                               m1_preds = NULL,
                               verbose = TRUE) {
  if (!requireNamespace("mgcv", quietly = TRUE)) stop("Please install mgcv.")

  if (!is.null(spec)) {
    if (is.null(best_mean_nll)) best_mean_nll <- spec$best_row
    if (is.null(pre_buffer))  pre_buffer  <- spec$pre_buffer
    if (is.null(alpha_state)) alpha_state <- spec$alpha_state
    if (lambda_w == 0 && !is.null(spec$lambda_w)) lambda_w <- spec$lambda_w
    if (is.null(w_floor) && !is.null(spec$w_floor)) w_floor <- spec$w_floor
  }
  w_floor <- as.numeric(w_floor %||% 0)
  if (is.null(best_mean_nll)) stop("Provide either spec=... or best_mean_nll=...")
  
  # If spec is NULL and alpha_state was not provided, try to take it from best_mean_nll
  if (is.null(spec) && is.null(alpha_state)) {
    if (is.data.frame(best_mean_nll) && "alpha_state" %in% names(best_mean_nll)) {
      alpha_state <- best_mean_nll$alpha_state[1L]
    } else if (is.list(best_mean_nll) && !is.data.frame(best_mean_nll) && !is.null(best_mean_nll)) {
      alpha_state <- best_mean_nll[["alpha_state"]]
    }
  }
  # ramp is controlled by K (K<=1 => no ramp)
  leads    <- if (!is.null(spec)) spec$leads else c(1L, 2L)
  
  d_all <- prep_stage2_joint(
    dat,
    best_mean_nll = best_mean_nll,
    template_df   = template_df,
    leads         = leads,
    ign_week_df   = ign_week_df,
    pre_buffer    = as.integer(pre_buffer %||% 0L),
    alpha_state   = as.numeric(alpha_state %||% 0.30),
    m1_preds      = m1_preds,
    verbose       = FALSE
  )
  
  train_stage2_joint_prepped(
    d_all = d_all,
    best_mean_nll = best_mean_nll,
    template_df = template_df,
    spec = spec,
    k_e = k_e,
    k_n = k_n,
    k_1 = k_1,
    k_2 = k_2,
    method = method,
    lambda_w = lambda_w,
    w_floor  = w_floor,
    verbose = verbose
  )
}

#' Format current-season observations for Stage-2 refit
#'
#' Converts raw current-season surveillance data and M1 alignment outputs into the
#' column set required by \code{train_stage2_joint()}: \code{season}, \code{weekF},
#' \code{phase}, \code{newWeek}, \code{y}, \code{N}, \code{neg}, \code{d1_link},
#' \code{d2_link}.
#'
#' @param currentSeason data.frame with columns \code{weekF}, \code{y}, and either
#'   \code{N} (total tests) or \code{neg} (negative tests).
#' @param iWeek_used Integer. Ignition week on the \code{weekF} scale.
#' @param template_df data.frame with columns \code{newWeek} and \code{fit} (unused
#'   here but retained for signature compatibility with \code{refit_stage2_weekly}).
#' @param spec Stage-2 spec from \code{stage2_make_spec()}. Must contain
#'   \code{spec$anchorWeek}.
#' @param season_label Character label for the current season (default \code{"current"}).
#' @param k Integer knot count passed to \code{add_prospective_derivs_link()} (default \code{5L}).
#' @return data.frame with the required Stage-2 columns, ready to \code{rbind} with
#'   historical aligned data.
#' @export
format_current_for_stage2 <- function(currentSeason,
                                      iWeek_used,
                                      template_df = NULL,
                                      spec        = NULL,
                                      season_label = "current",
                                      k = 5L) {
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  iWeek_used <- as.integer(iWeek_used[1L])
  anchorWeek <- as.integer(
    if (!is.null(spec) && !is.null(spec$anchorWeek)) spec$anchorWeek else 20L
  )

  df <- currentSeason
  if (!"neg" %in% names(df) && "N" %in% names(df) && "y" %in% names(df))
    df$neg <- df$N - df$y
  if (!"N" %in% names(df) && "neg" %in% names(df) && "y" %in% names(df))
    df$N <- df$y + df$neg
  df$season  <- as.character(season_label)
  df$phase   <- as.integer(!is.na(df$weekF) & as.integer(df$weekF) >= iWeek_used)
  df$newWeek <- as.integer(df$weekF) - iWeek_used + anchorWeek

  df <- add_prospective_derivs_link(df, k = as.integer(k), eps = 1e-6, min_obs = 4L)
  as.data.frame(df)
}

#' Refit Stage-2 GAM with current-season data for weekly prospective forecasting
#'
#' Combines all historical aligned data with the current season's observations
#' (formatted via \code{format_current_for_stage2}) and refits the Stage-2 GAM.
#' Call this function each week after ignition detection to obtain an updated model
#' that has estimated the live season's random effect and factor-smooth.
#'
#' @param current_obs data.frame with columns \code{weekF}, \code{y}, \code{N}
#'   (or \code{y}/\code{neg}) for the current season up to the current week.
#' @param iWeek_used Numeric. Detected ignition week (on weekF scale).
#' @param hist_data \code{alignedD_prosp} — historical aligned dataset (all past seasons).
#' @param template_df Template curve with \code{newWeek} and \code{fit}.
#' @param spec Stage-2 spec from \code{stage2_spec_from_tuning()}.
#' @param season_label Character. Label for the current season (default \code{"current"}).
#' @param addFS Integer threshold for re-enabling the season-specific factor-smooth
#'   in a brand-new season refit. If \code{NULL} (default), the factor-smooth is
#'   never included in weekly refits for unseen seasons. If an integer is given,
#'   the original \code{spec$k_s} is restored once at least that many post-ignition
#'   origin weeks are available in \code{current_obs}.
#' @param verbose Logical. Print progress messages.
#' @return Output of \code{train_stage2_joint()} on the combined dataset.
#' @export
refit_stage2_weekly <- function(current_obs,
                                iWeek_used,
                                hist_data,
                                template_df,
                                spec,
                                m1_preds     = NULL,
                                season_label = "current",
                                addFS = NULL,
                                verbose = TRUE) {
  refit_spec <- spec
  fit_method <- "REML"
  addFS <- if (is.null(addFS)) NULL else as.integer(addFS[1L])

  # For a brand-new season, the season-specific factor-smooth is both the
  # slowest term and the least stable early after ignition. The walk-forward
  # plotting code excludes season-specific terms at prediction time anyway, so
  # dropping the fs term here preserves the intended prediction target while
  # avoiding multi-minute/hour refits on only a handful of current-season rows.
  if (!season_label %in% unique(hist_data$season) && isTRUE(refit_spec$k_s > 0L)) {
    post_ign_weeks <- sum(unique(current_obs$weekF) >= as.integer(iWeek_used), na.rm = TRUE)
    keep_fs <- !is.null(addFS) && is.finite(addFS) && post_ign_weeks >= addFS
    if (!isTRUE(keep_fs)) {
      refit_spec$k_s <- 0L
      fit_method <- "fREML"
    }
  }

  cur_fmt <- format_current_for_stage2(
    currentSeason = current_obs,
    iWeek_used    = iWeek_used,
    template_df   = template_df,
    spec          = refit_spec,
    season_label  = season_label
  )
  dat_refit <- dplyr::bind_rows(hist_data, cur_fmt)
  # m1_preds: M1 walk-forward predictions for historical training seasons.
  # When supplied, prep_stage2_joint() overrides logit_f_eff with M1-based
  # values for those seasons, matching how the production frozen GAM was trained.
  # The current-season rows (cur_fmt) fall back to template-based logit_f_eff.
  train_stage2_joint(
    dat         = dat_refit,
    template_df = template_df,
    spec        = refit_spec,
    m1_preds    = m1_preds,
    method      = fit_method,
    verbose     = verbose
  )
}

# =========================================================
# Stage-2 tuning
# =========================================================

#' Tune a list of Stage-2 specs via LOSO
#'
#' This function evaluates each candidate \code{spec} under leave-one-season-out.
#' For each held-out season, it fits the model on the remaining seasons using
#' \code{train_stage2_joint()}, then scores post-ignition rows on the held-out
#' season using \code{score_stage2_metrics()}.
#'
#' @param dat Multi-season input data.
#' @param template_df Template curve.
#' @param specs Named list of spec objects.
#' @param ign_hat_df Optional ignition week estimates by season (cols season,iWeek_hat).
#' @param testSeason NULL for LOSO across all seasons, else a single season.
#' @param method mgcv method.
#' @param exclude_newseason_terms If TRUE, excludes \code{s(season)} and \code{fs} during scoring.
#' @param num.cores Parallel workers.
#'
#' @return list(results, best_by_season, best_overall)
#' @export
