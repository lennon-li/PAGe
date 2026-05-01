# ============================================================
# Nested M1 → M2 LOSO: Fold building and per-fold training
#
# Sections 1–4: build fold, M1 train, M2 train, M1 test.
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

  train_outs <- res_deriv$data |>
    dplyr::group_by(.data$season) |>
    dplyr::group_split(.keep = TRUE) |>
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
                                 slope_weight       = 8.0,
                                 slope_window       = 6L,
                                 dynamic_temp       = FALSE,
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
                                slope_weight       = 8.0,
                                slope_window       = 6L,
                                dynamic_temp       = FALSE,
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
