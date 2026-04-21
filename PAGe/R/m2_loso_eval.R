# ============================================================
# Nested M1 → M2 LOSO: M2 evaluation
#
# Section 5b: frozen GAM + Holt EMA bias (production path).
# Section 5c: weekly refit (legacy comparison path).
# ============================================================

# ---------- 5b. M2 eval with frozen GAM + trend-augmented bias ----------

#' Evaluate M2 using a frozen GAM with walk-forward bias correction
#'
#' Variant of \code{nested_loso_m2_eval()} that applies Holt-style
#' trend-augmented bias correction during walk-forward evaluation. The GAM
#' is trained once on historical data (frozen); at each evaluation week the
#' correction is updated from out-of-sample residuals and extrapolated forward.
#'
#' This matches the deployment semantics of \code{run_m2_forecast()} and is
#' much faster than \code{nested_loso_m2_eval_weekly_refit()} (~12x) because
#' no GAM refitting occurs per eval week.
#'
#' @param allD Full multi-season data frame.
#' @param fold Fold object from \code{nested_loso_build_fold()}.
#' @param m2_fit Output of \code{nested_loso_m2_train()} (the trained M2 GAM).
#' @param m1_test_preds Output of \code{nested_loso_m1_test()}: tibble with
#'   columns \code{eval_weekF}, \code{target_weekF}, \code{h}, \code{m1_p_hat},
#'   \code{m1_tau}.
#' @param spec Stage-2 spec from \code{stage2_make_spec()}.
#' @param eval_window Integer; max t_since to evaluate (default 12L).
#' @param horizons Integer vector of forecast horizons (default \code{c(1L, 2L)}).
#' @param bias_alpha Numeric; EMA smoothing for level-only Holt bias correction (default 0.2).
#'   Not read from \code{spec} — this is a deployment-time parameter fixed outside the LOSO
#'   spec grid. LOSO showed it is unidentifiable in-distribution (flat NLL from 0.1–0.3).
#' @param k_deriv Integer; basis dim for M0 derivative estimation (default 10L).
#' @param manual_labels Optional named integer vector of manual ignition labels
#'   (deprecated; use \code{manual_labels_train} and \code{manual_labels_test}).
#' @param manual_labels_train Optional named integer vector of manual ignition
#'   labels for training seasons only. Used when building training-fold ignition.
#'   Should exclude the held-out test season (B4 fix).
#' @param manual_labels_test Optional named integer vector of manual ignition
#'   labels for the test season. Default \code{NULL} = use prospective
#'   \code{flagIgnition()} without override (no retrospective label leakage).
#' @param flag_args Named list forwarded to \code{flagIgnition()}.
#' @param verbose Logical.
#' @return Same structure as \code{nested_loso_m2_eval()}: list with
#'   \code{scores} and \code{predictions}.
#' @export
nested_loso_m2_eval_frozen_bias <- function(allD,
                                            fold,
                                            m2_fit,
                                            m1_test_preds,
                                            spec,
                                            eval_window        = 12L,
                                            horizons           = c(1L, 2L),
                                            bias_alpha         = 0.2,
                                            manual_labels      = NULL,
                                            manual_labels_train = NULL,
                                            manual_labels_test  = NULL,
                                            flag_args          = list(
                                              p_thresh   = 0.01,
                                              k1         = 0.4,
                                              k_c        = 0.01,
                                              n_consec   = 2L,
                                              min_window = 10L,
                                              w_min      = 21L,
                                              w_max      = 21L,
                                              d2_relax   = -0.01
                                            ),
                                            verbose = TRUE) {

  if (!requireNamespace("dplyr",   quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("tibble",  quietly = TRUE)) stop("Please install tibble.")
  if (!requireNamespace("purrr",   quietly = TRUE)) stop("Please install purrr.")
  `%||%` <- function(x, y) if (is.null(x)) y else x

  # B4 backward compat: old callers pass manual_labels; new callers use
  # manual_labels_train / manual_labels_test.  Redirect with deprecation warning.
  if (!is.null(manual_labels) && is.null(manual_labels_train) && is.null(manual_labels_test)) {
    warning(
      "[nested_loso_m2_eval_frozen_bias] `manual_labels` is deprecated. ",
      "Use `manual_labels_train` and `manual_labels_test` instead. ",
      "Redirecting: manual_labels_train = manual_labels, manual_labels_test = NULL.",
      call. = FALSE
    )
    manual_labels_train <- manual_labels
    manual_labels_test  <- NULL
  }

  test_s <- fold$test_season
  na_scores  <- tibble::tibble(season = test_s, n = NA_integer_,
                               mean_nll = NA_real_, bernoulli_nll = NA_real_,
                               brier = NA_real_, rmse_p = NA_real_)
  empty_preds <- tibble::tibble(
    season = character(), weekF = integer(), lead = character(),
    t_since = numeric(), p_hat = numeric(), p_obs = numeric(),
    y_lead = integer(), N_lead = integer(),
    p_lo = numeric(), p_hi = numeric()
  )

  if (isTRUE(verbose))
    message("[m2_eval_fb] Evaluating frozen+bias M2 on test season ", test_s)

  # --- Frozen fit ---
  if (is.null(m2_fit)) return(list(scores = na_scores, predictions = empty_preds))
  fit_obj     <- m2_fit$fit
  soft_cap_fn <- make_soft_cap_fn(fit_obj)
  lev_lead    <- levels(fit_obj$model$lead)
  lev_seas    <- levels(fit_obj$model$season)

  # --- Build aligned test data via M0 ---
  # B4 fix: use manual_labels_test (not manual_labels_train) for the test fold.
  # manual_labels_test = NULL → uses prospective flagIgnition without override.
  # This prevents the held-out season's true iWeek from leaking into the test fold.
  test_allD  <- dplyr::filter(allD, .data$season == test_s)
  if (nrow(test_allD) == 0L) return(list(scores = na_scores, predictions = empty_preds))

  # L2 fix: walk-forward derivatives — each week w uses only rows with weekF <= w,
  # so future weeks cannot influence the GAM smoother at earlier time points.
  test_deriv_data <- estimateDerivs_walkforward(test_allD, k = 10L)
  test_outs <- list(test_deriv_data) |>
    purrr::map(~ do.call(flagIgnition,
                         c(list(df = .x, manual_labels = manual_labels_test), flag_args)))
  aligned_test <- alignIgnition(test_outs)

  iWeek_used <- suppressWarnings(
    min(aligned_test$weekF[aligned_test$phase == 1L], na.rm = TRUE)
  )
  if (!is.finite(iWeek_used)) return(list(scores = na_scores, predictions = empty_preds))

  alpha_s_global <- as.numeric(spec$alpha_state %||% 0.25)

  if (is.null(m1_test_preds) || nrow(m1_test_preds) == 0L)
    return(list(scores = na_scores, predictions = empty_preds))

  ex_terms   <- spec$exclude_newseason
  if (is.null(ex_terms)) ex_terms <- stage2_exclude_newseason(spec)
  anchorWeek <- as.integer(spec$anchorWeek %||% fold$ref$anchorWeek %||% 20L)

  eval_weeks <- sort(unique(m1_test_preds$eval_weekF))
  eval_weeks <- eval_weeks[eval_weeks >= iWeek_used]
  if (!is.null(eval_window))
    eval_weeks <- eval_weeks[eval_weeks - iWeek_used <= as.integer(eval_window)]
  if (length(eval_weeks) == 0L) return(list(scores = na_scores, predictions = empty_preds))

  all_rows <- vector("list", length(eval_weeks))

  # Holt trend-augmented bias tracker (R1) + online season RE (R2)
  # bias_alpha is a deployment-time parameter, not a LOSO-tuned spec param.
  # Use the function argument directly; spec$bias_alpha is ignored here.
  bias_alpha_v    <- as.numeric(bias_alpha)
  bias_alpha_high <- 0.7   # α when ≥2 consecutive same-sign residuals detected
  bias_beta_v     <- 0.0  # level-only confirmed optimal; trend term never tuned
  bias_level      <- list(h1 = 0, h2 = 0)
  bias_trend      <- list(h1 = 0, h2 = 0)
  pred_log        <- list()
  prev_z_ema      <- NA_real_
  prev_resid_pos  <- list(h1 = NA, h2 = NA)
  consec_ss       <- list(h1 = 0L, h2 = 0L)
  peak_passed_prev <- FALSE     # Fix B: post-peak reset
  fr           <- m2_fit$feature_ranges  # Fix A: clamping ranges

  for (i in seq_along(eval_weeks)) {
    ew        <- eval_weeks[i]
    t_since_v <- as.numeric(ew - iWeek_used)

    obs_to_ew <- dplyr::filter(test_allD, .data$weekF <= ew)

    # Fix B: prospective peak detection — reset bias on first post-peak week
    p_to_ew    <- obs_to_ew$y / pmax(obs_to_ew$N, 1L)
    p_ew       <- p_to_ew[obs_to_ew$weekF == ew]
    p_max_prev <- suppressWarnings(max(p_to_ew[obs_to_ew$weekF < ew], na.rm = TRUE))
    peak_now   <- length(p_ew) > 0L && is.finite(p_max_prev) &&
                  p_ew[1L] < 0.85 * p_max_prev
    if (isTRUE(peak_now) && !peak_passed_prev) {
      bias_level       <- list(h1 = 0, h2 = 0)
      bias_trend       <- list(h1 = 0, h2 = 0)
      prev_z_ema       <- NA_real_
      prev_resid_pos   <- list(h1 = NA, h2 = NA)
      consec_ss        <- list(h1 = 0L, h2 = 0L)
      peak_passed_prev <- TRUE
    }

    # Update Holt bias from past predictions whose targets are now observed
    obs_at_ew <- dplyr::filter(test_allD, .data$weekF == ew)
    if (nrow(obs_at_ew) > 0) {
      p_obs_ew  <- obs_at_ew$y[1L] / max(obs_at_ew$N[1L], 1L)
      logit_obs <- stats::qlogis(pmin(pmax(p_obs_ew, 1e-6), 1 - 1e-6))
      for (pl in pred_log) {
        if (pl$target_weekF == ew) {
          # B1 fix: use raw (uncorrected) logit error so the EMA level
          # asymptotes to the true bias B, not B/2.
          # pl$m2_eta_raw is the GAM linear predictor BEFORE bias addition.
          err      <- logit_obs - pl$m2_eta_raw
          hkey     <- paste0("h", pl$h)
          lev_prev <- bias_level[[hkey]]
          trn_prev <- bias_trend[[hkey]]
          # Adaptive α: boost to bias_alpha_high after ≥2 consecutive same-sign
          # raw errors (model "not catching up" per deployment intent).
          cur_pos <- err > 0
          if (!is.na(prev_resid_pos[[hkey]]) && cur_pos == prev_resid_pos[[hkey]]) {
            consec_ss[[hkey]] <- consec_ss[[hkey]] + 1L
          } else {
            consec_ss[[hkey]] <- 0L
          }
          prev_resid_pos[[hkey]] <- cur_pos
          alpha_t <- if (consec_ss[[hkey]] >= 2L) bias_alpha_high else bias_alpha_v
          # Holt level update: level tracks the running bias estimate.
          # lev_new = (lev+trn) + alpha*(err - (lev+trn))
          # At steady state (trn=0, beta=0): lev* = err = B. (B1 fixed)
          lev_new <- (lev_prev + trn_prev) + alpha_t * (err - (lev_prev + trn_prev))
          trn_new <- trn_prev + bias_beta_v * (lev_new - lev_prev - trn_prev)
          bias_level[[hkey]] <- lev_new
          bias_trend[[hkey]] <- trn_new
        }
      }
    }

    if (nrow(obs_to_ew) < 2L) next

    # Compute z_ema from observations up to ew
    obs_arr <- dplyr::arrange(obs_to_ew, .data$weekF) |>
      dplyr::mutate(
        p_now = .data$y / pmax(.data$N, 1L),
        z_now = stats::qlogis(pmin(pmax(.data$p_now, 1e-6), 1 - 1e-6))
      )
    z_ema_v   <- as.numeric(stats::filter(
      alpha_s_global * obs_arr$z_now, filter = 1 - alpha_s_global,
      method = "recursive", init = obs_arr$z_now[1]
    ))
    z_ema_now <- utils::tail(z_ema_v, 1L)
    logN_now  <- log(max(obs_arr$N[obs_arr$weekF == ew], 1L))

    # Fix A: clamp z_ema before dz_ema
    if (!is.null(fr$z_ema))
      z_ema_now <- pmin(fr$z_ema[2L], pmax(fr$z_ema[1L], z_ema_now))
    # B2 fix: divide dz_ema by training SD (parity with prep_stage2_joint).
    dz_sd      <- fr$dz_ema_sd %||% 1
    dz_ema_now <- if (is.na(prev_z_ema)) 0 else (z_ema_now - prev_z_ema) / dz_sd
    prev_z_ema  <- z_ema_now

    # R2: online season RE from observations to this week
    re_hat_loso <- estimate_season_re_online(fit = fit_obj, obs_df = obs_arr,
                                             ex_terms = ex_terms)

    for (h in as.integer(horizons)) {
      m1_row <- dplyr::filter(m1_test_preds,
                              .data$eval_weekF == ew, .data$h == h)
      if (nrow(m1_row) == 0L) next
      m1_p      <- m1_row$m1_p_hat[1L]
      if (is.na(m1_p)) next
      m1_spread <- if ("m1_logit_spread" %in% names(m1_row)) m1_row$m1_logit_spread[1L] else 0
      if (is.na(m1_spread)) m1_spread <- 0

      target_weekF <- as.integer(ew) + h
      obs_target   <- dplyr::filter(test_allD, .data$weekF == target_weekF)
      if (nrow(obs_target) == 0L) next
      y_lead <- as.integer(obs_target$y[1L])
      N_lead <- as.integer(obs_target$N[1L])

      logit_f_eff <- stats::qlogis(pmin(pmax(m1_p, 1e-6), 1 - 1e-6))
      if (!is.null(fr$logit_f_eff))
        logit_f_eff <- pmin(fr$logit_f_eff[2L], pmax(fr$logit_f_eff[1L], logit_f_eff))

      # Holt correction + online RE
      hkey <- paste0("h", h)
      bl   <- bias_level[[hkey]] + h * bias_trend[[hkey]] + re_hat_loso

      pr <- m2_predict_one(
        fit               = fit_obj,
        ew                = ew,
        h                 = h,
        iWeek             = iWeek_used,
        anchorWeek        = anchorWeek,
        logit_f_eff       = logit_f_eff,
        z_ema             = z_ema_now,
        dz_ema            = dz_ema_now,
        logit_spread      = m1_spread,
        logN_now          = logN_now,
        season_label      = NULL,
        ex_terms          = ex_terms,
        include_season_re = FALSE,
        soft_cap_fn       = soft_cap_fn,
        return_ci         = TRUE,
        bias_logit        = bl
      )
      if (is.null(pr)) next

      # Record prediction for future bias updates.
      # m2_eta_raw: GAM linear predictor BEFORE bias (bl) addition.
      # Used by B1 fix: raw error = logit_obs - m2_eta_raw.
      pred_log[[length(pred_log) + 1L]] <- list(
        target_weekF = target_weekF, m2_p = pr$m2_p,
        m2_eta_raw   = stats::qlogis(pmin(pmax(pr$m2_p, 1e-6), 1 - 1e-6)) - bl,
        h            = h
      )

      all_rows[[i]] <- c(all_rows[[i]], list(tibble::tibble(
        season  = test_s,
        weekF   = as.integer(ew),
        lead    = paste0("h", h),
        t_since = t_since_v,
        p_hat   = pr$m2_p,
        p_obs   = y_lead / max(N_lead, 1L),
        y_lead  = y_lead,
        N_lead  = N_lead,
        p_lo    = pr$m2_lo,
        p_hi    = pr$m2_hi
      )))
    }
  }

  preds <- dplyr::bind_rows(unlist(all_rows, recursive = FALSE))
  if (nrow(preds) == 0L) return(list(scores = na_scores, predictions = empty_preds))

  eps     <- 1e-12
  p_hat_v <- pmin(1 - eps, pmax(eps, preds$p_hat))
  p_obs_v <- pmin(1 - eps, pmax(eps, preds$p_obs))
  # Binomial NLL (legacy, N-dependent)
  ll_binom   <- stats::dbinom(preds$y_lead, preds$N_lead, p_hat_v, log = TRUE)
  # Bernoulli NLL (primary tuning metric, N-invariant)
  ll_bern    <- p_obs_v * log(p_hat_v) + (1 - p_obs_v) * log(1 - p_hat_v)
  brier   <- mean((p_hat_v - preds$p_obs)^2, na.rm = TRUE)
  scores  <- tibble::tibble(
    season        = test_s,
    n             = nrow(preds),
    mean_nll      = -mean(ll_binom, na.rm = TRUE),
    bernoulli_nll = -mean(ll_bern,  na.rm = TRUE),
    brier         = brier,
    rmse_p        = sqrt(brier)
  )

  if (isTRUE(verbose))
    message("[m2_eval_fb] ", test_s,
            " | bernoulli_nll=", round(scores$bernoulli_nll, 4),
            " mean_nll=", round(scores$mean_nll, 4),
            " brier=", round(scores$brier, 6),
            " n=", nrow(preds))

  list(scores = scores, predictions = preds)
}


# ---------- 5c. M2 eval with weekly refit (legacy) ----------

#' Evaluate a Stage-2 spec using weekly GAM refit on the test season
#'
#' Variant of \code{nested_loso_m2_eval()} that uses \code{refit_stage2_weekly()}
#' instead of predicting from a frozen fit. For each post-ignition evaluation
#' week on the held-out test season, the GAM is refitted on all training-season
#' aligned data plus the current-season observations accumulated to that week.
#'
#' This matches the deployment semantics of \code{run_m2_forecast(mode="weekly_refit")}.
#'
#' @param allD Full multi-season data frame.
#' @param fold Fold object from \code{nested_loso_build_fold()}.
#' @param flag_args Named list forwarded to \code{flagIgnition()}.
#' @param verbose Logical.
#' @return Same structure as \code{nested_loso_m2_eval()}: list with
#'   \code{scores} and \code{predictions}.
#' @export
nested_loso_m2_eval_weekly_refit <- function(allD,
                                             fold,
                                             m1_test_preds,
                                             spec,
                                             m1_train_preds = NULL,
                                             eval_window   = 12L,
                                             horizons      = c(1L, 2L),
                                             manual_labels = NULL,
                                             flag_args     = list(
                                               p_thresh   = 0.01,
                                               k1         = 0.4,
                                               k_c        = 0.01,
                                               n_consec   = 2L,
                                               min_window = 10L,
                                               w_min      = 21L,
                                               w_max      = 21L,
                                               d2_relax   = -0.01
                                             ),
                                             verbose = TRUE) {
  if (!requireNamespace("dplyr",   quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("tibble",  quietly = TRUE)) stop("Please install tibble.")
  if (!requireNamespace("purrr",   quietly = TRUE)) stop("Please install purrr.")
  `%||%` <- function(x, y) if (is.null(x)) y else x

  test_s <- fold$test_season
  na_scores  <- tibble::tibble(season = test_s, n = NA_integer_,
                               mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_)
  empty_preds <- tibble::tibble(
    season = character(), weekF = integer(), lead = character(),
    t_since = numeric(), p_hat = numeric(), p_obs = numeric(),
    y_lead = integer(), N_lead = integer()
  )

  if (isTRUE(verbose))
    message("[m2_eval_wf] Evaluating weekly-refit M2 on test season ", test_s)

  # --- Build aligned test data via M0 (same as nested_loso_m2_eval_frozen_bias) ---
  test_allD  <- dplyr::filter(allD, .data$season == test_s)
  if (nrow(test_allD) == 0L) return(list(scores = na_scores, predictions = empty_preds))

  # L2 fix: walk-forward derivatives — each week w uses only rows with weekF <= w.
  test_deriv_data <- estimateDerivs_walkforward(test_allD, k = 10L)
  test_outs <- list(test_deriv_data) |>
    purrr::map(~ do.call(flagIgnition,
                         c(list(df = .x, manual_labels = manual_labels), flag_args)))
  aligned_test <- alignIgnition(test_outs)

  iWeek_used <- suppressWarnings(
    min(aligned_test$weekF[aligned_test$phase == 1L], na.rm = TRUE)
  )
  if (!is.finite(iWeek_used)) return(list(scores = na_scores, predictions = empty_preds))

  # Training history (no leakage — test season excluded by fold construction)
  hist_aligned <- fold$aligned_train
  if (!"N" %in% names(hist_aligned))
    hist_aligned$N <- hist_aligned$y + hist_aligned$neg

  # alpha used for z_ema computation in the prediction step.
  # No clamping in LOSO — clamps live only in the deployment pipeline.
  alpha_s_global <- as.numeric(spec$alpha_state %||% 0.25)

  # M1 predictions provide template forecast at each eval week
  if (is.null(m1_test_preds) || nrow(m1_test_preds) == 0L)
    return(list(scores = na_scores, predictions = empty_preds))

  ex_terms   <- spec$exclude_newseason
  if (is.null(ex_terms)) ex_terms <- stage2_exclude_newseason(spec)
  # Season RE handling delegated to m2_predict_one() via include_season_re.
  anchorWeek <- as.integer(spec$anchorWeek %||% fold$ref$anchorWeek %||% 20L)

  eval_weeks <- sort(unique(m1_test_preds$eval_weekF))
  eval_weeks <- eval_weeks[eval_weeks >= iWeek_used]
  if (!is.null(eval_window))
    eval_weeks <- eval_weeks[eval_weeks - iWeek_used <= as.integer(eval_window)]
  if (length(eval_weeks) == 0L) return(list(scores = na_scores, predictions = empty_preds))

  all_rows <- vector("list", length(eval_weeks))

  # Level-only Holt EMA bias tracker
  bias_alpha_loso <- 0.4
  bias_level_loso <- list(h1 = 0, h2 = 0)
  pred_log_loso   <- list()
  prev_z_ema_loso <- NA_real_  # NA triggers safe first-week dz_ema=0

  for (i in seq_along(eval_weeks)) {
    ew        <- eval_weeks[i]
    t_since_v <- as.numeric(ew - iWeek_used)

    # Update bias from past predictions whose targets are now observed
    obs_at_ew <- dplyr::filter(test_allD, .data$weekF == ew)
    if (nrow(obs_at_ew) > 0) {
      p_obs_ew <- obs_at_ew$y[1L] / max(obs_at_ew$N[1L], 1L)
      logit_obs <- stats::qlogis(pmin(pmax(p_obs_ew, 1e-6), 1 - 1e-6))
      for (pl in pred_log_loso) {
        if (pl$target_weekF == ew) {
          logit_pred <- stats::qlogis(pmin(pmax(pl$m2_p, 1e-6), 1 - 1e-6))
          resid <- logit_obs - logit_pred
          hkey <- paste0("h", pl$h)
          bias_level_loso[[hkey]] <- bias_alpha_loso * resid +
            (1 - bias_alpha_loso) * bias_level_loso[[hkey]]
        }
      }
    }
    obs_to_ew <- dplyr::filter(test_allD, .data$weekF <= ew)
    if (nrow(obs_to_ew) < 2L) next

    # Combine M1 train + test predictions for refit: the current-season rows
    # should use M1 predictions (not template-based logit_f_eff) so that
    # training features match the prediction features at line 680.
    m1_test_to_ew <- dplyr::filter(m1_test_preds, .data$eval_weekF <= ew)
    m1_combined   <- if (!is.null(m1_train_preds)) {
      dplyr::bind_rows(m1_train_preds, m1_test_to_ew)
    } else {
      m1_test_to_ew
    }

    refit_out <- tryCatch(
      refit_stage2_weekly(
        current_obs  = obs_to_ew,
        iWeek_used   = iWeek_used,
        hist_data    = hist_aligned,
        template_df  = fold$template_df,
        spec         = spec,
        m1_preds     = m1_combined,
        season_label = test_s,
        verbose      = FALSE
      ),
      error = function(e) {
        if (verbose) message("[m2_eval_wf] refit failed at ew=", ew, ": ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(refit_out)) next
    fit_ew <- refit_out$fit   # extract actual GAM from train_stage2_joint() list

    soft_cap_fn <- make_soft_cap_fn(fit_ew)
    lev_lead    <- levels(fit_ew$model$lead)
    lev_seas    <- levels(fit_ew$model$season)

    obs_arr <- dplyr::arrange(obs_to_ew, .data$weekF) |>
      dplyr::mutate(
        p_now = .data$y / pmax(.data$N, 1L),
        z_now = stats::qlogis(pmin(pmax(.data$p_now, 1e-6), 1 - 1e-6))
      )
    z_ema_v   <- as.numeric(stats::filter(
      alpha_s_global * obs_arr$z_now, filter = 1 - alpha_s_global,
      method = "recursive", init = obs_arr$z_now[1]
    ))
    # No clamping here — LOSO evaluation should match v4 baseline exactly except
    # for (1) weekly refit and (2) soft cap.  Clamping lives only in the
    # deployment path (pipeline_runtime.R) where it guards against OOD input.
    z_ema_now <- utils::tail(z_ema_v, 1L)
    logN_now  <- log(max(obs_arr$N[obs_arr$weekF == ew], 1L))

    dz_ema_now_loso <- if (is.na(prev_z_ema_loso)) 0 else z_ema_now - prev_z_ema_loso
    prev_z_ema_loso <- z_ema_now

    for (h in as.integer(horizons)) {
      m1_row <- dplyr::filter(m1_test_preds,
                              .data$eval_weekF == ew, .data$h == h)
      if (nrow(m1_row) == 0L) next
      m1_p      <- m1_row$m1_p_hat[1L]
      if (is.na(m1_p)) next
      m1_spread <- if ("m1_logit_spread" %in% names(m1_row)) m1_row$m1_logit_spread[1L] else 0
      if (is.na(m1_spread)) m1_spread <- 0

      target_weekF <- as.integer(ew) + h
      obs_target   <- dplyr::filter(test_allD, .data$weekF == target_weekF)
      if (nrow(obs_target) == 0L) next
      y_lead <- as.integer(obs_target$y[1L])
      N_lead <- as.integer(obs_target$N[1L])

      logit_f_eff <- stats::qlogis(pmin(pmax(m1_p, 1e-6), 1 - 1e-6))

      # Weekly refit: test season is in the refit model's training data,
      # so include the season RE.
      is_refit <- test_s %in% lev_seas

      # Apply running bias correction: level-only
      hkey_loso <- paste0("h", h)
      bl <- bias_level_loso[[hkey_loso]]

      pr <- m2_predict_one(
        fit               = fit_ew,
        ew                = ew,
        h                 = h,
        iWeek             = iWeek_used,
        anchorWeek        = anchorWeek,
        logit_f_eff       = logit_f_eff,
        z_ema             = z_ema_now,
        dz_ema            = dz_ema_now_loso,
        logit_spread      = m1_spread,
        logN_now          = logN_now,
        season_label      = if (is_refit) test_s else NULL,
        ex_terms          = ex_terms,
        include_season_re = is_refit,
        soft_cap_fn       = soft_cap_fn,
        return_ci         = FALSE,
        bias_logit        = bl
      )
      if (is.null(pr)) next

      # Record prediction for future bias updates
      pred_log_loso[[length(pred_log_loso) + 1L]] <- list(
        target_weekF = target_weekF, m2_p = pr$m2_p, h = h
      )

      all_rows[[i]] <- c(all_rows[[i]], list(tibble::tibble(
        season  = test_s,
        weekF   = as.integer(ew),
        lead    = paste0("h", h),
        t_since = t_since_v,
        p_hat   = pr$m2_p,
        p_obs   = y_lead / max(N_lead, 1L),
        y_lead  = y_lead,
        N_lead  = N_lead
      )))
    }
  }

  preds <- dplyr::bind_rows(unlist(all_rows, recursive = FALSE))
  if (nrow(preds) == 0L) return(list(scores = na_scores, predictions = empty_preds))

  eps     <- 1e-12
  p_hat_v <- pmin(1 - eps, pmax(eps, preds$p_hat))
  ll      <- stats::dbinom(preds$y_lead, preds$N_lead, p_hat_v, log = TRUE)
  brier   <- mean((p_hat_v - preds$p_obs)^2, na.rm = TRUE)
  scores  <- tibble::tibble(
    season   = test_s,
    n        = nrow(preds),
    mean_nll = -mean(ll, na.rm = TRUE),
    brier    = brier,
    rmse_p   = sqrt(brier)
  )

  if (isTRUE(verbose))
    message("[m2_eval_wf] ", test_s,
            " | mean_nll=", round(scores$mean_nll, 4),
            " brier=", round(scores$brier, 6),
            " n=", nrow(preds))

  list(scores = scores, predictions = preds)
}
