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
                           return_ci       = FALSE) {

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

  if (isTRUE(return_ci)) {
    eta <- as.numeric(pr$fit)
    se  <- as.numeric(pr$se.fit)
    list(
      m2_p  = cap(pmin(1 - eps, pmax(eps, stats::plogis(eta)))),
      m2_lo = cap(pmin(1 - eps, pmax(eps, stats::plogis(eta - 1.96 * se)))),
      m2_hi = cap(pmin(1 - eps, pmax(eps, stats::plogis(eta + 1.96 * se))))
    )
  } else {
    eta <- as.numeric(pr)
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
      logit_f_eff = .data$omega * .data$logit_f
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
        )
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
  
  # DEFAULT: full model (everything on) unless user supplies spec
  if (is.null(spec)) {
    spec <- stage2_make_spec(
      delta = get1(best_mean_nll, "delta", 0L),
      K = get1(best_mean_nll, "K", 3L),
      k_f = k_f,
      alpha_state = get1(best_mean_nll, "alpha_state", 0.30),
      template_mode = "smooth",
      # full terms ON
      k_w = 8L,
      k_s   = 6L,
      k_e = as.integer(k_e),
      k_n = as.integer(k_n),
      k_1   = as.integer(k_1),
      k_2   = as.integer(k_2),
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
tune_stage2_loso_specs <- function(
    dat,
    template_df,
    specs,
    ign_hat_df = NULL,
    testSeason = NULL,
    method = "REML",
    exclude_newseason_terms = TRUE,
    lambda_w = 0,
    eval_window = NULL,
    num.cores = 8L,
    verbose = TRUE,
    progress_every = 200L
) {
  stopifnot(is.data.frame(dat))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("parallel", quietly = TRUE)) stop("Please install parallel.")
  
  if (!is.list(specs) || length(specs) == 0L) stop("specs must be a non-empty list.")
  if (is.null(names(specs))) names(specs) <- paste0("spec_", seq_along(specs))
  
  seasons_all <- unique(dat$season)
  test_seasons <- if (is.null(testSeason)) seasons_all else testSeason
  if (!all(test_seasons %in% seasons_all)) stop("Unknown testSeason(s): ", paste(setdiff(test_seasons, seasons_all), collapse = ", "))
  
  tasks <- expand.grid(
    spec_id = names(specs),
    test_season = test_seasons,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  
  if (verbose) message("[tune_stage2_loso_specs] tasks=", nrow(tasks), " specs=", length(specs), " seasons=", length(test_seasons))
  
  getS <- function(spec, nm, default = NULL) {
    if (!is.null(spec[[nm]])) return(spec[[nm]])
    default
  }
  
  eval_one <- function(task_row) {
    sid <- as.character(task_row$spec_id)
    ts  <- as.character(task_row$test_season)
    spec <- specs[[sid]]
    
    train_dat <- dat[dat$season != ts, , drop = FALSE]
    test_dat  <- dat[dat$season == ts, , drop = FALSE]
    
    spec_lambda_w <- getS(spec, "lambda_w", lambda_w)  # per-spec override or function default

    fit_out <- try(train_stage2_joint(
      dat = train_dat,
      template_df = template_df,
      spec = spec,
      method = method,
      lambda_w = spec_lambda_w,
      verbose = FALSE
    ), silent = TRUE)
    
    if (inherits(fit_out, "try-error")) {
      return(data.frame(ok = FALSE, spec_id = sid, test_season = ts,
                        n_train = NA_integer_, n_test = NA_integer_,
                        nll = NA_real_, mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_,
                        err = as.character(fit_out)[1], stringsAsFactors = FALSE))
    }
    
    ign_override <- NULL
    if (!is.null(ign_hat_df)) {
      stopifnot(all(c("season","iWeek_hat") %in% names(ign_hat_df)))
      ign_override <- ign_hat_df[ign_hat_df$season == ts, , drop = FALSE]
      if (nrow(ign_override) == 0L) ign_override <- NULL
    }
    
    d_test_all <- prep_stage2_joint(
      dat = test_dat,
      best_mean_nll = spec$best_row,
      template_df = template_df,
      use_ramp = getS(spec, "use_ramp", TRUE),
      leads = getS(spec, "leads", c(1L, 2L)),
      ign_week_df = ign_override,
      pre_buffer = getS(spec, "pre_buffer", 0L),
      alpha_state = getS(spec, "alpha_state", 0.30),
      verbose = FALSE
    )
    
    d_test <- d_test_all[d_test_all$post_ign, , drop = FALSE]
    d_train_used <- fit_out$train_data
    
    if (nrow(d_train_used) == 0L || nrow(d_test) == 0L) {
      return(data.frame(ok = TRUE, spec_id = sid, test_season = ts,
                        n_train = nrow(d_train_used), n_test = nrow(d_test),
                        nll = NA_real_, mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_,
                        err = NA_character_, stringsAsFactors = FALSE))
    }
    
    ex_terms <- NULL
    if (isTRUE(exclude_newseason_terms)) ex_terms <- stage2_exclude_newseason(spec)
    
    sc <- score_stage2_metrics(fit_out$fit, d_test, exclude_season_re = FALSE,
                               exclude_terms = ex_terms,
                               lambda_w = 0,           # eval on uniform weights (fixed objective)
                               eval_window = eval_window)
    
    data.frame(
      ok = TRUE,
      spec_id = sid,
      test_season = ts,
      delta = getS(spec, "delta", NA_integer_),
      K = getS(spec, "K", NA_integer_),
      k_f = getS(spec, "k_f", NA_integer_),
      alpha_state = getS(spec, "alpha_state", NA_real_),
      lambda_w = spec_lambda_w,
      template_mode = getS(spec, "template_mode", NA_character_),
      k_w = getS(spec, "k_w", NA_integer_),
      k_s = getS(spec, "k_s", NA_integer_),
      k_2 = getS(spec, "k_2", NA_integer_),
      n_train = nrow(d_train_used),
      n_test = nrow(d_test),
      nll = sc$nll,
      mean_nll = sc$mean_nll,
      brier = sc$brier,
      rmse_p = sc$rmse_p,
      err = NA_character_,
      stringsAsFactors = FALSE
    )
  }
  
  eval_one_safe <- function(task_row) {
    tryCatch(eval_one(task_row), error = function(e) {
      data.frame(ok = FALSE, spec_id = as.character(task_row$spec_id), test_season = as.character(task_row$test_season),
                 n_train = NA_integer_, n_test = NA_integer_, nll = NA_real_, mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_,
                 err = conditionMessage(e), stringsAsFactors = FALSE)
    })
  }
  
  num.cores <- as.integer(num.cores)
  if (is.na(num.cores) || num.cores < 1L) num.cores <- 1L
  
  if (num.cores == 1L) {
    out_list <- vector("list", nrow(tasks))
    for (i in seq_len(nrow(tasks))) {
      if (verbose && (i %% progress_every == 0L)) message("  [progress] ", i, "/", nrow(tasks))
      out_list[[i]] <- eval_one_safe(tasks[i, , drop = FALSE])
    }
  } else {
    idx <- seq_len(nrow(tasks))
    if (!requireNamespace("future", quietly = TRUE) ||
        !requireNamespace("future.apply", quietly = TRUE)) {
      stop("tune_stage2_loso_specs: parallel requires 'future' + 'future.apply'.")
    }
    old_plan <- future::plan()
    on.exit(future::plan(old_plan), add = TRUE)
    strat <- if (.Platform$OS.type == "windows") future::multisession else future::multicore
    future::plan(strat, workers = num.cores)

    # capture everything eval_one_safe needs in a globals list for future
    fg <- list(
      dat = dat, template_df = template_df, specs = specs,
      ign_hat_df = ign_hat_df, method = method,
      lambda_w = lambda_w, eval_window = eval_window,
      tasks = tasks,
      eval_one = eval_one, eval_one_safe = eval_one_safe,
      getS = getS,
      prep_stage2_joint = prep_stage2_joint,
      train_stage2_joint = train_stage2_joint,
      train_stage2_joint_prepped = train_stage2_joint_prepped,
      score_stage2_metrics = score_stage2_metrics,
      stage2_exclude_newseason = stage2_exclude_newseason,
      stage2_build_joint_formula = stage2_build_joint_formula,
      stage2_make_spec = stage2_make_spec,
      logit_stable = logit_stable,
      stage2_ramp_weight = stage2_ramp_weight,
      `%||%` = `%||%`
    )

    out_list <- future.apply::future_lapply(
      idx,
      FUN = function(i) eval_one_safe(tasks[i, , drop = FALSE]),
      future.seed = TRUE,
      future.packages = c("dplyr", "mgcv"),
      future.globals  = fg
    )
  }
  
  results <- as.data.frame(dplyr::bind_rows(out_list), stringsAsFactors = FALSE)
  if (nrow(results) == 0L) stop("tune_stage2_loso_specs: no results returned")
  
  metrics <- c("nll","mean_nll","brier","rmse_p")
  
  best_by_season <- list()
  for (ts in unique(results$test_season)) {
    d_ts <- results[results$test_season == ts & results$ok, , drop = FALSE]
    best_by_season[[ts]] <- lapply(metrics, function(m) {
      d2 <- d_ts[is.finite(d_ts[[m]]), , drop = FALSE]
      if (nrow(d2) == 0L) return(NULL)
      d2[which.min(d2[[m]]), , drop = FALSE]
    })
    names(best_by_season[[ts]]) <- metrics
  }
  
  best_overall <- lapply(metrics, function(m) {
    d2 <- results[results$ok & is.finite(results[[m]]), , drop = FALSE]
    if (nrow(d2) == 0L) return(NULL)
    agg <- stats::aggregate(d2[[m]] ~ spec_id, data = d2, FUN = sum)
    names(agg)[2] <- "sum_metric"
    agg <- agg[order(agg$sum_metric), , drop = FALSE]
    agg[1, , drop = FALSE]
  })
  names(best_overall) <- metrics
  
  list(results = results, best_by_season = best_by_season, best_overall = best_overall)
}

#' Tune Stage-2 over (delta,K,k_f,alpha_state) with a fixed model structure
#'
#' This is a compatibility wrapper that replicates the QMD workflow, but internally
#' it expands a grid of specs and calls \code{tune_stage2_loso_specs()}.
#'
#' If \code{spec_base} is NULL, it uses the **full model** (all terms on) as the default.
#' That means your Stage-2 now includes:
#' \code{s(logit_f_eff)} + \code{s(newWeek)} + \code{fs(newWeek,season_h)} + \code{z_ema, logN_now, d1, d2} + season RE.
#'
#' @param dat Multi-season input data.
#' @param template_df Template curve.
#' @param spec_base A spec that defines model structure (k's, template_mode, etc.).
#' @param shift_grid,K_grid,k_f_grid,alpha_grid Grids to tune.
#' @param ign_hat_df Optional ignition week estimates by season.
#' @param pre_buffer Weeks before ignition included.
#' @param leads Forecast horizons.
#' @param num.cores Parallel workers.
#'
#' @return list(results, best_by_season, best_overall)
#' @export
tune_stage2_loso_shift_template <- function(
    dat,
    template_df,
    spec_base = NULL,
    testSeason = NULL,
    shift_grid = -3:3,
    ign_hat_df = NULL,
    pre_buffer = 1L,
    K_grid = 2:6,
    k_f_grid = c(6L, 8L, 10L),
    alpha_grid = c(0.15, 0.25, 0.35, 0.50),
    leads = c(1L, 2L),
    lambda_w_grid = 0,
    eval_window = NULL,
    num.cores = 8L,
    verbose = TRUE
) {
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")

  # Base spec defines *structure* (k's, T, bases) while the grid tunes (delta, K, k_f, alpha_state).
  if (is.null(spec_base)) {
    spec_base <- stage2_make_spec(
      delta = 0L, K = 3L, k_f = 6L, alpha_state = 0.30,
      pre_buffer = as.integer(pre_buffer),
      leads = as.integer(leads),
      T = "S",
      k_w = 8L, k_s = 6L, k_e = 6L, k_n = 6L, k_1 = 6L, k_2 = 6L
    )
  } else {
    spec_base$pre_buffer <- as.integer(pre_buffer)
    spec_base$leads <- as.integer(leads)
  }

  shift_grid    <- as.integer(shift_grid)
  K_grid        <- as.integer(K_grid)
  k_f_grid      <- as.integer(k_f_grid)
  alpha_grid    <- as.numeric(alpha_grid)
  lambda_w_grid <- as.numeric(lambda_w_grid)

  grid <- expand.grid(
    delta       = shift_grid,
    K           = K_grid,
    k_f         = k_f_grid,
    alpha_state = alpha_grid,
    lambda_w    = lambda_w_grid,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )

  # Build a list of specs (one per hyperparam combination)
  specs <- vector("list", nrow(grid))
  nm <- character(nrow(grid))
  for (i in seq_len(nrow(grid))) {
    g <- grid[i, ]
    s <- spec_base
    s$delta       <- as.integer(g$delta)
    s$K           <- as.integer(g$K)
    s$k_f         <- as.integer(g$k_f)
    s$alpha_state <- as.numeric(g$alpha_state)
    s$lambda_w    <- as.numeric(g$lambda_w)
    s$best_row    <- data.frame(delta = s$delta, K = s$K, k_f = s$k_f, alpha_state = s$alpha_state,
                                stringsAsFactors = FALSE)
    s$formula          <- stage2_build_joint_formula(s)
    s$exclude_newseason <- stage2_exclude_newseason(s)

    nm[i] <- paste0("d", s$delta, "_K", s$K, "_kf", s$k_f,
                    "_a", formatC(s$alpha_state, digits = 2, format = "f"),
                    "_lw", formatC(s$lambda_w,    digits = 3, format = "f"))
    specs[[i]] <- s
  }
  names(specs) <- nm
  
  tuned <- tune_stage2_loso_specs(
    dat = dat,
    template_df = template_df,
    specs = specs,
    ign_hat_df = ign_hat_df,
    testSeason = testSeason,
    method = "REML",
    exclude_newseason_terms = TRUE,
    lambda_w = 0,          # per-spec lambda_w is read from spec$lambda_w inside eval_one
    eval_window = eval_window,
    num.cores = num.cores,
    verbose = verbose
  )
  
  # Return a legacy-friendly object:
  # - results has delta/K/k_f/alpha_state + metrics for each held-out season
  # - best_by_season / best_overall already computed inside tune_stage2_loso_specs
  tuned$results <- dplyr::select(
    tuned$results,
    .data$ok, .data$test_season, .data$spec_id,
    .data$delta, .data$K, .data$k_f, .data$alpha_state, .data$lambda_w,
    .data$n_train, .data$n_test,
    .data$nll, .data$mean_nll, .data$brier, .data$rmse_p,
    .data$err
  )
  
  tuned
}

# =========================================================
# Plot helper used in QMD

# =========================================================

plot_tune_stage2_heatmap <- function(df,
                                     metric = "mean_nll",
                                     agg = TRUE,
                                     test_season = NULL,
                                     base_size = 10,
                                     normalize01 = TRUE,
                                     norm_scope = c("facet", "global"),
                                     center = c("none", "facet_min", "global_min"),
                                     score_transform = c("none", "log", "log1p", "sqrt"),
                                     eps = 1e-9,
                                     star_best = TRUE,
                                     low = "red",
                                     high = "blue") {
  norm_scope <- match.arg(norm_scope)
  center <- match.arg(center)
  score_transform <- match.arg(score_transform)

  # Accept full tuned2 list: auto-extract by_spec_grid
  if (is.list(df) && !is.data.frame(df) && !is.null(df$by_spec_grid))
    df <- df$by_spec_grid

  stopifnot(is.data.frame(df), metric %in% names(df))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Please install ggplot2.")
  if (!requireNamespace("scales", quietly = TRUE)) stop("Please install scales.")

  # Normalize column names: Kr -> K (new tuning output structure)
  if ("Kr" %in% names(df) && !"K" %in% names(df))
    df <- dplyr::rename(df, K = Kr)
  # Normalize season column: season_out -> test_season
  if ("season_out" %in% names(df) && !"test_season" %in% names(df))
    df <- dplyr::rename(df, test_season = season_out)
  # If already aggregated (no test_season col) and agg=TRUE, add dummy season
  if (!"test_season" %in% names(df) && isTRUE(agg))
    df$test_season <- "pooled"

  need <- c("test_season", "delta", "K", "k_f", "alpha_state", metric)
  miss <- setdiff(need, names(df))
  if (length(miss)) stop("Missing cols: ", paste(miss, collapse = ", "))
  
  d <- df %>%
    dplyr::transmute(
      test_season = as.factor(.data$test_season),
      delta       = as.integer(.data$delta),
      K           = as.integer(.data$K),
      k_f         = as.integer(.data$k_f),
      alpha_state = as.numeric(.data$alpha_state),
      val_raw     = .data[[metric]]
    )
  
  if (!is.null(test_season)) d <- d %>% dplyr::filter(.data$test_season %in% test_season)
  
  if (isTRUE(agg)) {
    d <- d %>%
      dplyr::group_by(.data$delta, .data$K, .data$k_f, .data$alpha_state) %>%
      dplyr::summarise(val_raw = mean(.data$val_raw, na.rm = TRUE), n_folds = dplyr::n(), .groups = "drop")
  }
  
  d <- d %>% dplyr::mutate(val = .data$val_raw)
  
  if (center == "facet_min") {
    grp <- if (isTRUE(agg)) c("k_f", "alpha_state") else c("test_season", "k_f", "alpha_state")
    d <- d %>%
      dplyr::group_by(dplyr::across(dplyr::all_of(grp))) %>%
      dplyr::mutate(val = .data$val - min(.data$val, na.rm = TRUE)) %>%
      dplyr::ungroup()
  } else if (center == "global_min") {
    d <- d %>% dplyr::mutate(val = .data$val - min(.data$val, na.rm = TRUE))
  }
  
  if (score_transform == "log") {
    d <- d %>% dplyr::mutate(val = log(pmax(.data$val, eps)))
  } else if (score_transform == "log1p") {
    d <- d %>% dplyr::mutate(val = log1p(pmax(.data$val, 0)))
  } else if (score_transform == "sqrt") {
    d <- d %>% dplyr::mutate(val = sqrt(pmax(.data$val, 0)))
  }
  
  best_row <- NULL
  if (isTRUE(star_best)) {
    best_row <- d %>%
      dplyr::filter(is.finite(.data$val_raw)) %>%
      dplyr::slice_min(.data$val_raw, n = 1, with_ties = FALSE)
  }
  
  if (isTRUE(normalize01)) {
    if (norm_scope == "facet") {
      grp <- if (isTRUE(agg)) c("k_f", "alpha_state") else c("test_season", "k_f", "alpha_state")
      d <- d %>%
        dplyr::group_by(dplyr::across(dplyr::all_of(grp))) %>%
        dplyr::mutate(val01 = scales::rescale(.data$val, to = c(0, 1), na.rm = TRUE)) %>%
        dplyr::ungroup()
    } else {
      d <- d %>% dplyr::mutate(val01 = scales::rescale(.data$val, to = c(0, 1), na.rm = TRUE))
    }
    fill_col <- "val01"
    fill_lab <- paste0(metric,
                       if (center != "none") " (regret)" else "",
                       if (score_transform != "none") paste0(" + ", score_transform) else "",
                       if (norm_scope == "facet") " (norm facet)" else " (norm global)")
  } else {
    fill_col <- "val"
    fill_lab <- paste0(metric,
                       if (center != "none") " (regret)" else "",
                       if (score_transform != "none") paste0(" + ", score_transform) else "")
  }
  
  ggplot2::ggplot(d, ggplot2::aes(x = .data$delta, y = .data$K)) +
    ggplot2::geom_tile(ggplot2::aes(fill = .data[[fill_col]]), linewidth = 0) +
    ggplot2::facet_grid(
      rows = ggplot2::vars(.data$alpha_state),
      cols = ggplot2::vars(.data$k_f),
      labeller = ggplot2::label_both
    ) +
    ggplot2::scale_x_continuous(breaks = sort(unique(d$delta))) +
    ggplot2::scale_y_continuous(breaks = sort(unique(d$K))) +
    ggplot2::scale_fill_gradient(low = low, high = high, name = fill_lab) +
    ggplot2::labs(x = "delta (shift)", y = "K (ramp)", title = if (agg) "Stage-2 tuning (mean across test_season)" else "Stage-2 tuning") +
    ggplot2::labs(fill = NULL) +
    ggplot2::guides(fill = ggplot2::guide_colorbar(title = NULL)) +
    ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(panel.grid = ggplot2::element_blank()) +
    (if (isTRUE(star_best) && !is.null(best_row) && nrow(best_row) == 1)
      ggplot2::geom_point(data = best_row,
                          ggplot2::aes(x = .data$delta, y = .data$K),
                          inherit.aes = FALSE,
                          shape = 8, size = 3.2, stroke = 1)
     else NULL)
}

# =========================================================
# Training-fit plotting helper (kept compatible with QMD)
# =========================================================

.plot_stage2_joint_fit_prosp <- function(joint_out,
                                            dat_raw,
                                            ign_hat_df = NULL,
                                            exclude_season_re = FALSE,
                                            pre_buffer = 0L,
                                            facet_by_lead = TRUE,
                                            template_df = NULL) {
  stopifnot(is.list(joint_out), !is.null(joint_out$fit), !is.null(joint_out$tuned))
  stopifnot(is.data.frame(dat_raw))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Please install ggplot2.")
  
  if (is.null(template_df)) {
    if (exists("template_df", inherits = TRUE)) template_df <- get("template_df", inherits = TRUE)
  }
  if (is.null(template_df)) stop("plot_stage2_joint_fit_by_season: please pass template_df (fit curve) explicitly")
  
  d_all <- prep_stage2_joint(
    dat_raw,
    template_df = template_df,
    best_mean_nll = joint_out$tuned,
    ign_week_df = ign_hat_df,
    pre_buffer = pre_buffer,
    alpha_state = (joint_out$tuned$alpha_state %||% 0.30)
  )
  
  d_all <- d_all %>% dplyr::mutate(p_obs = .data$y_lead / .data$N_lead)
  
  d_fit <- d_all[d_all$post_ign, , drop = FALSE]
  ex <- if (isTRUE(exclude_season_re)) "s(season)" else NULL
  d_fit$p_hat <- as.numeric(stats::predict(joint_out$fit, newdata = d_fit, type = "response", exclude = ex))
  
  ign_true <- dat_raw %>%
    dplyr::group_by(.data$season) %>%
    dplyr::summarise(
      iWeek_true = suppressWarnings(min(.data$weekF[.data$phase == 1L], na.rm = TRUE)),
      .groups = "drop"
    )
  
  if (!is.null(ign_hat_df)) {
    stopifnot(all(c("season","iWeek_hat") %in% names(ign_hat_df)))
    ign_hat_df <- ign_hat_df %>%
      dplyr::transmute(season = as.character(.data$season), iWeek_hat = as.numeric(.data$iWeek_hat))
  }
  
  p <- ggplot2::ggplot(d_all, ggplot2::aes(x = .data$weekF)) +
    ggplot2::geom_point(ggplot2::aes(y = .data$p_obs, alpha = .data$post_ign), colour = "black", size = 1.05) +
    ggplot2::scale_alpha_manual(values = c(`FALSE` = 0.25, `TRUE` = 0.85), guide = "none") +
    ggplot2::geom_line(data = d_fit,
                       ggplot2::aes(y = .data$p_hat, group = interaction(.data$season, .data$lead)),
                       colour = "red", linewidth = 0.9) +
    ggplot2::geom_vline(data = ign_true, ggplot2::aes(xintercept = .data$iWeek_true), linewidth = 0.6) +
    ggplot2::labs(x = "weekF", y = "Lead positivity",
                  title = "Stage-2 fitted vs observed by season (post-ignition fit only)") +
    ggplot2::theme_bw()
  
  if (!is.null(ign_hat_df)) {
    p <- p + ggplot2::geom_vline(data = ign_hat_df, ggplot2::aes(xintercept = .data$iWeek_hat),
                                 linetype = "dashed", linewidth = 0.6)
  }
  
  if (isTRUE(facet_by_lead)) {
    p + ggplot2::facet_grid(lead ~ season, scales = "free_y")
  } else {
    p + ggplot2::facet_wrap(~ season, scales = "free_y")
  }
}


# NOTE: expand_grid_specs() has been consolidated into m2_spec_grid.R.
# Use the version there — it supports the full hyperparameter grid.


#’ Bundle all trained components into a prospective forecasting kit
#’
#’ Packages Stage-1 ignition detection and Stage-2 forecasting into a single list
#’ for prospective deployment. The weekly-refit workflow refits the Stage-2 GAM
#’ with current-season data each week; no offline calibration or online updater is stored.
#’
#’ Accepts either high-level training output objects (\code{ign_fit}, \code{joint_out})
#’ or the individual pieces directly. High-level objects take precedence only when the
#’ corresponding individual argument is \code{NULL}.
#’
#’ @param template_df Data frame with columns \code{newWeek} and \code{fit} defining
#’   the reference template curve.
#’ @param ign_fit Output of \code{fitIgnition()}. Used to extract \code{gam_cls} when
#’   \code{gam_cls} is \code{NULL}.
#’ @param gam_cls A trained \pkg{mgcv} \code{gam}/\code{bam} classifier, or a container
#’   accepted by \code{get_gam_cls()}. Overrides extraction from \code{ign_fit}.
#’ @param params_stage1 List of tuned Stage-1 threshold parameters (e.g.
#’   \code{tuned$best_params}).
#’ @param joint_out Output of \code{train_stage2_joint()}. Used to extract
#’   \code{spec_stage2}, \code{stage2_fit}, and \code{train_data_stage2} when those
#’   are \code{NULL}.
#’ @param spec_stage2 Stage-2 spec list from \code{stage2_make_spec()} or
#’   \code{stage2_spec_from_tuning()}. Overrides extraction from \code{joint_out}.
#’ @param stage2_fit Fitted \pkg{mgcv} \code{gam}/\code{bam} Stage-2 model. Overrides
#’   extraction from \code{joint_out}.
#’ @param train_data_stage2 Stage-2 training design data frame (preserves factor levels).
#’   Overrides extraction from \code{joint_out}.
#’ @param best_mean_nll 1-row data frame or list with \code{delta}/\code{K}/\code{leads}.
#’   Derived from \code{spec_stage2$best_row} when \code{NULL}.
#’ @param exclude_stage2 Character vector of model terms to exclude for new-season
#’   prediction. Derived from \code{spec_stage2$exclude_newseason} when \code{NULL}.
#’ @param defaults Named list of prospective pipeline run-time defaults:
#’   \code{align}, \code{anchorWeek}, \code{pre_buffer}, \code{deriv_k}.
#’
#’ @return A named list with components \code{stage1}, \code{stage2}, and \code{defaults},
#’   ready to be passed to the prospective pipeline.
#’
#’ @examples
#’ \dontrun{
#’ # Preferred: pass training objects directly
#’ kit <- make_prospective_kit(
#’   template_df   = template_df,
#’   ign_fit       = ign_fit,
#’   params_stage1 = tuned$best_params,
#’   joint_out     = joint_out,
#’ )
#’
#’ # Legacy: pass individual components
#’ kit <- make_prospective_kit(
#’   template_df       = template_df,
#’   gam_cls           = gam_cls,
#’   params_stage1     = params_stage1,
#’   spec_stage2       = spec_stage2,
#’   stage2_fit        = joint_out$fit,
#’   train_data_stage2 = joint_out$train_data
#’ )
#’ }
#’
#’ @export
make_prospective_kit <- function(template_df,
                                 ign_fit = NULL,
                                 gam_cls = NULL,
                                 params_stage1 = NULL,
                                 joint_out = NULL,
                                 spec_stage2 = NULL,
                                 stage2_fit = NULL,
                                 train_data_stage2 = NULL,
                                 best_mean_nll = NULL,
                                 exclude_stage2 = NULL,
                                 defaults = list(
                                   align = TRUE,
                                   anchorWeek = 19L,
                                   pre_buffer = 1L,
                                   deriv_k = 5L
                                 )) {
  stopifnot(is.data.frame(template_df))
  stopifnot(is.list(defaults))

  # ---- extract from high-level training objects ----

  # Stage-1: pull gam_cls from ign_fit if not supplied directly
  if (is.null(gam_cls) && !is.null(ign_fit)) {
    gam_cls <- get_gam_cls(ign_fit)
  }

  # Stage-2: pull spec, fit, train_data from joint_out if not supplied directly
  if (!is.null(joint_out)) {
    if (is.null(spec_stage2)       && !is.null(joint_out$spec))       spec_stage2       <- joint_out$spec
    if (is.null(stage2_fit)        && !is.null(joint_out$fit))        stage2_fit        <- joint_out$fit
    if (is.null(train_data_stage2) && !is.null(joint_out$train_data)) train_data_stage2 <- joint_out$train_data
  }

  # ---- derive secondary fields from spec when not explicitly provided ----
  if (is.null(best_mean_nll) && is.list(spec_stage2) && "best_row" %in% names(spec_stage2)) {
    best_mean_nll <- spec_stage2$best_row
  }
  if (is.null(exclude_stage2) && is.list(spec_stage2) && "exclude_newseason" %in% names(spec_stage2)) {
    exclude_stage2 <- spec_stage2$exclude_newseason
  }
  # ---- backfill defaults$pre_buffer from spec (LOSO result) when available ----
  if (is.list(spec_stage2) && !is.null(spec_stage2$pre_buffer)) {
    defaults$pre_buffer <- as.integer(spec_stage2$pre_buffer)
  }

  # ---- validate required pieces ----
  if (is.null(gam_cls)) stop("gam_cls is required (or supply ign_fit to extract it).")
  if (is.null(params_stage1) || !is.list(params_stage1)) stop("params_stage1 must be a list.")
  if (!inherits(stage2_fit, c("gam", "bam"))) stop("stage2_fit must be a mgcv gam/bam (or supply joint_out).")
  if (!is.data.frame(train_data_stage2)) stop("train_data_stage2 must be a data frame (or supply joint_out).")

  list(
    stage1 = list(
      gam_cls = gam_cls,
      params  = params_stage1
    ),
    stage2 = list(
      template_df   = template_df,
      spec_stage2   = spec_stage2,       # single source of truth for spec (includes lambda_w)
      best_mean_nll = best_mean_nll,     # back-compat for helpers expecting delta/K/leads
      exclude_terms = exclude_stage2,    # terms to exclude for brand-new season prediction
      fit           = stage2_fit,
      train_data    = train_data_stage2
    ),
    defaults = defaults
  )
}

check_prospective_kit <- function(kit) {
  stopifnot(is.list(kit))
  req <- list(
    c("stage1","gam_cls"),
    c("stage1","params"),
    c("stage2","template_df"),
    c("stage2","spec_stage2"),
    c("stage2","fit"),
    c("stage2","train_data"),
    c("stage2","best_mean_nll"),
    c("stage2","exclude_terms"),
    c("defaults")
  )
  
  get_path <- function(x, path) {
    for (nm in path) x <- x[[nm]]
    x
  }
  
  missing <- vapply(req, function(p) is.null(try(get_path(kit, p), silent = TRUE)), logical(1))
  if (any(missing)) {
    bad <- vapply(req[missing], paste, collapse = "/", FUN.VALUE = character(1))
    stop("kit missing: ", paste(bad, collapse = ", "))
  }
  invisible(TRUE)
}
