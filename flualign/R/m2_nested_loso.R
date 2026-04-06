# ============================================================
# Nested M1 → M2 LOSO: Composable helpers
#
# Refactors loso_m1_m2_joint() (pipeline_bridge.R) into small,
# testable helper functions. Each maps to a block of the
# original monolithic function.
#
# No existing functions are modified.
# ============================================================

# ---------- 1. Build one LOSO fold (M1 training) ----------

#' Build a single LOSO fold: training alignment + reference curve
#'
#' For a held-out test season, filters to training seasons, runs the
#' M0 detection pipeline (derivatives → ignition → alignment), fits
#' the reference curve, and learns alignment hyperparams. Everything
#' needed to run M1 on this fold.
#'
#' @param allD Data frame with all seasons (columns: season, week, y, neg, …).
#' @param test_season Character scalar — the held-out season.
#' @param exclude_seasons Character vector of seasons to drop entirely
#'   (before fold splitting).
#' @param k_deriv Integer; basis dimension for \code{estimateDerivs()}.
#' @param k_ref Integer; basis dimension for \code{estimateRef()}.
#' @param n_weeks Integer; period for reference GAM (default 52).
#' @param manual_labels Optional named list of manual ignition labels.
#' @param flag_args Named list of arguments forwarded to \code{flagIgnition()}.
#' @param verbose Logical; print progress messages.
#'
#' @return A named list with components:
#'   \describe{
#'     \item{ref}{Output of \code{estimateRef()} on training seasons.}
#'     \item{hyper}{Output of \code{learn_alignment_hyperparams()}.}
#'     \item{aligned_train}{Aligned training data (output of \code{alignIgnition()}).}
#'     \item{template_df}{Two-column tibble (newWeek, fit) from the per-fold ref curve.}
#'     \item{train_seasons}{Character vector of training season labels.}
#'     \item{test_season}{The held-out season label (echoed back).}
#'   }
#'
#' @export
nested_loso_build_fold <- function(allD,
                                   test_season,
                                   exclude_seasons = NULL,
                                   k_deriv         = 10L,
                                   k_ref           = 25L,
                                   n_weeks         = 52L,
                                   ref_method      = "fs",
                                   manual_labels   = NULL,
                                   flag_args       = list(
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

  all_seasons <- sort(unique(as.character(allD$season)))
  if (!is.null(exclude_seasons)) {
    allD        <- dplyr::filter(allD, !.data$season %in% exclude_seasons)
    all_seasons <- setdiff(all_seasons, exclude_seasons)
  }
  stopifnot(test_season %in% all_seasons)

  tr_seasons <- setdiff(all_seasons, test_season)
  if (length(tr_seasons) < 2L)
    stop("Need >= 2 training seasons; got ", length(tr_seasons))

  if (isTRUE(verbose))
    message("[build_fold] test=", test_season,
            " | training on ", length(tr_seasons), " seasons")

  # M0 pipeline on training data

  train_allD <- dplyr::filter(allD, .data$season %in% tr_seasons)
  res_deriv  <- estimateDerivs(train_allD, k = k_deriv)

  train_outs <- res_deriv$data %>%
    dplyr::group_by(.data$season) %>%
    dplyr::group_split(.keep = TRUE) %>%
    purrr::map(~ do.call(flagIgnition,
                         c(list(df = .x, manual_labels = manual_labels),
                           flag_args)))

  aligned_train <- alignIgnition(train_outs)

  # Reference curve (leakage-free: test season excluded)
  ref   <- estimateRef(alignedD = aligned_train, exSeason = character(0),
                       k = k_ref, n_weeks = n_weeks, method = ref_method)
  hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)

  # Per-fold template
  template_df <- ref$pred_df[, c("newWeek", "fit")]

  list(
    ref            = ref,
    hyper          = hyper,
    aligned_train  = aligned_train,
    template_df    = template_df,
    train_seasons  = tr_seasons,
    test_season    = test_season
  )
}


# ---------- 2. M1 walk-forward on training seasons ----------

#' Run M1 walk-forward predictions on training seasons
#'
#' Generates M1 stacking features for all training seasons in a fold.
#' Calls \code{m1_walkforward_multi()} using the fold's reference curve
#' and hyperparams.
#'
#' @param allD Full multi-season data frame.
#' @param fold Output of \code{nested_loso_build_fold()}.
#' @param params M0 detection parameters.
#' @param horizons Integer vector of forecast horizons (default \code{c(1L, 2L)}).
#' @param allow_scale Passed to \code{m1_walkforward_multi()}.
#' @param use_ci Logical; peak CI control (default TRUE).
#' @param buffer_weeks Integer; peak buffer (default 0L).
#' @param min_obs Integer; minimum rows for alignment (default 4L).
#' @param curvature_ratio Numeric; delta curvature gate (default 1.0).
#' @param parallel Logical; run M1 seasons in parallel (default TRUE).
#' @param verbose Logical; print progress.
#'
#' @return Tibble of M1 walk-forward predictions for training seasons
#'   (columns: season, eval_weekF, target_weekF, h, m1_p_hat, …).
#'   Can be empty if no ignition detected.
#'
#' @export
nested_loso_m1_train <- function(allD,
                                 fold,
                                 params,
                                 horizons           = c(1L, 2L),
                                 allow_scale        = NULL,
                                 use_ci             = TRUE,
                                 buffer_weeks       = 0L,
                                 min_obs            = 4L,
                                 curvature_ratio    = 1.0,
                                 temperature        = 0.25,
                                 rise_weight        = 1.0,
                                 trough_weight      = 0.1,
                                 peak_decay         = 0.3,
                                 slope_weight       = 0.5,
                                 slope_window       = 4L,
                                 dynamic_temp       = TRUE,
                                 dynamic_temp_pivot = 10L,
                                 top_k              = NULL,
                                 blend_alpha        = 1.0,
                                 parallel           = TRUE,
                                 verbose            = TRUE) {

  if (isTRUE(verbose))
    message("[m1_train] Running M1 walk-forward on ",
            length(fold$train_seasons), " training seasons")

  m1_walkforward_multi(
    allD               = allD,
    ref                = fold$ref,
    hyper              = fold$hyper,
    params             = params,
    seasons            = fold$train_seasons,
    horizons           = horizons,
    allow_scale        = allow_scale,
    use_ci             = use_ci,
    buffer_weeks       = buffer_weeks,
    min_obs            = min_obs,
    curvature_ratio    = curvature_ratio,
    temperature        = temperature,
    rise_weight        = rise_weight,
    trough_weight      = trough_weight,
    peak_decay         = peak_decay,
    slope_weight       = slope_weight,
    slope_window       = slope_window,
    dynamic_temp       = dynamic_temp,
    dynamic_temp_pivot = dynamic_temp_pivot,
    top_k              = top_k,
    blend_alpha        = blend_alpha,
    parallel           = parallel,
    verbose            = FALSE
  )
}


# ---------- 3. Train M2 on one fold ----------

#' Train M2 model on one LOSO fold
#'
#' Prepares aligned training data with prospective derivatives, then
#' trains the M2 GAM using the fold's per-fold \code{template_df}
#' (leakage-free reference curve). Optionally injects M1 stacking
#' predictions.
#'
#' @param fold Output of \code{nested_loso_build_fold()}.
#' @param m1_train_preds M1 walk-forward predictions for training seasons
#'   (output of \code{nested_loso_m1_train()}), or \code{NULL} to skip stacking.
#' @param spec M2 hyperparameter spec object (as used by \code{train_stage2_joint()}).
#' @param method GAM fitting method (default \code{"REML"}).
#' @param verbose Logical; print progress.
#'
#' @return Output of \code{train_stage2_joint()} (list with \code{fit},
#'   \code{train_data}, …), or \code{NULL} if training fails.
#'
#' @export
nested_loso_m2_train <- function(fold,
                                 m1_train_preds = NULL,
                                 spec,
                                 method  = "REML",
                                 verbose = TRUE) {

  if (isTRUE(verbose))
    message("[m2_train] Training M2 on fold (test=", fold$test_season, ")")

  # Prepare aligned training data with prospective derivatives
  alignedD_prosp <- add_prospective_derivs_link(fold$aligned_train)
  if (!"N" %in% names(alignedD_prosp))
    alignedD_prosp$N <- alignedD_prosp$y + alignedD_prosp$neg

  # Normalize empty M1 predictions to NULL
  m1_preds_use <- if (!is.null(m1_train_preds) && nrow(m1_train_preds) > 0)
    m1_train_preds else NULL

  tryCatch(
    train_stage2_joint(
      dat         = alignedD_prosp,
      template_df = fold$template_df,
      spec        = spec,
      method      = method,
      m1_preds    = m1_preds_use,
      verbose     = FALSE
    ),
    error = function(e) {
      warning("[m2_train] Failed for test season ", fold$test_season,
              ": ", e$message)
      NULL
    }
  )
}


# ---------- 4. M1 walk-forward on test season ----------

#' Run M1 walk-forward on the held-out test season
#'
#' Generates M1 stacking features for the test season using the fold's
#' reference curve (which was fitted without the test season).
#'
#' @param allD Full multi-season data frame.
#' @param fold Output of \code{nested_loso_build_fold()}.
#' @param params M0 detection parameters.
#' @param horizons Integer vector of forecast horizons (default \code{c(1L, 2L)}).
#' @param allow_scale Passed to \code{m1_walkforward_predictions()}.
#' @param use_ci Logical; peak CI control (default TRUE).
#' @param buffer_weeks Integer; peak buffer (default 0L).
#' @param min_obs Integer; minimum rows for alignment (default 4L).
#' @param curvature_ratio Numeric; delta curvature gate (default 1.0).
#' @param verbose Logical; print progress.
#'
#' @return Tibble of M1 walk-forward predictions for the test season,
#'   or a zero-row tibble if no ignition detected.
#'
#' @export
nested_loso_m1_test <- function(allD,
                                fold,
                                params,
                                horizons           = c(1L, 2L),
                                allow_scale        = NULL,
                                use_ci             = TRUE,
                                buffer_weeks       = 0L,
                                min_obs            = 4L,
                                curvature_ratio    = 1.0,
                                temperature        = 0.25,
                                rise_weight        = 1.0,
                                trough_weight      = 0.1,
                                peak_decay         = 0.3,
                                slope_weight       = 0.5,
                                slope_window       = 4L,
                                dynamic_temp       = TRUE,
                                dynamic_temp_pivot = 10L,
                                top_k              = NULL,
                                blend_alpha        = 1.0,
                                verbose            = TRUE) {

  if (isTRUE(verbose))
    message("[m1_test] Running M1 walk-forward on test season ", fold$test_season)

  seasonD <- dplyr::filter(allD, .data$season == fold$test_season)

  m1_walkforward_predictions(
    seasonD            = seasonD,
    ref                = fold$ref,
    hyper              = fold$hyper,
    params             = params,
    horizons           = horizons,
    allow_scale        = allow_scale,
    use_ci             = use_ci,
    buffer_weeks       = buffer_weeks,
    min_obs            = min_obs,
    curvature_ratio    = curvature_ratio,
    temperature        = temperature,
    rise_weight        = rise_weight,
    trough_weight      = trough_weight,
    peak_decay         = peak_decay,
    slope_weight       = slope_weight,
    slope_window       = slope_window,
    dynamic_temp       = dynamic_temp,
    dynamic_temp_pivot = dynamic_temp_pivot,
    top_k              = top_k,
    blend_alpha        = blend_alpha
  )
}


# ---------- 5. Evaluate M2 on test season ----------

#' Evaluate M2 on the held-out test season
#'
#' Builds aligned test data (running M0 pipeline on the test season),
#' prepares M2 features with the fold's per-fold \code{template_df},
#' scores predictions, and extracts diagnostics.
#'
#' @param allD Full multi-season data frame.
#' @param fold Output of \code{nested_loso_build_fold()}.
#' @param m2_fit Output of \code{nested_loso_m2_train()} (the trained M2 GAM).
#' @param m1_test_preds M1 test predictions from \code{nested_loso_m1_test()}.
#' @param spec M2 hyperparameter spec object.
#' @param eval_window Integer; maximum weeks post-ignition to evaluate
#'   (default 12L).
#' @param k_deriv Integer; basis dimension for \code{estimateDerivs()}.
#' @param manual_labels Optional manual ignition labels.
#' @param flag_args Named list forwarded to \code{flagIgnition()}.
#' @param verbose Logical; print progress.
#'
#' @return A named list:
#'   \describe{
#'     \item{scores}{One-row tibble with season, n, mean_nll, brier, rmse_p.}
#'     \item{predictions}{Tibble with per-observation predictions
#'       (season, weekF, lead, t_since, p_hat, p_obs, y_lead, N_lead).}
#'   }
#'   On failure, scores contain \code{NA} and predictions is empty.
#'
#' @export
nested_loso_m2_eval <- function(allD,
                                fold,
                                m2_fit,
                                m1_test_preds,
                                spec,
                                eval_window   = 12L,
                                k_deriv       = 10L,
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

  test_s <- fold$test_season
  na_scores <- tibble::tibble(
    season = test_s, n = NA_integer_,
    mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_
  )
  empty_preds <- tibble::tibble(
    season = character(), weekF = integer(), lead = character(),
    t_since = numeric(), p_hat = numeric(), p_obs = numeric(),
    y_lead = integer(), N_lead = integer()
  )

  if (isTRUE(verbose))
    message("[m2_eval] Evaluating M2 on test season ", test_s)

  # --- Build aligned test data via M0 pipeline ---
  test_allD <- dplyr::filter(allD, .data$season == test_s)
  test_deriv <- estimateDerivs(test_allD, k = k_deriv)

  test_outs <- test_deriv$data %>%
    dplyr::group_by(.data$season) %>%
    dplyr::group_split(.keep = TRUE) %>%
    purrr::map(~ do.call(flagIgnition,
                         c(list(df = .x, manual_labels = manual_labels),
                           flag_args)))

  aligned_test <- alignIgnition(test_outs)
  aligned_test_prosp <- add_prospective_derivs_link(aligned_test)
  if (!"N" %in% names(aligned_test_prosp))
    aligned_test_prosp$N <- aligned_test_prosp$y + aligned_test_prosp$neg

  # --- Prep M2 test data with per-fold template ---
  # Normalize empty M1 predictions to NULL
  m1_preds_use <- if (!is.null(m1_test_preds) && nrow(m1_test_preds) > 0)
    m1_test_preds else NULL

  d_test <- tryCatch(
    prep_stage2_joint(
      dat           = aligned_test_prosp,
      best_mean_nll = spec$best_row,
      template_df   = fold$template_df,
      leads         = spec$leads %||% c(1L, 2L),
      pre_buffer    = as.integer(spec$pre_buffer %||% 0L),
      alpha_state   = as.numeric(spec$alpha_state %||% 0.30),
      m1_preds      = m1_preds_use,
      verbose       = FALSE
    ),
    error = function(e) NULL
  )

  if (is.null(d_test) || nrow(d_test) == 0)
    return(list(scores = na_scores, predictions = empty_preds))

  # --- Restrict to post-ignition eval window ---
  d_test <- d_test[d_test$post_ign, , drop = FALSE]
  if (!is.null(eval_window) && "t_since" %in% names(d_test)) {
    d_test <- d_test[is.finite(d_test$t_since) &
                       d_test$t_since >= 0 &
                       d_test$t_since <= as.integer(eval_window), , drop = FALSE]
  }

  if (nrow(d_test) == 0)
    return(list(scores = na_scores, predictions = empty_preds))

  # --- Soft positivity ceiling (matches deployment-time cap) ---
  # Derived from the training data of m2_fit so evaluation is consistent
  # with what run_m2_forecast() applies at prediction time.
  fit_obj     <- m2_fit$fit
  soft_cap_fn <- make_soft_cap_fn(fit_obj)

  # --- Score ---
  ex_terms <- spec$exclude_newseason
  if (is.null(ex_terms)) ex_terms <- stage2_exclude_newseason(spec)

  scores <- score_stage2_metrics(
    fit               = fit_obj,
    d_test            = d_test,
    exclude_season_re = TRUE,
    exclude_terms     = ex_terms,
    lambda_w          = 0,
    eval_window       = eval_window,
    soft_cap_fn       = soft_cap_fn
  )

  # --- Extract predictions ---
  # Align factor levels for prediction
  if ("lead" %in% names(d_test) && is.factor(fit_obj$model$lead))
    d_test$lead <- factor(as.character(d_test$lead),
                          levels = levels(fit_obj$model$lead))
  if ("season" %in% names(d_test) && is.factor(fit_obj$model$season)) {
    d_test$season <- factor(as.character(d_test$season),
                            levels = levels(fit_obj$model$season))
    if (anyNA(d_test$season))
      d_test$season[is.na(d_test$season)] <- levels(fit_obj$model$season)[1]
  }
  if ("season_h" %in% names(d_test) && is.factor(fit_obj$model$season_h)) {
    d_test$season_h <- factor(as.character(d_test$season_h),
                              levels = levels(fit_obj$model$season_h))
    if (anyNA(d_test$season_h))
      d_test$season_h[is.na(d_test$season_h)] <- levels(fit_obj$model$season_h)[1]
  }

  p_hat <- as.numeric(stats::predict(fit_obj, newdata = d_test,
                                     type = "response", exclude = ex_terms))
  p_hat <- soft_cap_fn(p_hat)
  p_hat <- pmin(1 - 1e-12, pmax(1e-12, p_hat))

  preds <- tibble::tibble(
    season  = test_s,
    weekF   = d_test$weekF,
    lead    = as.character(d_test$lead),
    t_since = d_test$t_since,
    p_hat   = p_hat,
    p_obs   = d_test$y_lead / d_test$N_lead,
    y_lead  = d_test$y_lead,
    N_lead  = d_test$N_lead
  )

  if (isTRUE(verbose))
    message("[m2_eval] ", test_s,
            " | mean_nll=", round(scores$mean_nll, 4),
            " brier=", round(scores$brier, 6),
            " rmse_p=", round(scores$rmse_p, 4))

  list(
    scores      = tibble::tibble(
      season   = test_s,
      n        = nrow(d_test),
      mean_nll = scores$mean_nll,
      brier    = scores$brier,
      rmse_p   = scores$rmse_p
    ),
    predictions = preds
  )
}


# ---------- 5b. M2 eval with weekly refit ----------

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
#' @param m1_test_preds Output of \code{nested_loso_m1_test()}: tibble with
#'   columns \code{eval_weekF}, \code{target_weekF}, \code{h}, \code{m1_p_hat},
#'   \code{m1_tau}.
#' @param spec Stage-2 spec from \code{stage2_make_spec()}.
#' @param eval_window Integer; max t_since to evaluate (default 12L).
#' @param horizons Integer vector of forecast horizons (default \code{c(1L, 2L)}).
#' @param k_deriv Integer; basis dim for M0 derivative estimation (default 10L).
#' @param manual_labels Optional named integer vector of manual ignition labels.
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
                                             k_deriv       = 10L,
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

  # --- Build aligned test data via M0 (same as nested_loso_m2_eval) ---
  test_allD  <- dplyr::filter(allD, .data$season == test_s)
  if (nrow(test_allD) == 0L) return(list(scores = na_scores, predictions = empty_preds))

  test_deriv <- estimateDerivs(test_allD, k = k_deriv)
  test_outs  <- test_deriv$data %>%
    dplyr::group_by(.data$season) %>%
    dplyr::group_split(.keep = TRUE) %>%
    purrr::map(~ do.call(flagIgnition,
                         c(list(df = .x, manual_labels = manual_labels), flag_args)))
  aligned_test <- alignIgnition(test_outs)

  iWeek_used <- suppressWarnings(
    min(aligned_test$weekF[aligned_test$phase == 1L], na.rm = TRUE)
  )
  if (!is.finite(iWeek_used)) return(list(scores = na_scores, predictions = empty_preds))

  # Training history (no leakage — test season excluded by fold construction)
  hist_aligned <- add_prospective_derivs_link(fold$aligned_train)
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
  anchorWeek <- as.integer(spec$anchorWeek %||% fold$ref$anchorWeek %||% 20L)

  eval_weeks <- sort(unique(m1_test_preds$eval_weekF))
  eval_weeks <- eval_weeks[eval_weeks >= iWeek_used]
  if (!is.null(eval_window))
    eval_weeks <- eval_weeks[eval_weeks - iWeek_used <= as.integer(eval_window)]
  if (length(eval_weeks) == 0L) return(list(scores = na_scores, predictions = empty_preds))

  all_rows <- vector("list", length(eval_weeks))

  for (i in seq_along(eval_weeks)) {
    ew        <- eval_weeks[i]
    t_since_v <- as.numeric(ew - iWeek_used)
    obs_to_ew <- dplyr::filter(test_allD, .data$weekF <= ew)
    if (nrow(obs_to_ew) < 2L) next

    refit_out <- tryCatch(
      refit_stage2_weekly(
        current_obs  = obs_to_ew,
        iWeek_used   = iWeek_used,
        hist_data    = hist_aligned,
        template_df  = fold$template_df,
        spec         = spec,
        m1_preds     = m1_train_preds,
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

    # Compute prospective d1/d2 from data up to eval week (matches v4 derivs)
    d_deriv_ew <- tryCatch(
      add_prospective_derivs_link(
        dplyr::transmute(obs_arr, season = test_s, weekF = .data$weekF,
                         y = .data$y, neg = .data$N - .data$y),
        k = 5L, eps = 1e-6, min_obs = 4L
      ),
      error = function(e) NULL
    )
    d_at_ew <- if (!is.null(d_deriv_ew)) dplyr::filter(d_deriv_ew, .data$weekF == ew) else NULL
    d1_now_ew <- if (!is.null(d_at_ew) && nrow(d_at_ew) > 0 && !is.na(d_at_ew$d1_link[1L]))
      d_at_ew$d1_link[1L] else 0
    d2_now_ew <- if (!is.null(d_at_ew) && nrow(d_at_ew) > 0 && !is.na(d_at_ew$d2_link[1L]))
      d_at_ew$d2_link[1L] else 0

    for (h in as.integer(horizons)) {
      m1_row <- dplyr::filter(m1_test_preds,
                              .data$eval_weekF == ew, .data$h == h)
      if (nrow(m1_row) == 0L) next
      m1_p <- m1_row$m1_p_hat[1L]
      if (is.na(m1_p)) next

      target_weekF <- as.integer(ew) + h
      obs_target   <- dplyr::filter(test_allD, .data$weekF == target_weekF)
      if (nrow(obs_target) == 0L) next
      y_lead <- as.integer(obs_target$y[1L])
      N_lead <- as.integer(obs_target$N[1L])

      logit_f_eff <- stats::qlogis(pmin(pmax(m1_p, 1e-6), 1 - 1e-6))

      nd <- tibble::tibble(
        weekF       = as.integer(ew),
        newWeek     = as.integer(ew) - as.integer(iWeek_used) + anchorWeek,
        lead        = factor(paste0("h", h), levels = lev_lead),
        season      = factor(lev_seas[1L], levels = lev_seas),
        logit_f_eff = logit_f_eff,
        z_ema       = z_ema_now,
        logN_now    = logN_now,
        d1_now      = d1_now_ew,
        d2_now      = d2_now_ew,
        t_since     = t_since_v,
        post_ign    = TRUE
      )
      if ("season_h" %in% names(fit_ew$model)) {
        lev_sh <- levels(fit_ew$model$season_h)
        nd$season_h <- factor(lev_sh[1L], levels = lev_sh)
      }

      pr <- tryCatch(
        stats::predict(fit_ew, newdata = nd, type = "response", exclude = ex_terms),
        error = function(e) NULL
      )
      if (is.null(pr)) next

      p_hat <- soft_cap_fn(pmin(1 - 1e-12, pmax(1e-12, as.numeric(pr))))

      all_rows[[i]] <- c(all_rows[[i]], list(tibble::tibble(
        season  = test_s,
        weekF   = as.integer(ew),
        lead    = paste0("h", h),
        t_since = t_since_v,
        p_hat   = p_hat,
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


# ---------- 6. Orchestrate one fold ----------

#' Run a complete nested LOSO fold
#'
#' Orchestrates the five steps for a single held-out season:
#' build fold → M1 train → M2 train → M1 test → M2 eval.
#' Returns aggregated results; handles errors gracefully.
#'
#' @param allD Full multi-season data frame.
#' @param test_season Character scalar — the held-out season.
#' @param params M0 detection parameters.
#' @param spec M2 hyperparameter spec object.
#' @param exclude_seasons Character vector of seasons to exclude entirely.
#' @param horizons Integer vector of forecast horizons (default \code{c(1L, 2L)}).
#' @param eval_window Integer; max weeks post-ignition (default 12L).
#' @param k_deriv Integer; basis dim for derivatives (default 10L).
#' @param k_ref Integer; basis dim for reference curve (default 10L).
#' @param n_weeks Integer; reference curve period (default 52L).
#' @param manual_labels Optional manual ignition labels.
#' @param flag_args Named list forwarded to \code{flagIgnition()}.
#' @param allow_scale Passed to M1 walk-forward.
#' @param use_ci Logical; peak CI control (default TRUE).
#' @param buffer_weeks Integer; peak buffer (default 0L).
#' @param min_obs Integer; minimum rows for alignment (default 4L).
#' @param curvature_ratio Numeric; delta curvature gate (default 1.0).
#' @param method GAM fitting method (default \code{"REML"}).
#' @param parallel Logical; parallelize M1 walk-forward (default TRUE).
#' @param verbose Logical; print progress.
#'
#' @return A named list:
#'   \describe{
#'     \item{scores}{One-row tibble of metrics.}
#'     \item{predictions}{Tibble of per-observation predictions.}
#'     \item{m1_preds}{M1 test-season predictions tibble.}
#'     \item{fold}{The fold object from \code{nested_loso_build_fold()}.}
#'   }
#'
#' @export
nested_loso_run_fold <- function(allD,
                                 test_season,
                                 params,
                                 spec,
                                 exclude_seasons    = NULL,
                                 horizons           = c(1L, 2L),
                                 eval_window        = 12L,
                                 k_deriv            = 10L,
                                 k_ref              = 25L,
                                 n_weeks            = 52L,
                                 ref_method         = "fs",
                                 manual_labels      = NULL,
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
                                 allow_scale        = NULL,
                                 use_ci             = TRUE,
                                 buffer_weeks       = 0L,
                                 min_obs            = 4L,
                                 curvature_ratio    = 1.0,
                                 temperature        = 0.25,
                                 rise_weight        = 1.0,
                                 trough_weight      = 0.1,
                                 peak_decay         = 0.3,
                                 slope_weight       = 0.5,
                                 slope_window       = 4L,
                                 dynamic_temp       = TRUE,
                                 dynamic_temp_pivot = 10L,
                                 top_k              = NULL,
                                 blend_alpha        = 1.0,
                                 method             = "REML",
                                 parallel           = TRUE,
                                 skip_m1            = FALSE,
                                 verbose            = TRUE) {

  na_scores <- tibble::tibble(
    season = test_season, n = NA_integer_,
    mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_
  )

  # Step 1: Build fold
  fold <- nested_loso_build_fold(
    allD            = allD,
    test_season     = test_season,
    exclude_seasons = exclude_seasons,
    k_deriv         = k_deriv,
    k_ref           = k_ref,
    n_weeks         = n_weeks,
    ref_method      = ref_method,
    manual_labels   = manual_labels,
    flag_args       = flag_args,
    verbose         = verbose
  )

  # Step 2: M1 walk-forward on training seasons (skip if skip_m1)
  if (isTRUE(skip_m1)) {
    m1_train_preds <- NULL
    if (isTRUE(verbose)) message("[run_fold] Skipping M1 walk-forward (skip_m1=TRUE)")
  } else {
    m1_train_preds <- nested_loso_m1_train(
      allD               = allD,
      fold               = fold,
      params             = params,
      horizons           = horizons,
      allow_scale        = allow_scale,
      use_ci             = use_ci,
      buffer_weeks       = buffer_weeks,
      min_obs            = min_obs,
      curvature_ratio    = curvature_ratio,
      temperature        = temperature,
      rise_weight        = rise_weight,
      trough_weight      = trough_weight,
      peak_decay         = peak_decay,
      slope_weight       = slope_weight,
      slope_window       = slope_window,
      dynamic_temp       = dynamic_temp,
      dynamic_temp_pivot = dynamic_temp_pivot,
      top_k              = top_k,
      blend_alpha        = blend_alpha,
      parallel           = parallel,
      verbose            = verbose
    )
  }

  if (isTRUE(verbose))
    message("[run_fold] M1 training preds: ", nrow(m1_train_preds), " rows")

  # Step 3: Train M2
  m2_fit <- nested_loso_m2_train(
    fold           = fold,
    m1_train_preds = m1_train_preds,
    spec           = spec,
    method         = method,
    verbose        = verbose
  )

  if (is.null(m2_fit)) {
    return(list(
      scores      = na_scores,
      predictions = tibble::tibble(),
      m1_preds    = tibble::tibble(),
      fold        = fold
    ))
  }

  # Step 4: M1 walk-forward on test season (skip if skip_m1)
  if (isTRUE(skip_m1)) {
    m1_test_preds <- NULL
  } else {
    m1_test_preds <- nested_loso_m1_test(
      allD               = allD,
      fold               = fold,
      params             = params,
      horizons           = horizons,
      allow_scale        = allow_scale,
      use_ci             = use_ci,
      buffer_weeks       = buffer_weeks,
      min_obs            = min_obs,
      curvature_ratio    = curvature_ratio,
      temperature        = temperature,
      rise_weight        = rise_weight,
      trough_weight      = trough_weight,
      peak_decay         = peak_decay,
      slope_weight       = slope_weight,
      slope_window       = slope_window,
      dynamic_temp       = dynamic_temp,
      dynamic_temp_pivot = dynamic_temp_pivot,
      top_k              = top_k,
      blend_alpha        = blend_alpha,
      verbose            = verbose
    )

    if (nrow(m1_test_preds) == 0) {
      if (isTRUE(verbose))
        message("[run_fold] No M1 predictions for test season (no ignition?)")
      return(list(
        scores      = na_scores,
        predictions = tibble::tibble(),
        m1_preds    = m1_test_preds,
        fold        = fold
      ))
    }
  }

  # Step 5: Evaluate M2
  eval_out <- nested_loso_m2_eval(
    allD          = allD,
    fold          = fold,
    m2_fit        = m2_fit,
    m1_test_preds = m1_test_preds,
    spec          = spec,
    eval_window   = eval_window,
    k_deriv       = k_deriv,
    manual_labels = manual_labels,
    flag_args     = flag_args,
    verbose       = verbose
  )

  list(
    scores      = eval_out$scores,
    predictions = eval_out$predictions,
    m1_preds    = m1_test_preds,
    fold        = fold
  )
}


# ---------- 7. Full nested LOSO cross-validation ----------

#' Nested M1 → M2 leave-one-season-out cross-validation
#'
#' For each held-out test season, builds a leakage-free reference curve
#' on training seasons, runs M1 walk-forward to generate stacking
#' features, trains M2, and evaluates on the test season. This is the
#' composable replacement for \code{loso_m1_m2_joint()} in
#' \code{pipeline_bridge.R}.
#'
#' @param allD Data frame with all seasons.
#' @param params M0 detection parameters.
#' @param spec M2 hyperparameter spec object.
#' @param test_seasons Character vector of seasons to hold out.
#'   If \code{NULL}, every season is tested.
#' @param exclude_seasons Character vector of seasons to exclude entirely.
#' @param horizons Integer vector of forecast horizons (default \code{c(1L, 2L)}).
#' @param eval_window Integer; max weeks post-ignition (default 12L).
#' @param k_deriv Integer; basis dim for derivatives (default 10L).
#' @param k_ref Integer; basis dim for reference curve (default 10L).
#' @param n_weeks Integer; reference curve period (default 52L).
#' @param manual_labels Optional manual ignition labels.
#' @param flag_args Named list forwarded to \code{flagIgnition()}.
#' @param allow_scale Passed to M1 walk-forward.
#' @param use_ci Logical; peak CI control (default TRUE).
#' @param buffer_weeks Integer; peak buffer (default 0L).
#' @param min_obs Integer; minimum rows for alignment (default 4L).
#' @param curvature_ratio Numeric; delta curvature gate (default 1.0).
#' @param method GAM fitting method (default \code{"REML"}).
#' @param n_cores Integer; number of worker cores for M1 parallelism
#'   (default \code{parallel::detectCores() - 1L}).
#' @param verbose Logical; print progress.
#'
#' @return A named list (same structure as \code{loso_m1_m2_joint()}):
#'   \describe{
#'     \item{scores}{Tibble with one row per test season: season, n,
#'       mean_nll, brier, rmse_p.}
#'     \item{predictions}{Tibble of all per-observation predictions
#'       across test seasons.}
#'     \item{m1_preds}{Named list of M1 test predictions per season.}
#'     \item{folds}{Named list of fold objects for diagnostics.}
#'   }
#'
#' @export
nested_loso_cv <- function(allD,
                           params,
                           spec,
                           test_seasons       = NULL,
                           exclude_seasons    = NULL,
                           horizons           = c(1L, 2L),
                           eval_window        = 12L,
                           k_deriv            = 10L,
                           k_ref              = 25L,
                           n_weeks            = 52L,
                           ref_method         = "fs",
                           manual_labels      = NULL,
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
                           allow_scale        = NULL,
                           use_ci             = TRUE,
                           buffer_weeks       = 0L,
                           min_obs            = 4L,
                           curvature_ratio    = 1.0,
                           temperature        = 0.25,
                           rise_weight        = 1.0,
                           trough_weight      = 0.1,
                           peak_decay         = 0.3,
                           slope_weight       = 0.5,
                           slope_window       = 4L,
                           dynamic_temp       = TRUE,
                           dynamic_temp_pivot = 10L,
                           top_k              = NULL,
                           blend_alpha        = 1.0,
                           method             = "REML",
                           n_cores            = parallel::detectCores() - 1L,
                           skip_m1            = FALSE,
                           verbose            = TRUE) {

  # --- Validate ---
  all_seasons <- sort(unique(as.character(allD$season)))
  if (!is.null(exclude_seasons))
    all_seasons <- setdiff(all_seasons, exclude_seasons)
  if (is.null(test_seasons)) test_seasons <- all_seasons
  stopifnot(all(test_seasons %in% all_seasons))
  if (length(all_seasons) < 3L)
    stop("Need >= 3 seasons for LOSO; got ", length(all_seasons))

  # --- Parallel plan (used inside M1 walk-forward) ---
  n_workers <- max(1L, as.integer(n_cores))
  old_plan  <- future::plan()
  if (n_workers > 1L) future::plan(future::multisession, workers = n_workers)
  on.exit(future::plan(old_plan), add = TRUE)

  n_folds  <- length(test_seasons)
  cv_start <- proc.time()[["elapsed"]]

  if (isTRUE(verbose))
    message("\n=== nested_loso_cv: ", n_folds,
            " folds, ", length(all_seasons), " total seasons ===\n")

  # --- Run folds sequentially ---
  scores_list   <- vector("list", n_folds)
  pred_list     <- vector("list", n_folds)
  m1_preds_list <- vector("list", n_folds)
  folds_list    <- vector("list", n_folds)
  names(scores_list) <- names(pred_list) <- test_seasons
  names(m1_preds_list) <- names(folds_list) <- test_seasons

  for (fi in seq_along(test_seasons)) {
    test_s    <- test_seasons[fi]
    fold_t0   <- proc.time()[["elapsed"]]

    if (isTRUE(verbose))
      message(sprintf("\n--- Fold %d/%d: hold out %s ---", fi, n_folds, test_s))

    res <- tryCatch(
      nested_loso_run_fold(
        allD               = allD,
        test_season        = test_s,
        params             = params,
        spec               = spec,
        exclude_seasons    = exclude_seasons,
        horizons           = horizons,
        eval_window        = eval_window,
        k_deriv            = k_deriv,
        k_ref              = k_ref,
        n_weeks            = n_weeks,
        ref_method         = ref_method,
        manual_labels      = manual_labels,
        flag_args          = flag_args,
        allow_scale        = allow_scale,
        use_ci             = use_ci,
        buffer_weeks       = buffer_weeks,
        min_obs            = min_obs,
        curvature_ratio    = curvature_ratio,
        temperature        = temperature,
        rise_weight        = rise_weight,
        trough_weight      = trough_weight,
        peak_decay         = peak_decay,
        slope_weight       = slope_weight,
        slope_window       = slope_window,
        dynamic_temp       = dynamic_temp,
        dynamic_temp_pivot = dynamic_temp_pivot,
        top_k              = top_k,
        blend_alpha        = blend_alpha,
        method             = method,
        parallel           = (n_workers > 1L),
        skip_m1            = skip_m1,
        verbose            = verbose
      ),
      error = function(e) {
        warning("[nested_loso_cv] Fold ", test_s, " failed: ", e$message)
        list(
          scores      = tibble::tibble(season = test_s, n = NA_integer_,
                                       mean_nll = NA_real_, brier = NA_real_,
                                       rmse_p = NA_real_),
          predictions = tibble::tibble(),
          m1_preds    = NULL,
          fold        = NULL
        )
      }
    )

    scores_list[[test_s]]   <- res$scores
    pred_list[[test_s]]     <- res$predictions
    m1_preds_list[[test_s]] <- res$m1_preds
    folds_list[[test_s]]    <- res$fold

    if (isTRUE(verbose)) {
      fold_elapsed <- proc.time()[["elapsed"]] - fold_t0
      cv_elapsed   <- proc.time()[["elapsed"]] - cv_start
      folds_done   <- fi
      folds_left   <- n_folds - fi
      eta_secs     <- if (folds_done > 0) (cv_elapsed / folds_done) * folds_left else NA
      message(sprintf(
        "    Fold %d/%d done | fold: %s | cv elapsed: %s | ETA: %s",
        fi, n_folds,
        .fmt_duration(fold_elapsed),
        .fmt_duration(cv_elapsed),
        if (is.na(eta_secs)) "?" else .fmt_duration(eta_secs)
      ))
    }
  }

  # --- Aggregate ---
  scores_df <- dplyr::bind_rows(scores_list)
  preds_df  <- dplyr::bind_rows(pred_list)

  if (isTRUE(verbose)) {
    message("\n=== nested_loso_cv complete ===")
    message("  Overall mean_nll: ",
            round(mean(scores_df$mean_nll, na.rm = TRUE), 4))
    message("  Overall rmse_p:   ",
            round(mean(scores_df$rmse_p, na.rm = TRUE), 4))
  }

  list(
    scores      = scores_df,
    predictions = preds_df,
    m1_preds    = m1_preds_list,
    folds       = folds_list
  )
}


# ---------- 8. Grid search over specs ----------

# Internal helper: format seconds as "Xh Ym Zs"
.fmt_duration <- function(secs) {
  secs <- round(secs)
  h <- secs %/% 3600
  m <- (secs %% 3600) %/% 60
  s <- secs %% 60
  if (h > 0) sprintf("%dh %dm", h, m)
  else if (m > 0) sprintf("%dm %ds", m, s)
  else sprintf("%ds", s)
}

#' Nested LOSO grid search over M2 specs
#'
#' Loops over a named list of M2 spec objects and runs
#' \code{nested_loso_cv()} for each. Returns aggregated scores
#' with spec identifiers for comparison.
#'
#' @param allD Full multi-season data frame.
#' @param params M0 detection parameters.
#' @param specs Named list of M2 spec objects (from \code{stage2_make_spec()}).
#' @param checkpoint_file Optional path to an RDS file for incremental saves.
#'   After each spec completes, results are written to this file. If the file
#'   already exists at startup, completed specs are skipped (resume support).
#' @param ... Additional arguments passed to \code{nested_loso_cv()}
#'   (e.g. \code{test_seasons}, \code{eval_window}, \code{k_ref}, \code{verbose}).
#'
#' @return A named list:
#'   \describe{
#'     \item{scores}{Tibble with columns spec_id, season, n, mean_nll, brier, rmse_p.}
#'     \item{summary}{Tibble with one row per spec: spec_id, mean_nll, brier, rmse_p
#'       (averaged across seasons).}
#'     \item{best_spec_id}{The spec_id with lowest mean_nll.}
#'     \item{best_spec}{The corresponding spec object.}
#'     \item{cv_results}{Named list of full \code{nested_loso_cv()} outputs per spec.}
#'   }
#'
#' @export
nested_loso_grid_search <- function(allD,
                                    params,
                                    specs,
                                    checkpoint_file = NULL,
                                    ...) {

  stopifnot(is.list(specs), length(specs) > 0L)
  if (is.null(names(specs)))
    names(specs) <- paste0("spec_", seq_along(specs))

  n_specs    <- length(specs)
  grid_start <- proc.time()[["elapsed"]]
  message("\n====== nested_loso_grid_search: ", n_specs, " specs ======\n")
  if (!is.null(checkpoint_file))
    message("  Checkpoint file: ", checkpoint_file, "\n")

  all_scores  <- vector("list", n_specs)
  cv_results  <- vector("list", n_specs)
  names(all_scores) <- names(cv_results) <- names(specs)

  # Resume from checkpoint if it exists
  if (!is.null(checkpoint_file) && file.exists(checkpoint_file)) {
    ckpt <- readRDS(checkpoint_file)
    completed <- names(ckpt$cv_results)[!sapply(ckpt$cv_results, is.null)]
    message("  Resuming from checkpoint: ", length(completed),
            "/", n_specs, " specs already done")
    for (sid in completed) {
      cv_results[[sid]]  <- ckpt$cv_results[[sid]]
      sc <- ckpt$cv_results[[sid]]$scores
      if (!is.null(sc)) {
        all_scores[[sid]] <- dplyr::mutate(sc, spec_id = sid)
      }
    }
  } else {
    completed <- character(0)
  }

  for (i in seq_along(specs)) {
    sid  <- names(specs)[i]
    spec <- specs[[sid]]

    if (sid %in% completed) {
      message(sprintf("\n--- Spec %d/%d: %s [SKIPPED - already in checkpoint] ---",
                      i, n_specs, sid))
      next
    }

    spec_t0 <- proc.time()[["elapsed"]]
    message(sprintf("\n--- Spec %d/%d: %s ---", i, n_specs, sid))

    cv <- tryCatch(
      nested_loso_cv(allD = allD, params = params, spec = spec, ...),
      error = function(e) {
        warning("[grid_search] Spec ", sid, " failed: ", e$message)
        NULL
      }
    )

    cv_results[[sid]] <- cv

    if (!is.null(cv)) {
      sc <- dplyr::mutate(cv$scores, spec_id = sid)
      all_scores[[sid]] <- sc
    }

    # Timing and ETA
    spec_elapsed  <- proc.time()[["elapsed"]] - spec_t0
    grid_elapsed  <- proc.time()[["elapsed"]] - grid_start
    n_done        <- sum(!sapply(cv_results, is.null))
    n_left        <- n_specs - n_done
    eta_secs      <- if (n_done > 0) (grid_elapsed / n_done) * n_left else NA

    message(sprintf(
      "  => Spec %d/%d done | spec: %.0fs | total elapsed: %s | ETA: %s",
      n_done, n_specs,
      spec_elapsed,
      .fmt_duration(grid_elapsed),
      if (is.na(eta_secs)) "?" else .fmt_duration(eta_secs)
    ))

    # Incremental checkpoint save
    if (!is.null(checkpoint_file)) {
      ckpt_data <- list(cv_results = cv_results,
                        timestamp  = Sys.time(),
                        n_done     = n_done,
                        n_specs    = n_specs)
      saveRDS(ckpt_data, checkpoint_file)
      message("  [checkpoint saved: ", checkpoint_file, "]")
    }
  }

  scores_df <- dplyr::bind_rows(all_scores)

  if (nrow(scores_df) == 0 || !"spec_id" %in% names(scores_df)) {
    stop("[grid_search] No valid scores produced. ",
         "Check warnings above — all specs likely failed during fold execution.")
  }

  summary_df <- scores_df %>%
    dplyr::group_by(.data$spec_id) %>%
    dplyr::summarise(
      n_seasons = dplyr::n(),
      mean_nll  = mean(.data$mean_nll, na.rm = TRUE),
      brier     = mean(.data$brier,    na.rm = TRUE),
      rmse_p    = mean(.data$rmse_p,   na.rm = TRUE),
      .groups   = "drop"
    ) %>%
    dplyr::arrange(.data$mean_nll)

  best_id <- summary_df$spec_id[1]

  message("\n====== Grid search complete ======")
  message("  Best spec: ", best_id,
          " (mean_nll=", round(summary_df$mean_nll[1], 4), ")")

  list(
    scores       = scores_df,
    summary      = summary_df,
    best_spec_id = best_id,
    best_spec    = specs[[best_id]],
    cv_results   = cv_results
  )
}


# ---------- 9. Fit-back and diagnostics ----------

#' Refit M2 on all historical data with a chosen spec
#'
#' After selecting the best spec from nested LOSO, this function
#' refits M2 on the full aligned historical dataset using the
#' production reference curve. Returns the fit object ready for
#' deployment or plotting.
#'
#' @param alignedD_prosp Aligned historical data with prospective
#'   derivatives (output of \code{add_prospective_derivs_link()}).
#' @param template_df Reference curve template (newWeek, fit) — typically
#'   from the production (full-data) \code{estimateRef()}.
#' @param spec M2 spec object (from LOSO best or \code{stage2_make_spec()}).
#' @param m1_preds Optional data frame of M1 walk-forward predictions for all
#'   training seasons (output of \code{m1_walkforward_multi()}). When supplied,
#'   \code{logit_f_eff} in the training data is replaced with M1-based values,
#'   matching the richer feature representation available at deployment time.
#'   **This should be the same \code{m1_preds} that will be passed to
#'   \code{refit_stage2_weekly()} at deployment**, so the frozen GAM and the
#'   weekly refit are trained on the same feature space. Save it in
#'   \code{m2_production.rds} (as \code{m1_train_preds}) and load via
#'   \code{load_prospective_kit()}.
#' @param method GAM fitting method (default \code{"REML"}).
#' @param verbose Logical; print progress.
#'
#' @return Output of \code{train_stage2_joint()} — a list with
#'   \code{fit}, \code{train_data}, \code{spec}, \code{tuned}, etc.
#'
#' @export
nested_loso_refit_best <- function(alignedD_prosp,
                                   template_df,
                                   spec,
                                   m1_preds = NULL,
                                   method   = "REML",
                                   verbose  = TRUE) {

  if (isTRUE(verbose))
    message("[refit_best] Fitting M2 on full historical data with best spec")

  if (!"N" %in% names(alignedD_prosp))
    alignedD_prosp$N <- alignedD_prosp$y + alignedD_prosp$neg

  train_stage2_joint(
    dat         = alignedD_prosp,
    template_df = template_df,
    spec        = spec,
    m1_preds    = m1_preds,
    method      = method,
    verbose     = verbose
  )
}


#' Plot nested LOSO predictions by season
#'
#' Produces a faceted ggplot of observed vs predicted positivity
#' for each held-out season from nested LOSO results. Similar to
#' \code{plot_stage2_joint_fit_by_season()} but uses out-of-sample
#' predictions from the CV object rather than in-sample fits.
#'
#' @param cv_result Output of \code{nested_loso_cv()} or one element
#'   of \code{nested_loso_grid_search()$cv_results}.
#' @param dat_raw Optional aligned data for true ignition lines.
#' @param title Plot title.
#'
#' @return A ggplot object.
#'
#' @export
plot_nested_loso_predictions <- function(cv_result,
                                         dat_raw = NULL,
                                         title   = "Nested LOSO: predicted vs observed by season") {

  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Please install ggplot2.")

  preds <- cv_result$predictions
  if (is.null(preds) || nrow(preds) == 0) {
    message("No predictions to plot.")
    return(ggplot2::ggplot() + ggplot2::theme_void())
  }

  p <- ggplot2::ggplot(preds, ggplot2::aes(x = .data$weekF)) +
    ggplot2::geom_point(ggplot2::aes(y = .data$p_obs),
                        colour = "black", size = 1.0, alpha = 0.7) +
    ggplot2::geom_line(ggplot2::aes(y = .data$p_hat, colour = .data$lead),
                       linewidth = 0.9) +
    ggplot2::scale_colour_manual(
      values = c("1" = "steelblue", "2" = "tomato"),
      labels = c("1" = "h=1", "2" = "h=2")
    ) +
    ggplot2::labs(x = "weekF", y = "Positivity", colour = "Horizon",
                  title = title) +
    ggplot2::theme_bw()

  # Add ignition lines from raw data
  if (!is.null(dat_raw) && all(c("season", "weekF", "phase") %in% names(dat_raw))) {
    ign_true <- dat_raw %>%
      dplyr::group_by(.data$season) %>%
      dplyr::summarise(
        iWeek_true = suppressWarnings(min(.data$weekF[.data$phase == 1L], na.rm = TRUE)),
        .groups = "drop"
      ) %>%
      dplyr::filter(is.finite(.data$iWeek_true))

    p <- p + ggplot2::geom_vline(
      data = ign_true,
      ggplot2::aes(xintercept = .data$iWeek_true),
      linewidth = 0.5, linetype = "dashed"
    )
  }

  p + ggplot2::facet_wrap(~ season, scales = "free_y", ncol = 3)
}


#' Plot nested LOSO scores by season
#'
#' Bar chart of per-season scores from nested LOSO, with the overall
#' mean shown as a dashed line.
#'
#' @param scores Scores tibble from \code{nested_loso_cv()} or
#'   \code{nested_loso_grid_search()}.
#' @param metric Character; which metric to plot. One of
#'   \code{"mean_nll"}, \code{"brier"}, \code{"rmse_p"}.
#' @param title Plot title.
#'
#' @return A ggplot object.
#'
#' @export
plot_nested_loso_scores <- function(scores,
                                    metric = "mean_nll",
                                    title  = NULL) {

  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Please install ggplot2.")
  stopifnot(metric %in% c("mean_nll", "brier", "rmse_p"))

  if (is.null(title))
    title <- paste0("Nested LOSO: ", metric, " by season")

  overall_mean <- mean(scores[[metric]], na.rm = TRUE)

  ggplot2::ggplot(scores, ggplot2::aes(x = .data$season, y = .data[[metric]])) +
    ggplot2::geom_col(fill = "steelblue", alpha = 0.8) +
    ggplot2::geom_hline(yintercept = overall_mean,
                        linetype = "dashed", colour = "red", linewidth = 0.7) +
    ggplot2::annotate("text", x = 1, y = overall_mean,
                      label = sprintf("mean = %.4f", overall_mean),
                      vjust = -0.5, hjust = 0, colour = "red", size = 3.5) +
    ggplot2::labs(x = "Season", y = metric, title = title) +
    ggplot2::theme_bw() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}
