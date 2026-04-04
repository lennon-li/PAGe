# ============================================================
# M1 → M2 Bridge: Generate M1 walk-forward predictions
# for use as M2 training features (stacking architecture)
# ============================================================

#' Run M1 walk-forward for one season and collect predictions at target weeks
#'
#' For each evaluation week, runs \code{run_alignment_prospective()} and
#' extracts M1's template-based prediction at each forecast target week
#' (weekF + h). Returns a tidy tibble suitable for joining to M2 training data.
#'
#' @param seasonD Data frame for ONE season (all weeks). Must have
#'   columns \code{weekF}, \code{y}, and either \code{N} or \code{neg}.
#' @param ref Output from \code{estimateRef()} (pre-computed from training data).
#' @param hyper Output from \code{learn_alignment_hyperparams()}.
#' @param ign_out Pre-computed output from \code{run_ignition_weekly()}.
#'   If NULL, must supply \code{params} to run M0 internally.
#' @param params M0 detection params. Used only if \code{ign_out} is NULL.
#' @param horizons Integer vector of forecast horizons (default \code{c(1L, 2L)}).
#' @param eval_weeks Optional integer vector of weekF values to evaluate at.
#'   If NULL, evaluates from ignition lock through end of season.
#' @param allow_scale Passed to \code{run_alignment_prospective()}.
#' @param use_ci Logical; peak CI control (default TRUE).
#' @param buffer_weeks Integer; peak buffer (default 0L).
#' @param min_obs Integer; minimum rows for alignment (default 4L).
#' @param curvature_ratio Numeric; delta curvature gate (default 1.0).
#'
#' @return A tibble with columns:
#' \describe{
#'   \item{season}{Season label}
#'   \item{eval_weekF}{The weekF at which M1 was run (data up to this week)}
#'   \item{target_weekF}{The weekF for which M1 predicts (eval_weekF + h)}
#'   \item{h}{Forecast horizon (1 or 2)}
#'   \item{m1_p_hat}{M1's predicted positivity at target week}
#'   \item{m1_p_lo}{M1's lower PI at target week}
#'   \item{m1_p_hi}{M1's upper PI at target week}
#'   \item{m1_tau}{M1's shift parameter at eval_weekF}
#'   \item{m1_delta}{M1's dilation parameter at eval_weekF}
#'   \item{m1_state}{M1 state: "aligning" or "post_peak"}
#' }
#'
#' @export
m1_walkforward_predictions <- function(seasonD,
                                       ref,
                                       hyper,
                                       ign_out            = NULL,
                                       params             = NULL,
                                       horizons           = c(1L, 2L),
                                       eval_weeks         = NULL,
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
                                       blend_alpha        = 1.0) {

  season_name <- unique(as.character(seasonD$season))[1]
  horizons    <- as.integer(horizons)
  max_weekF   <- max(seasonD$weekF, na.rm = TRUE)

  # --- M0: run ignition detection if not supplied ---
  if (is.null(ign_out)) {
    if (is.null(params))
      stop("Either 'ign_out' or 'params' must be provided.")
    ign_out <- run_ignition_weekly(
      currentSeason  = seasonD,
      ign_fit_or_gam = NULL,
      params         = params,
      start_week     = 1L
    )
  }

  # No ignition detected → empty result
  if (is.na(ign_out$ign_week_locked))
    return(.empty_m1_preds())

  # --- Resolve eval weeks ---
  if (is.null(eval_weeks)) {
    eval_weeks <- seq(as.integer(ign_out$ign_week_locked), max_weekF)
  }
  eval_weeks <- as.integer(eval_weeks)

  # --- Walk-forward over eval weeks ---
  results <- vector("list", length(eval_weeks))

  for (i in seq_along(eval_weeks)) {
    ew <- eval_weeks[i]
    season_to_ew <- dplyr::filter(seasonD, .data$weekF <= ew)

    ap <- tryCatch(
      run_alignment_prospective_multi(
        currentSeason      = season_to_ew,
        ref                = ref,
        hyper              = hyper,
        ign_out            = ign_out,
        use_ci             = use_ci,
        buffer_weeks       = buffer_weeks,
        allow_scale        = allow_scale,
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
      ),
      error = function(e) NULL
    )

    if (is.null(ap) || ap$state == "pre_ignition" || is.null(ap$forecast_df))
      next

    iWeek_hat  <- ap$iWeek_hat
    anchorWeek <- ref$anchorWeek
    fdf        <- ap$forecast_df

    # Extract predictions at each target week for each horizon
    rows <- vector("list", length(horizons))
    for (j in seq_along(horizons)) {
      h <- horizons[j]
      target_weekF   <- ew + h
      target_newWeek <- as.numeric(target_weekF - iWeek_hat + anchorWeek)

      # Interpolate M1's prediction at target_newWeek
      p_hat <- stats::approx(fdf$newWeek, fdf$p_hat, xout = target_newWeek,
                             rule = 2)$y
      p_lo  <- stats::approx(fdf$newWeek, fdf$p_lo,  xout = target_newWeek,
                             rule = 2)$y
      p_hi  <- stats::approx(fdf$newWeek, fdf$p_hi,  xout = target_newWeek,
                             rule = 2)$y

      rows[[j]] <- tibble::tibble(
        season         = season_name,
        eval_weekF     = ew,
        target_weekF   = target_weekF,
        h              = h,
        m1_p_hat       = p_hat,
        m1_p_lo        = p_lo,
        m1_p_hi        = p_hi,
        m1_tau         = ap$tau,
        m1_delta       = ap$delta,
        m1_state       = ap$state
      )
    }
    results[[i]] <- dplyr::bind_rows(rows)
  }

  out <- dplyr::bind_rows(results)
  if (nrow(out) == 0) return(.empty_m1_preds())
  out
}


#' Run M1 walk-forward for multiple seasons (parallelized)
#'
#' Calls \code{m1_walkforward_predictions()} for each season, optionally
#' in parallel via \code{furrr::future_map()}.
#'
#' @param allD Multi-season data frame.
#' @param ref Output from \code{estimateRef()}.
#' @param hyper Output from \code{learn_alignment_hyperparams()}.
#' @param params M0 detection params.
#' @param seasons Character vector of seasons to process.
#' @param horizons Forecast horizons (default \code{c(1L, 2L)}).
#' @param eval_weeks Optional; if NULL, determined per season from ignition.
#' @param allow_scale Passed through.
#' @param use_ci Passed through.
#' @param buffer_weeks Passed through.
#' @param min_obs Passed through.
#' @param curvature_ratio Passed through.
#' @param parallel Logical; use parallel via furrr (default TRUE).
#' @param verbose Logical; print progress (default TRUE).
#'
#' @return A tibble (stacked across seasons) with the same columns as
#'   \code{m1_walkforward_predictions()}.
#' @export
m1_walkforward_multi <- function(allD,
                                 ref,
                                 hyper,
                                 params,
                                 seasons            = NULL,
                                 horizons           = c(1L, 2L),
                                 eval_weeks         = NULL,
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

  if (is.null(seasons)) seasons <- sort(unique(as.character(allD$season)))

  map_fn <- if (isTRUE(parallel) && requireNamespace("furrr", quietly = TRUE)) {
    function(...) furrr::future_map(..., .options = furrr::furrr_options(seed = TRUE))
  } else {
    purrr::map
  }

  results <- map_fn(seasons, function(s) {
    if (isTRUE(verbose)) message("[m1_walkforward_multi] Processing season: ", s)
    seasonD <- dplyr::filter(allD, .data$season == s)

    m1_walkforward_predictions(
      seasonD            = seasonD,
      ref                = ref,
      hyper              = hyper,
      params             = params,
      horizons           = horizons,
      eval_weeks         = eval_weeks,
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
  })

  dplyr::bind_rows(results)
}


# internal: empty tibble with correct columns
.empty_m1_preds <- function() {
  tibble::tibble(
    season         = character(0),
    eval_weekF     = integer(0),
    target_weekF   = integer(0),
    h              = integer(0),
    m1_p_hat       = numeric(0),
    m1_p_lo        = numeric(0),
    m1_p_hi        = numeric(0),
    m1_tau         = numeric(0),
    m1_delta       = numeric(0),
    m1_state       = character(0)
  )
}


# ============================================================
# Runtime helper: Inject M1 prediction into M2 snapshot
# ============================================================

#' Replace logit_f_eff in M2 snapshots with M1's aligned prediction
#'
#' Takes the output of \code{build_stage2_pseudo_prospective_list()} and
#' replaces each snapshot's \code{logit_f_eff} with M1's prediction at
#' the corresponding target week.
#'
#' @param pp List with \code{meta} and \code{df} from
#'   \code{build_stage2_pseudo_prospective_list()}.
#' @param m1_result Output from \code{run_alignment_prospective()} for the
#'   current evaluation week.
#' @param ref Reference object (must have \code{anchorWeek}).
#' @param horizons Integer vector of forecast horizons (default \code{c(1L, 2L)}).
#' @param eps Clipping epsilon for logit (default 1e-6).
#'
#' @return Modified \code{pp} with \code{logit_f_eff} replaced by M1 predictions.
#' @export
inject_m1_into_snapshots <- function(pp,
                                     m1_result,
                                     ref,
                                     horizons = c(1L, 2L),
                                     eps      = 1e-6) {

  if (is.null(m1_result) || m1_result$state == "pre_ignition" ||
      is.null(m1_result$forecast_df))
    return(pp)

  fdf        <- m1_result$forecast_df
  iWeek_hat  <- m1_result$iWeek_hat
  anchorWeek <- ref$anchorWeek

  for (i in seq_along(pp$df)) {
    snap <- pp$df[[i]]
    if (!is.data.frame(snap) || nrow(snap) == 0) next

    # For each row, compute M1's prediction at the target week
    h_int <- as.integer(sub("^h", "", as.character(snap$lead)))
    target_weekF   <- as.integer(snap$weekF) + h_int
    target_newWeek <- as.numeric(target_weekF - iWeek_hat + anchorWeek)

    m1_p <- stats::approx(fdf$newWeek, fdf$p_hat, xout = target_newWeek,
                          rule = 2)$y

    has_m1 <- is.finite(m1_p) & !is.na(m1_p)
    m1_logit <- ifelse(has_m1, logit_stable(m1_p, eps = eps), snap$logit_f_eff)

    pp$df[[i]]$logit_f_eff <- m1_logit
  }

  pp
}


#' Run full M0→M1→M2 weekly forecast chain
#'
#' Convenience function for prospective deployment that chains:
#' \enumerate{
#'   \item M0 ignition detection (via \code{ign_out} or \code{params})
#'   \item M1 alignment (via \code{run_alignment_prospective()})
#'   \item M2 forecast with M1's prediction as template
#' }
#'
#' @param currentSeason Data frame for the current season up to this week.
#' @param ref Reference object from \code{estimateRef()}.
#' @param hyper M1 hyperparams from \code{learn_alignment_hyperparams()}.
#' @param stage2_fit Fitted M2 model (bam/gam object).
#' @param kit Prospective kit (used by \code{build_stage2_pseudo_prospective_list()}).
#' @param params M0 detection params (if \code{ign_out} is NULL).
#' @param ign_out Pre-computed M0 ignition output.
#' @param allow_scale Passed to M1 alignment.
#' @param level Confidence level (default 0.95).
#' @param use_m1_template Logical. If TRUE (default), replaces M2's template
#'   with M1's aligned prediction. If FALSE, uses static template (legacy mode).
#' @param exclude M2 prediction exclude terms (e.g., for new season).
#' @param exclude_season_re Logical (default TRUE).
#' @param interval "pi" or "ci" for M2 prediction intervals.
#'
#' @return A list with:
#' \describe{
#'   \item{m1}{Full M1 alignment result from \code{run_alignment_prospective()}}
#'   \item{m2_forecast}{M2 forecast data frame from \code{stage2_predict_series()}}
#'   \item{state}{Overall pipeline state: "pre_ignition", "aligning", or "post_peak"}
#' }
#' @export
run_m0_m1_m2_weekly <- function(currentSeason,
                                 ref,
                                 hyper,
                                 stage2_fit,
                                 kit           = NULL,
                                 params        = NULL,
                                 ign_out       = NULL,
                                 allow_scale   = NULL,
                                 level         = 0.95,
                                 use_m1_template = TRUE,
                                 template_df   = NULL,
                                 best_mean_nll = NULL,
                                 exclude_season_re = TRUE,
                                 interval      = c("pi", "ci")) {

  interval <- match.arg(interval)

  `%||%` <- function(x, y) if (is.null(x)) y else x
  template_df   <- template_df   %||% kit$m2_production$template_df
  best_mean_nll <- best_mean_nll %||% kit$best_spec
  if (is.null(template_df) || is.null(best_mean_nll))
    stop("Provide template_df and best_mean_nll directly, or pass a kit containing them.")

  # --- Step 1: M0 + M1 ---
  m1 <- run_alignment_prospective(
    currentSeason = currentSeason,
    ref           = ref,
    hyper         = hyper,
    params        = params,
    ign_out       = ign_out,
    allow_scale   = allow_scale,
    level         = level
  )

  if (m1$state == "pre_ignition") {
    return(list(m1 = m1, m2_forecast = NULL, state = "pre_ignition"))
  }

  # --- Step 2: Build M2 snapshots ---
  pp <- build_stage2_pseudo_prospective_list(
    currentSeason = currentSeason,
    template_df   = template_df,
    best_mean_nll = best_mean_nll,
    iWeek_hat     = m1$iWeek_hat
  )

  # --- Step 3: Inject M1 predictions into M2 template ---
  if (isTRUE(use_m1_template)) {
    pp <- inject_m1_into_snapshots(
      pp        = pp,
      m1_result = m1,
      ref       = ref
    )
  }

  # --- Step 4: M2 prediction ---
  m2_forecast <- stage2_predict_series(
    pp                 = pp,
    stage2_fit         = stage2_fit,
    which              = "latest",
    exclude_season_re  = exclude_season_re,
    interval           = interval,
    level              = level
  )

  list(
    m1          = m1,
    m2_forecast = m2_forecast,
    state       = m1$state
  )
}


# ============================================================
# Joint M0→M1→M2 LOSO Evaluator
# ============================================================

#' Leave-one-season-out evaluation of the full M0→M1→M2 pipeline
#'
#' For each test season, this function:
#' \enumerate{
#'   \item Builds aligned training data and fits reference curve (M1 training)
#'   \item Runs M1 walk-forward for each training season to generate M1
#'     predictions (template features for M2)
#'   \item Trains M2 with M1 predictions as the template feature (stacking)
#'   \item Runs M1 walk-forward on the test season and evaluates M2
#' }
#'
#' @param allD Multi-season data frame with columns weekF, y, neg, season.
#' @param params M0 detection parameters.
#' @param spec M2 spec from \code{stage2_make_spec()}.
#' @param template_df Template curve (newWeek, fit). Used as fallback when
#'   M1 predictions are unavailable.
#' @param manual_labels Named list of manual ignition labels per season.
#' @param test_seasons Character vector of seasons to hold out. If NULL,
#'   uses all seasons.
#' @param exclude_seasons Seasons to exclude entirely.
#' @param horizons Forecast horizons (default \code{c(1L, 2L)}).
#' @param eval_window Integer; post-ignition weeks to evaluate (default 12L).
#' @param k_deriv Integer; derivative fitting window (default 10L).
#' @param k_ref Integer; reference GAM basis size (default 10L).
#' @param n_weeks Integer; number of weeks in a season (default 52L).
#' @param flag_args List of ignition detection parameters.
#' @param allow_scale Passed to alignment.
#' @param use_ci Passed to alignment.
#' @param buffer_weeks Passed to alignment.
#' @param min_obs Minimum observations for alignment.
#' @param curvature_ratio Passed to alignment.
#' @param method BAM fitting method (default "REML").
#' @param n_cores Number of parallel workers.
#' @param verbose Logical.
#'
#' @return A list with:
#' \describe{
#'   \item{scores}{Tibble with per-season NLL, Brier, RMSE scores}
#'   \item{predictions}{Tibble with all M2 predictions vs actuals}
#'   \item{m1_preds_list}{List of M1 predictions per fold (for diagnostics)}
#' }
#' @export
loso_m1_m2_joint <- function(allD,
                              params,
                              spec,
                              template_df,
                              manual_labels   = NULL,
                              test_seasons    = NULL,
                              exclude_seasons = NULL,
                              horizons        = c(1L, 2L),
                              eval_window     = 12L,
                              k_deriv         = 10L,
                              k_ref           = 10L,
                              n_weeks         = 52L,
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
                              allow_scale     = NULL,
                              use_ci          = TRUE,
                              buffer_weeks    = 0L,
                              min_obs         = 4L,
                              curvature_ratio = 1.0,
                              method          = "REML",
                              n_cores         = parallel::detectCores() - 1L,
                              verbose         = TRUE) {

  all_seasons <- sort(unique(as.character(allD$season)))

  if (!is.null(exclude_seasons)) {
    allD        <- dplyr::filter(allD, !.data$season %in% exclude_seasons)
    all_seasons <- setdiff(all_seasons, exclude_seasons)
  }

  if (is.null(test_seasons)) test_seasons <- all_seasons
  stopifnot(all(test_seasons %in% all_seasons))

  if (length(all_seasons) < 3)
    stop("Need >= 3 seasons for LOSO.")

  # Set up parallel plan
  n_workers <- max(1L, as.integer(n_cores))
  old_plan  <- future::plan()
  if (n_workers > 1L) future::plan(future::multisession, workers = n_workers)
  on.exit(future::plan(old_plan), add = TRUE)

  scores_list     <- vector("list", length(test_seasons))
  pred_list       <- vector("list", length(test_seasons))
  m1_preds_list   <- vector("list", length(test_seasons))
  names(scores_list) <- names(pred_list) <- names(m1_preds_list) <- test_seasons

  for (test_s in test_seasons) {
    if (isTRUE(verbose))
      message("\n=== [loso_m1_m2_joint] Test season: ", test_s, " ===")

    tr_seasons <- setdiff(all_seasons, test_s)

    # --- Step 1: Build aligned training data + reference curve ---
    if (isTRUE(verbose)) message("  Step 1: Fitting reference on ", length(tr_seasons), " training seasons")
    train_allD <- dplyr::filter(allD, .data$season %in% tr_seasons)
    res_deriv  <- estimateDerivs(train_allD, k = k_deriv)

    train_outs <- res_deriv$data %>%
      dplyr::group_by(.data$season) %>%
      dplyr::group_split(.keep = TRUE) %>%
      purrr::map(~ do.call(flagIgnition,
                           c(list(df = .x, manual_labels = manual_labels), flag_args)))

    aligned_train <- alignIgnition(train_outs)
    ref <- estimateRef(alignedD = aligned_train, exSeason = character(0),
                       k = k_ref, n_weeks = n_weeks)
    hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)

    # --- Step 2: M1 walk-forward for all training seasons ---
    if (isTRUE(verbose)) message("  Step 2: Running M1 walk-forward for training seasons")

    m1_train_preds <- m1_walkforward_multi(
      allD            = allD,
      ref             = ref,
      hyper           = hyper,
      params          = params,
      seasons         = tr_seasons,
      horizons        = horizons,
      allow_scale     = allow_scale,
      use_ci          = use_ci,
      buffer_weeks    = buffer_weeks,
      min_obs         = min_obs,
      curvature_ratio = curvature_ratio,
      parallel        = (n_workers > 1L),
      verbose         = FALSE
    )

    if (isTRUE(verbose))
      message("  M1 training predictions: ", nrow(m1_train_preds), " rows across ",
              length(unique(m1_train_preds$season)), " seasons")

    # --- Step 3: Prepare aligned training data with prospective derivatives ---
    alignedD_prosp <- add_prospective_derivs_link(aligned_train)
    if (!"N" %in% names(alignedD_prosp))
      alignedD_prosp$N <- alignedD_prosp$y + alignedD_prosp$neg

    # --- Step 4: Train M2 with M1 predictions as template ---
    if (isTRUE(verbose)) message("  Step 3-4: Training M2 with M1-stacked template")

    m2_fit <- tryCatch(
      train_stage2_joint(
        dat         = alignedD_prosp,
        template_df = template_df,
        spec        = spec,
        method      = method,
        m1_preds    = m1_train_preds,
        verbose     = FALSE
      ),
      error = function(e) {
        warning("M2 training failed for test season ", test_s, ": ", e$message)
        NULL
      }
    )

    if (is.null(m2_fit)) {
      scores_list[[test_s]] <- tibble::tibble(
        season = test_s, mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_
      )
      next
    }

    # --- Step 5: M1 walk-forward on test season ---
    if (isTRUE(verbose)) message("  Step 5: Running M1 walk-forward on test season")

    m1_test_preds <- m1_walkforward_predictions(
      seasonD         = dplyr::filter(allD, .data$season == test_s),
      ref             = ref,
      hyper           = hyper,
      params          = params,
      horizons        = horizons,
      allow_scale     = allow_scale,
      use_ci          = use_ci,
      buffer_weeks    = buffer_weeks,
      min_obs         = min_obs,
      curvature_ratio = curvature_ratio
    )
    m1_preds_list[[test_s]] <- m1_test_preds

    if (nrow(m1_test_preds) == 0) {
      if (isTRUE(verbose)) message("  No M1 predictions for test season (no ignition?)")
      scores_list[[test_s]] <- tibble::tibble(
        season = test_s, mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_
      )
      next
    }

    # --- Step 6: Prepare test data + M2 prediction ---
    if (isTRUE(verbose)) message("  Step 6: Evaluating M2 on test season")

    test_allD <- dplyr::filter(allD, .data$season == test_s)
    test_deriv <- estimateDerivs(test_allD, k = k_deriv)

    test_outs <- test_deriv$data %>%
      dplyr::group_by(.data$season) %>%
      dplyr::group_split(.keep = TRUE) %>%
      purrr::map(~ do.call(flagIgnition,
                           c(list(df = .x, manual_labels = manual_labels), flag_args)))

    aligned_test <- alignIgnition(test_outs)
    aligned_test_prosp <- add_prospective_derivs_link(aligned_test)
    if (!"N" %in% names(aligned_test_prosp))
      aligned_test_prosp$N <- aligned_test_prosp$y + aligned_test_prosp$neg

    # Build M2 test data with M1 test predictions
    d_test <- tryCatch(
      prep_stage2_joint(
        dat           = aligned_test_prosp,
        best_mean_nll = spec$best_row,
        template_df   = template_df,
        leads         = horizons,
        pre_buffer    = as.integer(spec$pre_buffer %||% 0L),
        alpha_state   = as.numeric(spec$alpha_state %||% 0.30),
        m1_preds      = m1_test_preds,
        verbose       = FALSE
      ),
      error = function(e) NULL
    )

    if (is.null(d_test) || nrow(d_test) == 0) {
      scores_list[[test_s]] <- tibble::tibble(
        season = test_s, mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_
      )
      next
    }

    # Restrict to eval window
    d_test <- d_test[d_test$post_ign, , drop = FALSE]
    if (!is.null(eval_window) && "t_since" %in% names(d_test)) {
      d_test <- d_test[is.finite(d_test$t_since) &
                         d_test$t_since >= 0 &
                         d_test$t_since <= as.integer(eval_window), , drop = FALSE]
    }

    if (nrow(d_test) == 0) {
      scores_list[[test_s]] <- tibble::tibble(
        season = test_s, mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_
      )
      next
    }

    # Score M2
    scores <- score_stage2_metrics(
      fit                  = m2_fit$fit,
      d_test               = d_test,
      exclude_season_re    = TRUE,
      exclude_terms        = spec$exclude_newseason,
      lambda_w             = 0,
      eval_window          = eval_window
    )

    scores_list[[test_s]] <- tibble::tibble(
      season   = test_s,
      n        = nrow(d_test),
      mean_nll = scores$mean_nll,
      brier    = scores$brier,
      rmse_p   = scores$rmse_p
    )

    # Collect predictions for diagnostics
    fit_obj <- m2_fit$fit
    ex <- spec$exclude_newseason

    # Align factor levels
    if ("lead" %in% names(d_test) && is.factor(fit_obj$model$lead))
      d_test$lead <- factor(as.character(d_test$lead), levels = levels(fit_obj$model$lead))
    if ("season" %in% names(d_test) && is.factor(fit_obj$model$season)) {
      d_test$season <- factor(as.character(d_test$season), levels = levels(fit_obj$model$season))
      if (anyNA(d_test$season)) d_test$season[is.na(d_test$season)] <- levels(fit_obj$model$season)[1]
    }
    if ("season_h" %in% names(d_test) && is.factor(fit_obj$model$season_h)) {
      d_test$season_h <- factor(as.character(d_test$season_h), levels = levels(fit_obj$model$season_h))
      if (anyNA(d_test$season_h)) d_test$season_h[is.na(d_test$season_h)] <- levels(fit_obj$model$season_h)[1]
    }

    p_hat <- as.numeric(stats::predict(fit_obj, newdata = d_test, type = "response", exclude = ex))
    p_hat <- pmin(1 - 1e-12, pmax(1e-12, p_hat))

    pred_list[[test_s]] <- tibble::tibble(
      season   = test_s,
      weekF    = d_test$weekF,
      lead     = as.character(d_test$lead),
      t_since  = d_test$t_since,
      p_hat    = p_hat,
      p_obs    = d_test$y_lead / d_test$N_lead,
      y_lead   = d_test$y_lead,
      N_lead   = d_test$N_lead
    )

    if (isTRUE(verbose))
      message("  Score: mean_nll=", round(scores$mean_nll, 4),
              " brier=", round(scores$brier, 6),
              " rmse_p=", round(scores$rmse_p, 4))
  }

  list(
    scores      = dplyr::bind_rows(scores_list),
    predictions = dplyr::bind_rows(pred_list),
    m1_preds    = m1_preds_list
  )
}
