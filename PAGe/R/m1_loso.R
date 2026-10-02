# Weighted MAE used by the M1 LOSO scorer.  Missing/undefined rows are not
# informative for the metric and must not make the aggregate itself NA.
.weighted_mae <- function(df, weight_col, error_col = "error") {
  if (!is.data.frame(df) || !nrow(df) || !weight_col %in% names(df) ||
    !error_col %in% names(df)) {
    return(NA_real_)
  }
  w <- suppressWarnings(as.numeric(df[[weight_col]]))
  error <- suppressWarnings(as.numeric(df[[error_col]]))
  keep <- is.finite(w) & w > 0 & is.finite(error)
  if (!any(keep)) {
    return(NA_real_)
  }
  total <- sum(w[keep])
  if (!is.finite(total) || total <= 0) {
    return(NA_real_)
  }
  sum(w[keep] * error[keep]) / total
}

#' Walk-forward alignment evaluation with LOSO reference curves
#'
#' For each test season (LOSO by default):
#' \enumerate{
#'   \item Runs \code{estimateDerivs()} + \code{flagIgnition()} + \code{alignIgnition()}
#'     on the training seasons to build an aligned training dataset.
#'   \item Fits the reference curve with \code{estimateRef()} on the training
#'     aligned data.
#'   \item Runs \code{run_ignition_weekly()} prospectively on the raw test-season
#'     data to simulate real-time ignition detection.
#'   \item Walks forward from \code{walk_start} to \code{walk_end}: once ignition
#'     locks at \code{iWeek_hat}, re-anchors data as
#'     \code{newWeek = weekF - iWeek_hat + anchorWeek} and produces alignment +
#'     forecast at each step.
#' }
#'
#' @param allD Raw data frame (one row per season-week) with at least
#'   \code{season}, \code{weekF}, \code{y}, \code{N} (or \code{neg}), \code{p}.
#' @param params Named list of Stage-1 detector threshold parameters passed to
#'   \code{run_ignition_weekly()} (e.g. \code{stage1_tuning.rds$best_params}).
#' @param walk_start Integer or \code{NULL}. First \code{weekF} at which to
#'   produce a forecast. \code{NULL} (default) starts at the ignition-lock week.
#' @param walk_end Integer or \code{NULL}. Last \code{weekF} at which to
#'   evaluate. \code{NULL} (default) uses the last observed week of the season.
#' @param manual_labels Named integer vector mapping season labels to verified
#'   ignition \code{weekF} values, passed to \code{flagIgnition()} for training
#'   seasons. \code{NULL} forces algorithmic detection.
#' @param train_seasons Character vector of training season labels. \code{NULL}
#'   (default) uses all seasons except the test season (LOSO).
#' @param test_seasons Character vector of test season labels. \code{NULL}
#'   (default) evaluates all seasons.
#' @param k_deriv Basis dimension passed to \code{estimateDerivs()} (default 10).
#' @param k_ref Basis dimension passed to \code{estimateRef()} (default 10).
#' @param n_weeks Integer. Template domain length for \code{estimateRef()} (default 52).
#' @param flag_args Named list of additional arguments forwarded to
#'   \code{flagIgnition()} (excluding \code{df} and \code{manual_labels}).
#' @param allow_scale Logical or \code{NULL}. Passed to
#'   \code{check_scale_identifiability()}. \code{NULL} auto-detects per fold.
#' @param level Numeric. CI level for forecast intervals (default 0.95).
#' @param use_ci Logical. Forwarded to \code{run_alignment_prospective()}.
#'   If \code{TRUE} (default), the peak is declared passed once the last
#'   observed \code{newWeek} exceeds the upper CI bound.
#' @param buffer_weeks Integer. Forwarded to \code{run_alignment_prospective()}.
#'   Additional weeks beyond the threshold before declaring the peak passed
#'   (default \code{0L}).
#' @param exclude_seasons Character vector of season labels to exclude from both
#'   training and testing. Useful for known outlier seasons (e.g. \code{"2015-16"}).
#'   \code{NULL} (default) excludes nothing.
#' @param n_cores Integer. Parallel workers for the eval_weeks loop per season.
#'   Defaults to \code{parallel::detectCores() - 1}. Set to 1 to disable.
#' @param min_obs Integer. Minimum observations after ignition before attempting
#'   alignment (default 4).
#' @param curvature_ratio Numeric coefficient for activating dilation.
#' @param template_shift Integer shift applied to template coordinates.
#' @param align_trough_weight,align_rise_weight,align_peak_decay Numeric
#'   alignment-loss weights for epidemic regions.
#' @param use_multi_template Logical; use the multi-template ensemble.
#' @param ref_method Reference-curve method passed to \code{estimateRef()}.
#' @param multi_temperature,multi_top_k,multi_blend_alpha Ensemble controls.
#' @param slope_weight,slope_window Growth-rate similarity controls.
#' @param dynamic_temp,dynamic_temp_pivot Early-season temperature controls.
#' @param peak_weight_boost Numeric >= 1. Multiplicative weight for observations
#'   between ignition and peak in \code{estimateDerivs()} (default 1 = no boost).
#' @param peak_weight_decay Numeric > 0. Exponential decay rate for weights after
#'   the observed peak (default 0.3).
#' @param checkpoint_file Character path (or \code{NULL}). If provided, saves
#'   incremental results to this RDS file after each test season completes. On
#'   restart, completed seasons are loaded from the checkpoint and skipped.
#'   Delete the file to force a full rerun.
#' @param verbose Logical. Print per-season progress (default \code{TRUE}).
#'
#' @return A list with three elements:
#' \describe{
#'   \item{params_df}{Tibble with one row per (season, eval_week). Columns:
#'     \code{season}, \code{eval_week}, \code{n_obs}, \code{iWeek_hat},
#'     \code{iWeek_true}, \code{tau}, \code{delta}, \code{a}, \code{b},
#'     \code{allow_scale}, \code{delta_on}, \code{t_peak}, \code{t_peak_lo},
#'     \code{t_peak_hi}, \code{peak_weekF}, \code{peak_passed},
#'     \code{fallback_reason}, \code{n_train}, \code{anchorWeek}.}
#'   \item{forecast_df}{Tibble with one row per (season, eval_week, newWeek).
#'     Columns: \code{season}, \code{eval_week}, \code{newWeek}, \code{p_hat},
#'     \code{p_lo}, \code{p_hi}, \code{kind}.}
#'   \item{ref_list}{Named list of \code{estimateRef()} outputs, one per test
#'     season.}
#' }
#'
#' @examples
#' \dontrun{
#' tuned <- readRDS("data/stage1_tuning.rds")
#' wf <- loso_walkforward(
#'   allD          = allD,
#'   params        = tuned$best_params,
#'   walk_start    = 10,
#'   walk_end      = 30,
#'   manual_labels = c("2017-18" = 20L, "2018-19" = 19L),
#'   test_seasons  = "2017-18"
#' )
#' }
loso_walkforward <- function(allD,
                             params,
                             walk_start = NULL,
                             walk_end = NULL,
                             manual_labels = NULL,
                             train_seasons = NULL,
                             test_seasons = NULL,
                             exclude_seasons = NULL,
                             k_deriv = 10L,
                             k_ref = 10L,
                             n_weeks = 52L,
                             flag_args = list(
                               p_thresh   = 0.01,
                               k1         = 0.4,
                               k_c        = 0.01,
                               n_consec   = 2L,
                               min_window = 10L,
                               w_min      = 21L,
                               w_max      = 21L,
                               d2_relax   = -0.01
                             ),
                             allow_scale = NULL,
                             level = 0.95,
                             use_ci = TRUE,
                             buffer_weeks = 0L,
                             n_cores = parallel::detectCores() - 1L,
                             min_obs = 4L,
                             curvature_ratio = 1.0,
                             template_shift = 0L,
                             peak_weight_boost = 1,
                             peak_weight_decay = 0.3,
                             # --- Alignment loss weighting (Improvement C) ---
                             align_trough_weight = 0.1,
                             align_rise_weight = 1.0,
                             align_peak_decay = 0.3,
                             # --- Multi-template ensemble (Improvement A) ---
                             use_multi_template = TRUE,
                             ref_method = "fs",
                             multi_temperature = 0.25,
                             multi_top_k = NULL,
                             multi_blend_alpha = 1.0,
                             slope_weight = 8.0,
                             slope_window = 6L,
                             dynamic_temp = FALSE,
                             dynamic_temp_pivot = 10L,
                             checkpoint_file = NULL,
                             verbose = TRUE,
                             timing_mode = c("legacy", "fractional"),
                             timing_truth = NULL,
                             checkpoint_identity = NULL) {
  timing_mode <- match.arg(timing_mode)
  all_seasons <- sort(unique(as.character(allD$season)))

  # Exclude bad seasons from data and universe before any other logic
  if (!is.null(exclude_seasons)) {
    allD <- dplyr::filter(allD, !season %in% exclude_seasons)
    all_seasons <- setdiff(all_seasons, exclude_seasons)
  }

  if (is.null(test_seasons)) test_seasons <- all_seasons

  bad <- setdiff(test_seasons, all_seasons)
  if (length(bad) > 0) {
    stop("test_seasons not found in allD: ", paste(bad, collapse = ", "))
  }

  if (!is.null(train_seasons)) {
    bad_tr <- setdiff(train_seasons, all_seasons)
    if (length(bad_tr) > 0) {
      stop("train_seasons not found in allD: ", paste(bad_tr, collapse = ", "))
    }
  }

  if (!is.null(checkpoint_file) && is.null(checkpoint_identity)) {
    checkpoint_identity <- list(
      schema = "page_m1_walkforward_checkpoint",
      version = 1L,
      data_id = digest::digest(list(
        data = allD,
        test_seasons = test_seasons,
        train_seasons = train_seasons,
        exclude_seasons = exclude_seasons,
        params = params,
        manual_labels = manual_labels,
        flag_args = flag_args,
        k_deriv = k_deriv,
        k_ref = k_ref,
        n_weeks = n_weeks,
        allow_scale = allow_scale,
        level = level,
        use_ci = use_ci,
        buffer_weeks = buffer_weeks,
        min_obs = min_obs,
        curvature_ratio = curvature_ratio,
        template_shift = template_shift,
        peak_weight_boost = peak_weight_boost,
        peak_weight_decay = peak_weight_decay,
        align_trough_weight = align_trough_weight,
        align_rise_weight = align_rise_weight,
        align_peak_decay = align_peak_decay,
        use_multi_template = use_multi_template,
        ref_method = ref_method,
        multi_temperature = multi_temperature,
        multi_top_k = multi_top_k,
        multi_blend_alpha = multi_blend_alpha,
        slope_weight = slope_weight,
        slope_window = slope_window,
        dynamic_temp = dynamic_temp,
        dynamic_temp_pivot = dynamic_temp_pivot,
        n_cores = n_cores,
        timing_mode = timing_mode,
        timing_truth = timing_truth,
        walk_start = walk_start,
        walk_end = walk_end,
        n_weeks = n_weeks,
        ref_method = ref_method
      ), algo = "sha256")
    )
  }

  # --- set up parallel plan; restore on exit ---
  n_workers <- max(1L, as.integer(n_cores))
  old_plan <- future::plan()
  .page_set_parallel_plan(n_workers)
  on.exit(future::plan(old_plan), add = TRUE)

  params_list <- vector("list", length(test_seasons))
  forecast_list <- vector("list", length(test_seasons))
  ref_list <- vector("list", length(test_seasons))
  names(params_list) <- names(forecast_list) <- names(ref_list) <- test_seasons

  # --- Resume from checkpoint if available ---
  completed_seasons <- character(0)
  if (!is.null(checkpoint_file) && file.exists(checkpoint_file)) {
    ckpt <- tryCatch(readRDS(checkpoint_file), error = function(e) NULL)
    usable <- is.list(ckpt) &&
      identical(ckpt$schema, "page_m1_walkforward_checkpoint") &&
      identical(ckpt$identity, checkpoint_identity)
    if (isTRUE(usable)) {
      completed_seasons <- ckpt$completed_seasons %||% character(0)
      for (s in intersect(completed_seasons, test_seasons)) {
        params_list[[s]] <- ckpt$params_list[[s]]
        forecast_list[[s]] <- ckpt$forecast_list[[s]]
        ref_list[[s]] <- ckpt$ref_list[[s]]
      }
    }
    if (verbose && isTRUE(usable) && length(completed_seasons)) {
      message(sprintf(
        "[loso_walkforward] Resuming from checkpoint: %d/%d seasons done (%s)",
        length(intersect(completed_seasons, test_seasons)),
        length(test_seasons),
        paste(intersect(completed_seasons, test_seasons), collapse = ", ")
      ))
    } else if (verbose && !isTRUE(usable)) {
      message("[loso_walkforward] Ignoring checkpoint with mismatched provenance.")
    }
  }

  for (test_s in test_seasons) {
    # Skip seasons already completed in checkpoint
    if (test_s %in% completed_seasons) {
      if (verbose) message(sprintf("[loso_walkforward] Skipping %s (from checkpoint)", test_s))
      next
    }

    tr_seasons <- if (!is.null(train_seasons)) {
      train_seasons
    } else {
      setdiff(all_seasons, test_s)
    }

    if (length(tr_seasons) < 2) {
      stop("Fewer than 2 training seasons for test season '", test_s, "'.")
    }

    # --- resolve walk bounds for this season ---
    season_weeks <- dplyr::filter(allD, season == test_s)$weekF
    walk_end_s <- if (!is.null(walk_end)) as.integer(walk_end) else max(season_weeks, na.rm = TRUE)

    # --- 1. Build aligned training data (retrospective) ---
    train_allD <- dplyr::filter(allD, season %in% tr_seasons)
    res_deriv <- estimateDerivs(train_allD,
      k = k_deriv,
      peak_weight_boost = peak_weight_boost,
      peak_weight_decay = peak_weight_decay,
      ignition_weeks = manual_labels
    )

    train_outs <- res_deriv$data |>
      dplyr::group_by(season) |>
      dplyr::group_split(.keep = TRUE) |>
      purrr::map(~ do.call(
        flagIgnition,
        c(list(df = .x, manual_labels = manual_labels), flag_args)
      ))

    aligned_train <- alignIgnition(train_outs)

    # In the fractional workflow, replace the integer manual-label anchor in
    # the retrospective training seasons with the midpoint target used by M0.
    # This keeps the reference curve and all downstream alignment coordinates
    # on the same timing scale as the prospective detector.
    if (timing_mode == "fractional" && !is.null(timing_truth)) {
      if (!is.data.frame(timing_truth) ||
        !all(c("season", "ignition_target_weekF") %in% names(timing_truth))) {
        stop("`timing_truth` must contain season and ignition_target_weekF.", call. = FALSE)
      }
      tt <- timing_truth[, c("season", "ignition_target_weekF"), drop = FALSE]
      tt$season <- as.character(tt$season)
      if (anyDuplicated(tt$season) || any(!is.finite(tt$ignition_target_weekF))) {
        stop("`timing_truth` must have one finite target per season.", call. = FALSE)
      }
      target <- stats::setNames(as.numeric(tt$ignition_target_weekF), tt$season)
      aligned_train$season <- as.character(aligned_train$season)
      aligned_train$iWeekF <- unname(target[aligned_train$season])
      aligned_train$iWeek <- aligned_train$iWeekF
      anchor <- stats::median(target[intersect(names(target), tr_seasons)], na.rm = TRUE)
      if (!is.finite(anchor)) stop("Fractional timing truth has no training-season targets.", call. = FALSE)
      aligned_train$phase <- as.integer(aligned_train$weekF >= aligned_train$iWeekF)
      aligned_train$newWeek <- .page_shift_week(
        aligned_train$weekF, aligned_train$iWeekF, anchor
      )
      .dom <- .page_alignment_domain(aligned_train$newWeek, .page_template_weeks())
      aligned_train$alignment_in_domain <- .dom$in_domain
      aligned_train$alignment_out_of_domain <- .dom$out_of_domain
      attr(aligned_train, "anchorWeek") <- anchor
    }

    # --- 2. Fit reference curve on aligned training data ---
    if (use_multi_template && ref_method != "fs") {
      warning(sprintf("[loso_walkforward] ref_method='%s' ignored when use_multi_template=TRUE; forcing 'fs' (required for eta_mat).", ref_method))
    }
    ref_meth <- if (use_multi_template) "fs" else ref_method
    ref <- tryCatch(
      estimateRef(
        alignedD = aligned_train, exSeason = character(0),
        k = k_ref, n_weeks = n_weeks,
        method = ref_meth,
        timing_mode = timing_mode
      ),
      error = function(e) {
        stop(
          "M1 reference fit failed for fold `", test_s,
          "` with k_ref=", as.integer(k_ref), ": ", conditionMessage(e),
          call. = FALSE
        )
      }
    )

    # Store original (unshifted) template for plotting, then apply lag if requested
    ref$g_ref_fun_orig <- ref$g_ref_fun
    if (as.integer(template_shift) != 0L) {
      s_int <- as.integer(template_shift)
      orig_fun <- ref$g_ref_fun
      orig_mu_se <- ref$g_ref_mu_se
      orig_safe <- ref$g_ref_safe
      ref$g_ref_fun <- function(u) orig_fun(u - s_int)
      ref$g_ref_safe <- function(u) orig_fun(pmin(pmax(u - s_int, 1L), n_weeks))
      ref$g_ref_mu_se <- function(u) orig_mu_se(u - s_int)
    }

    hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)
    ref_list[[test_s]] <- ref

    # iWeek_true from manual_labels (ground truth for diagnostics)
    iWeek_true <- if (timing_mode == "fractional" && !is.null(timing_truth) &&
      test_s %in% as.character(timing_truth$season)) {
      as.numeric(timing_truth$ignition_target_weekF[
        match(test_s, as.character(timing_truth$season))
      ])
    } else if (!is.null(manual_labels) && test_s %in% names(manual_labels)) {
      as.integer(manual_labels[[test_s]])
    } else {
      NA_integer_
    }

    # --- 3. Prospective ignition detection on test season (run once) ---
    raw_test_D <- dplyr::filter(allD, season == test_s, weekF <= walk_end_s)
    det_start <- if (!is.null(walk_start)) as.integer(walk_start) else 1L
    ign_out <- run_ignition_weekly(
      currentSeason  = raw_test_D,
      ign_fit_or_gam = NULL,
      params         = params,
      start_week     = det_start,
      timing_mode    = timing_mode
    )

    # --- resolve walk_start for this season ---
    walk_start_s <- if (!is.null(walk_start)) {
      as.integer(walk_start)
    } else if (!is.na(ign_out$ign_week_locked)) {
      as.integer(ign_out$ign_week_locked)
    } else {
      walk_end_s + 1L # empty sequence -- no ignition detected
    }
    eval_weeks_s <- seq(walk_start_s, walk_end_s)

    if (verbose) {
      message(sprintf(
        "[loso_walkforward] test: %-9s | train: %d seasons | weeks %d-%d | workers: %d",
        test_s, length(tr_seasons), walk_start_s, walk_end_s, n_workers
      ))
    }

    # capture locals for parallel workers
    .ref <- ref
    .hyper <- hyper
    .allD_test <- dplyr::filter(allD, season == test_s)
    .allow_scale <- allow_scale
    .test_s <- test_s
    .tr_seasons <- tr_seasons
    .min_obs <- min_obs
    .level <- level
    .iWeek_true <- iWeek_true
    .ign_out <- ign_out
    .use_ci <- use_ci
    .buffer_weeks <- buffer_weeks
    .curvature_ratio <- curvature_ratio
    .trough_weight <- align_trough_weight
    .rise_weight <- align_rise_weight
    .peak_decay <- align_peak_decay
    .use_multi <- use_multi_template
    .multi_temp <- multi_temperature
    .multi_top_k <- multi_top_k
    .multi_blend <- multi_blend_alpha
    .slope_weight <- slope_weight
    .slope_window <- slope_window
    .dynamic_temp <- dynamic_temp
    .dynamic_temp_pivot <- dynamic_temp_pivot
    .timing_mode <- timing_mode

    # --- 4. Walk-forward: parallelise over eval_weeks ---
    week_results <- furrr::future_map(eval_weeks_s, function(ew) {
      season_data_to_ew <- dplyr::filter(.allD_test, weekF <= ew)
      .page_assert_prefix(season_data_to_ew, ew, label = "M1 walk-forward input")
      n_obs <- nrow(season_data_to_ew)

      # Dispatch: multi-template ensemble or single-template alignment
      if (.use_multi && !is.null(.ref$eta_mat)) {
        ap <- run_alignment_prospective_multi(
          currentSeason = season_data_to_ew,
          ref = .ref,
          hyper = .hyper,
          ign_out = .ign_out,
          use_ci = .use_ci,
          buffer_weeks = .buffer_weeks,
          allow_scale = .allow_scale,
          level = .level,
          min_obs = .min_obs,
          curvature_ratio = .curvature_ratio,
          trough_weight = .trough_weight,
          rise_weight = .rise_weight,
          peak_decay = .peak_decay,
          temperature = .multi_temp,
          top_k = .multi_top_k,
          blend_alpha = .multi_blend,
          slope_weight = .slope_weight,
          slope_window = .slope_window,
          dynamic_temp = .dynamic_temp,
          dynamic_temp_pivot = .dynamic_temp_pivot,
          timing_mode = .timing_mode
        )
      } else {
        ap <- run_alignment_prospective(
          currentSeason = season_data_to_ew,
          ref = .ref,
          hyper = .hyper,
          params = NULL,
          ign_out = .ign_out,
          use_ci = .use_ci,
          buffer_weeks = .buffer_weeks,
          allow_scale = .allow_scale,
          level = .level,
          min_obs = .min_obs,
          curvature_ratio = .curvature_ratio,
          trough_weight = .trough_weight,
          rise_weight = .rise_weight,
          peak_decay = .peak_decay,
          timing_mode = .timing_mode
        )
      }

      if (ap$state %in% c("pre_ignition", "alignment_failed")) {
        ign_locked_w <- .ign_out$ign_week_locked
        alignment_failed <- identical(ap$state, "alignment_failed")
        reason <- if (alignment_failed) {
          ap$fallback_reason %||% "alignment_failed"
        } else if (is.na(ign_locked_w) || ign_locked_w > ew) {
          "no_ignition"
        } else if (n_obs < .min_obs) {
          "too_few_obs"
        } else {
          "alignment_error"
        }
        iWeek_hat_ew <- if (alignment_failed && is.finite(ap$iWeek_hat)) {
          if (.timing_mode == "fractional") as.numeric(ap$iWeek_hat) else as.integer(ap$iWeek_hat)
        } else if (!is.na(ign_locked_w) && ign_locked_w <= ew) {
          if (.timing_mode == "fractional") {
            as.numeric(.ign_out$iWeek_hat_lockedF)
          } else {
            as.integer(.ign_out$iWeek_hat_locked)
          }
        } else {
          NA_integer_
        }

        na_row <- tibble::tibble(
          season = .test_s, eval_week = ew, n_obs = n_obs,
          iWeek_hat = iWeek_hat_ew, iWeek_true = .iWeek_true,
          tau = NA_real_, delta = NA_real_, a = NA_real_, b = NA_real_,
          allow_scale = NA, delta_on = NA,
          t_peak = NA_real_, t_peak_median = NA_real_, t_peak_lo = NA_real_, t_peak_hi = NA_real_,
          peak_weekF = if (.timing_mode == "fractional") NA_real_ else NA_integer_, peak_passed = FALSE,
          fallback_reason = reason,
          n_train = length(.tr_seasons), anchorWeek = .ref$anchorWeek
        )
        return(list(params = na_row, forecast = NULL))
      }

      params_row <- tibble::tibble(
        season          = .test_s,
        eval_week       = ew,
        n_obs           = n_obs,
        iWeek_hat       = ap$iWeek_hat,
        iWeek_true      = .iWeek_true,
        tau             = ap$tau,
        delta           = ap$delta,
        a               = ap$a,
        b               = ap$b,
        allow_scale     = ap$allow_scale,
        delta_on        = ap$delta_on,
        t_peak          = ap$t_peak,
        t_peak_median   = ap$t_peak_median,
        t_peak_lo       = ap$t_peak_ci[1],
        t_peak_hi       = ap$t_peak_ci[2],
        peak_weekF      = ap$peak_weekF,
        peak_passed     = ap$peak_passed,
        fallback_reason = ap$fallback_reason,
        n_train         = length(.tr_seasons),
        anchorWeek      = .ref$anchorWeek
      )

      forecast_row <- ap$forecast_df |>
        dplyr::mutate(
          season = .test_s, eval_week = ew,
          newWeek = as.numeric(newWeek),
          p_hat = as.numeric(p_hat),
          p_lo = as.numeric(p_lo),
          p_hi = as.numeric(p_hi)
        ) |>
        dplyr::select(season, eval_week, newWeek, p_hat, p_lo, p_hi, kind)

      list(params = params_row, forecast = forecast_row)
    }, .options = furrr::furrr_options(seed = TRUE))

    params_list[[test_s]] <- dplyr::bind_rows(purrr::map(week_results, "params"))
    forecast_list[[test_s]] <- dplyr::bind_rows(purrr::map(week_results, "forecast"))

    # --- Checkpoint: save progress after each season ---
    if (!is.null(checkpoint_file)) {
      completed_seasons <- union(completed_seasons, test_s)
      saveRDS(list(
        schema = "page_m1_walkforward_checkpoint",
        version = 1L,
        identity = checkpoint_identity,
        completed_seasons = completed_seasons,
        params_list = params_list[completed_seasons],
        forecast_list = forecast_list[completed_seasons],
        ref_list = ref_list[completed_seasons]
      ), checkpoint_file)
      if (verbose) {
        message(sprintf(
          "[loso_walkforward] Checkpoint saved: %d/%d seasons (%s)",
          length(completed_seasons), length(test_seasons), checkpoint_file
        ))
      }
    }
  }

  # Flatten any list columns that furrr parallel serialisation may introduce
  flatten_list_cols <- function(df) {
    for (nm in names(df)) {
      if (is.list(df[[nm]])) {
        df[[nm]] <- tryCatch(
          as.numeric(unlist(df[[nm]])),
          warning = function(w) unlist(df[[nm]]),
          error   = function(e) unlist(df[[nm]])
        )
      }
    }
    df
  }

  list(
    params_df   = flatten_list_cols(dplyr::bind_rows(params_list)),
    forecast_df = flatten_list_cols(dplyr::bind_rows(forecast_list)),
    ref_list    = ref_list
  )
}


# Multi-specification walk-forward used by tune_m1_alignment(). Every spec in a
# group must share all alignment-affecting inputs and differ only in the
# weighting parameters carried in `weight_sets`. The expensive fold preparation,
# reference fit, hyperparameter learning, and per-eval-week template alignment
# are computed once and reused across the group; only the softmax reweighting
# is repeated. Per-spec checkpoints use the same schema and identity as
# loso_walkforward() so restart behavior is unchanged.
#' @keywords internal
loso_walkforward_weights <- function(allD,
                                     params,
                                     weight_sets,
                                     checkpoint_files = NULL,
                                     checkpoint_identities = NULL,
                                     walk_start = NULL,
                                     walk_end = NULL,
                                     manual_labels = NULL,
                                     train_seasons = NULL,
                                     test_seasons = NULL,
                                     exclude_seasons = NULL,
                                     k_deriv = 10L,
                                     k_ref = 10L,
                                     n_weeks = 52L,
                                     flag_args = list(
                                       p_thresh   = 0.01,
                                       k1         = 0.4,
                                       k_c        = 0.01,
                                       n_consec   = 2L,
                                       min_window = 10L,
                                       w_min      = 21L,
                                       w_max      = 21L,
                                       d2_relax   = -0.01
                                     ),
                                     allow_scale = NULL,
                                     level = 0.95,
                                     use_ci = TRUE,
                                     buffer_weeks = 0L,
                                     n_cores = parallel::detectCores() - 1L,
                                     min_obs = 4L,
                                     curvature_ratio = 1.0,
                                     template_shift = 0L,
                                     peak_weight_boost = 1,
                                     peak_weight_decay = 0.3,
                                     align_trough_weight = 0.1,
                                     align_rise_weight = 1.0,
                                     align_peak_decay = 0.3,
                                     use_multi_template = TRUE,
                                     ref_method = "fs",
                                     multi_top_k = NULL,
                                     multi_blend_alpha = 1.0,
                                     timing_mode = c("legacy", "fractional"),
                                     timing_truth = NULL,
                                     verbose = TRUE) {
  timing_mode <- match.arg(timing_mode)
  spec_ids <- names(weight_sets)
  if (is.null(spec_ids) || any(!nzchar(spec_ids))) {
    stop("`weight_sets` must be a named list keyed by spec id.", call. = FALSE)
  }
  all_seasons <- sort(unique(as.character(allD$season)))

  if (!is.null(exclude_seasons)) {
    allD <- dplyr::filter(allD, !season %in% exclude_seasons)
    all_seasons <- setdiff(all_seasons, exclude_seasons)
  }

  if (is.null(test_seasons)) test_seasons <- all_seasons
  bad <- setdiff(test_seasons, all_seasons)
  if (length(bad) > 0) {
    stop("test_seasons not found in allD: ", paste(bad, collapse = ", "))
  }
  if (!is.null(train_seasons)) {
    bad_tr <- setdiff(train_seasons, all_seasons)
    if (length(bad_tr) > 0) {
      stop("train_seasons not found in allD: ", paste(bad_tr, collapse = ", "))
    }
  }

  n_workers <- max(1L, as.integer(n_cores))
  old_plan <- future::plan()
  .page_set_parallel_plan(n_workers)
  on.exit(future::plan(old_plan), add = TRUE)

  params_list <- vector("list", length(spec_ids))
  forecast_list <- vector("list", length(spec_ids))
  names(params_list) <- names(forecast_list) <- spec_ids
  for (sid in spec_ids) {
    params_list[[sid]] <- vector("list", length(test_seasons))
    forecast_list[[sid]] <- vector("list", length(test_seasons))
    names(params_list[[sid]]) <- names(forecast_list[[sid]]) <- test_seasons
  }
  ref_list <- vector("list", length(test_seasons))
  names(ref_list) <- test_seasons

  completed <- stats::setNames(vector("list", length(spec_ids)), spec_ids)
  for (sid in spec_ids) {
    completed[[sid]] <- character(0)
    ckpt_file <- checkpoint_files[[sid]]
    if (!is.null(ckpt_file) && file.exists(ckpt_file)) {
      ckpt <- tryCatch(readRDS(ckpt_file), error = function(e) NULL)
      usable <- is.list(ckpt) &&
        identical(ckpt$schema, "page_m1_walkforward_checkpoint") &&
        identical(ckpt$identity, checkpoint_identities[[sid]])
      if (isTRUE(usable)) {
        completed[[sid]] <- ckpt$completed_seasons %||% character(0)
        for (s in intersect(completed[[sid]], test_seasons)) {
          params_list[[sid]][[s]] <- ckpt$params_list[[s]]
          forecast_list[[sid]][[s]] <- ckpt$forecast_list[[s]]
          if (is.null(ref_list[[s]])) ref_list[[s]] <- ckpt$ref_list[[s]]
        }
      }
    }
  }

  for (test_s in test_seasons) {
    need_sids <- spec_ids[!vapply(
      spec_ids, function(sid) test_s %in% completed[[sid]], logical(1)
    )]
    if (!length(need_sids)) {
      if (verbose) message(sprintf("[loso_walkforward_weights] Skipping %s (all specs checkpointed)", test_s))
      next
    }

    tr_seasons <- if (!is.null(train_seasons)) {
      train_seasons
    } else {
      setdiff(all_seasons, test_s)
    }
    if (length(tr_seasons) < 2) {
      stop("Fewer than 2 training seasons for test season '", test_s, "'.")
    }

    season_weeks <- dplyr::filter(allD, season == test_s)$weekF
    walk_end_s <- if (!is.null(walk_end)) as.integer(walk_end) else max(season_weeks, na.rm = TRUE)

    train_allD <- dplyr::filter(allD, season %in% tr_seasons)
    res_deriv <- estimateDerivs(train_allD,
      k = k_deriv,
      peak_weight_boost = peak_weight_boost,
      peak_weight_decay = peak_weight_decay,
      ignition_weeks = manual_labels
    )

    train_outs <- res_deriv$data |>
      dplyr::group_by(season) |>
      dplyr::group_split(.keep = TRUE) |>
      purrr::map(~ do.call(
        flagIgnition,
        c(list(df = .x, manual_labels = manual_labels), flag_args)
      ))

    aligned_train <- alignIgnition(train_outs)

    if (timing_mode == "fractional" && !is.null(timing_truth)) {
      if (!is.data.frame(timing_truth) ||
        !all(c("season", "ignition_target_weekF") %in% names(timing_truth))) {
        stop("`timing_truth` must contain season and ignition_target_weekF.", call. = FALSE)
      }
      tt <- timing_truth[, c("season", "ignition_target_weekF"), drop = FALSE]
      tt$season <- as.character(tt$season)
      if (anyDuplicated(tt$season) || any(!is.finite(tt$ignition_target_weekF))) {
        stop("`timing_truth` must have one finite target per season.", call. = FALSE)
      }
      target <- stats::setNames(as.numeric(tt$ignition_target_weekF), tt$season)
      aligned_train$season <- as.character(aligned_train$season)
      aligned_train$iWeekF <- unname(target[aligned_train$season])
      aligned_train$iWeek <- aligned_train$iWeekF
      anchor <- stats::median(target[intersect(names(target), tr_seasons)], na.rm = TRUE)
      if (!is.finite(anchor)) stop("Fractional timing truth has no training-season targets.", call. = FALSE)
      aligned_train$phase <- as.integer(aligned_train$weekF >= aligned_train$iWeekF)
      aligned_train$newWeek <- .page_shift_week(
        aligned_train$weekF, aligned_train$iWeekF, anchor
      )
      .dom <- .page_alignment_domain(aligned_train$newWeek, .page_template_weeks())
      aligned_train$alignment_in_domain <- .dom$in_domain
      aligned_train$alignment_out_of_domain <- .dom$out_of_domain
      attr(aligned_train, "anchorWeek") <- anchor
    }

    if (use_multi_template && ref_method != "fs") {
      warning(sprintf("[loso_walkforward_weights] ref_method='%s' ignored when use_multi_template=TRUE; forcing 'fs' (required for eta_mat).", ref_method))
    }
    ref_meth <- if (use_multi_template) "fs" else ref_method
    ref <- tryCatch(
      estimateRef(
        alignedD = aligned_train, exSeason = character(0),
        k = k_ref, n_weeks = n_weeks,
        method = ref_meth,
        timing_mode = timing_mode
      ),
      error = function(e) {
        stop(
          "M1 reference fit failed for fold `", test_s,
          "` with k_ref=", as.integer(k_ref), ": ", conditionMessage(e),
          call. = FALSE
        )
      }
    )

    ref$g_ref_fun_orig <- ref$g_ref_fun
    if (as.integer(template_shift) != 0L) {
      s_int <- as.integer(template_shift)
      orig_fun <- ref$g_ref_fun
      orig_mu_se <- ref$g_ref_mu_se
      orig_safe <- ref$g_ref_safe
      ref$g_ref_fun <- function(u) orig_fun(u - s_int)
      ref$g_ref_safe <- function(u) orig_fun(pmin(pmax(u - s_int, 1L), n_weeks))
      ref$g_ref_mu_se <- function(u) orig_mu_se(u - s_int)
    }

    hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)
    ref_list[[test_s]] <- ref

    iWeek_true <- if (timing_mode == "fractional" && !is.null(timing_truth) &&
      test_s %in% as.character(timing_truth$season)) {
      as.numeric(timing_truth$ignition_target_weekF[
        match(test_s, as.character(timing_truth$season))
      ])
    } else if (!is.null(manual_labels) && test_s %in% names(manual_labels)) {
      as.integer(manual_labels[[test_s]])
    } else {
      NA_integer_
    }

    raw_test_D <- dplyr::filter(allD, season == test_s, weekF <= walk_end_s)
    det_start <- if (!is.null(walk_start)) as.integer(walk_start) else 1L
    ign_out <- run_ignition_weekly(
      currentSeason  = raw_test_D,
      ign_fit_or_gam = NULL,
      params         = params,
      start_week     = det_start,
      timing_mode    = timing_mode
    )

    walk_start_s <- if (!is.null(walk_start)) {
      as.integer(walk_start)
    } else if (!is.na(ign_out$ign_week_locked)) {
      as.integer(ign_out$ign_week_locked)
    } else {
      walk_end_s + 1L
    }
    eval_weeks_s <- seq(walk_start_s, walk_end_s)

    if (verbose) {
      message(sprintf(
        "[loso_walkforward_weights] test: %-9s | %d specs | train: %d | weeks %d-%d | workers: %d",
        test_s, length(need_sids), length(tr_seasons), walk_start_s, walk_end_s, n_workers
      ))
    }

    .ref <- ref
    .hyper <- hyper
    .allD_test <- dplyr::filter(allD, season == test_s)
    .allow_scale <- allow_scale
    .test_s <- test_s
    .tr_seasons <- tr_seasons
    .min_obs <- min_obs
    .level <- level
    .iWeek_true <- iWeek_true
    .ign_out <- ign_out
    .use_ci <- use_ci
    .buffer_weeks <- buffer_weeks
    .curvature_ratio <- curvature_ratio
    .trough_weight <- align_trough_weight
    .rise_weight <- align_rise_weight
    .peak_decay <- align_peak_decay
    .use_multi <- use_multi_template
    .multi_top_k <- multi_top_k
    .multi_blend <- multi_blend_alpha
    .timing_mode <- timing_mode
    .weight_sets <- weight_sets[need_sids]

    week_results <- furrr::future_map(eval_weeks_s, function(ew) {
      season_data_to_ew <- dplyr::filter(.allD_test, weekF <= ew)
      .page_assert_prefix(season_data_to_ew, ew, label = "M1 walk-forward input")
      n_obs <- nrow(season_data_to_ew)

      ap_list <- if (!is.null(.ref$eta_mat)) {
        run_alignment_prospective_multi_weights(
          currentSeason      = season_data_to_ew,
          ref                = .ref,
          hyper              = .hyper,
          ign_out            = .ign_out,
          weight_sets        = .weight_sets,
          use_ci             = .use_ci,
          buffer_weeks       = .buffer_weeks,
          allow_scale        = .allow_scale,
          level              = .level,
          min_obs            = .min_obs,
          curvature_ratio    = .curvature_ratio,
          trough_weight      = .trough_weight,
          rise_weight        = .rise_weight,
          peak_decay         = .peak_decay,
          top_k              = .multi_top_k,
          blend_alpha        = .multi_blend,
          timing_mode        = .timing_mode
        )
      } else {
        # Same fallback as loso_walkforward(): without eta_mat the
        # single-template path is used and the weighting axes do not apply.
        ap_single <- run_alignment_prospective(
          currentSeason   = season_data_to_ew,
          ref             = .ref,
          hyper           = .hyper,
          params          = NULL,
          ign_out         = .ign_out,
          use_ci          = .use_ci,
          buffer_weeks    = .buffer_weeks,
          allow_scale     = .allow_scale,
          level           = .level,
          min_obs         = .min_obs,
          curvature_ratio = .curvature_ratio,
          trough_weight   = .trough_weight,
          rise_weight     = .rise_weight,
          peak_decay      = .peak_decay,
          timing_mode     = .timing_mode
        )
        stats::setNames(rep(list(ap_single), length(.weight_sets)), names(.weight_sets))
      }

      out <- vector("list", length(.weight_sets))
      names(out) <- names(.weight_sets)
      for (sid in names(.weight_sets)) {
        ap <- ap_list[[sid]]
        if (ap$state %in% c("pre_ignition", "alignment_failed")) {
          ign_locked_w <- .ign_out$ign_week_locked
          alignment_failed <- identical(ap$state, "alignment_failed")
          reason <- if (alignment_failed) {
            ap$fallback_reason %||% "alignment_failed"
          } else if (is.na(ign_locked_w) || ign_locked_w > ew) {
            "no_ignition"
          } else if (n_obs < .min_obs) {
            "too_few_obs"
          } else {
            "alignment_error"
          }
          iWeek_hat_ew <- if (alignment_failed && is.finite(ap$iWeek_hat)) {
            if (.timing_mode == "fractional") as.numeric(ap$iWeek_hat) else as.integer(ap$iWeek_hat)
          } else if (!is.na(ign_locked_w) && ign_locked_w <= ew) {
            if (.timing_mode == "fractional") {
              as.numeric(.ign_out$iWeek_hat_lockedF)
            } else {
              as.integer(.ign_out$iWeek_hat_locked)
            }
          } else {
            NA_integer_
          }
          na_row <- tibble::tibble(
            season = .test_s, eval_week = ew, n_obs = n_obs,
            iWeek_hat = iWeek_hat_ew, iWeek_true = .iWeek_true,
            tau = NA_real_, delta = NA_real_, a = NA_real_, b = NA_real_,
            allow_scale = NA, delta_on = NA,
            t_peak = NA_real_, t_peak_median = NA_real_, t_peak_lo = NA_real_, t_peak_hi = NA_real_,
            peak_weekF = if (.timing_mode == "fractional") NA_real_ else NA_integer_, peak_passed = FALSE,
            fallback_reason = reason,
            n_train = length(.tr_seasons), anchorWeek = .ref$anchorWeek
          )
          out[[sid]] <- list(params = na_row, forecast = NULL)
          next
        }
        params_row <- tibble::tibble(
          season          = .test_s,
          eval_week       = ew,
          n_obs           = n_obs,
          iWeek_hat       = ap$iWeek_hat,
          iWeek_true      = .iWeek_true,
          tau             = ap$tau,
          delta           = ap$delta,
          a               = ap$a,
          b               = ap$b,
          allow_scale     = ap$allow_scale,
          delta_on        = ap$delta_on,
          t_peak          = ap$t_peak,
          t_peak_median   = ap$t_peak_median,
          t_peak_lo       = ap$t_peak_ci[1],
          t_peak_hi       = ap$t_peak_ci[2],
          peak_weekF      = ap$peak_weekF,
          peak_passed     = ap$peak_passed,
          fallback_reason = ap$fallback_reason,
          n_train         = length(.tr_seasons),
          anchorWeek      = .ref$anchorWeek
        )
        forecast_row <- ap$forecast_df |>
          dplyr::mutate(
            season = .test_s, eval_week = ew,
            newWeek = as.numeric(newWeek),
            p_hat = as.numeric(p_hat),
            p_lo = as.numeric(p_lo),
            p_hi = as.numeric(p_hi)
          ) |>
          dplyr::select(season, eval_week, newWeek, p_hat, p_lo, p_hi, kind)
        out[[sid]] <- list(params = params_row, forecast = forecast_row)
      }
      out
    }, .options = furrr::furrr_options(seed = TRUE))

    for (sid in need_sids) {
      params_list[[sid]][[test_s]] <- dplyr::bind_rows(
        purrr::map(week_results, function(wk) wk[[sid]]$params)
      )
      forecast_list[[sid]][[test_s]] <- dplyr::bind_rows(
        purrr::map(week_results, function(wk) wk[[sid]]$forecast)
      )
    }

    for (sid in need_sids) {
      completed[[sid]] <- union(completed[[sid]], test_s)
      if (!is.null(checkpoint_files[[sid]])) {
        saveRDS(list(
          schema = "page_m1_walkforward_checkpoint",
          version = 1L,
          identity = checkpoint_identities[[sid]],
          completed_seasons = completed[[sid]],
          params_list = params_list[[sid]][completed[[sid]]],
          forecast_list = forecast_list[[sid]][completed[[sid]]],
          ref_list = ref_list[completed[[sid]]]
        ), checkpoint_files[[sid]])
      }
    }
    if (verbose) {
      message(sprintf(
        "[loso_walkforward_weights] Checkpoint saved: %d specs @ %s",
        length(need_sids), test_s
      ))
    }
  }

  flatten_list_cols <- function(df) {
    for (nm in names(df)) {
      if (is.list(df[[nm]])) {
        df[[nm]] <- tryCatch(
          as.numeric(unlist(df[[nm]])),
          warning = function(w) unlist(df[[nm]]),
          error   = function(e) unlist(df[[nm]])
        )
      }
    }
    df
  }

  stats::setNames(lapply(spec_ids, function(sid) {
    list(
      params_df   = flatten_list_cols(dplyr::bind_rows(params_list[[sid]])),
      forecast_df = flatten_list_cols(dplyr::bind_rows(forecast_list[[sid]])),
      ref_list    = ref_list
    )
  }), spec_ids)
}


#' LOSO grid search over M1 alignment hyperparameters
#'
#' Runs \code{loso_walkforward()} for every combination of candidate values
#' across multiple alignment hyperparameters and scores each specification by
#' prospective peak MAE under three Weibull weighting schemes (same metrics as
#' \code{tune_loso_k()}).
#'
#' Each specification is identified by a short string \code{spec_id}. Results
#' are checkpointed after every completed spec so the search can be resumed
#' after interruption.
#'
#' @param allD Raw data frame passed to \code{loso_walkforward()}.
#' @param params Stage-1 detector parameters list.
#' @param grid A data frame (or tibble) where each row is one parameter
#'   specification. Column names must match arguments of
#'   \code{loso_walkforward()} (e.g. \code{k_ref}, \code{multi_temperature},
#'   \code{template_shift}, \code{align_rise_weight}).
#' @param manual_labels Named integer vector of verified ignition weeks.
#' @param exclude_seasons Character vector of seasons to exclude.
#' @param n_weeks Integer. Template length (default 52).
#' @param n_cores Integer. Workers per \code{loso_walkforward()} call
#'   (default \code{parallel::detectCores() - 1}).
#' @param checkpoint_dir Character. Directory for per-spec checkpoint files
#'   and the results cache (default \code{"data/m1_tune_ckpt"}).
#' @param verbose Logical. Print progress (default \code{TRUE}).
#' @param fail_fast Logical. Stop and return the failing specification and
#'   fold error instead of recording an unevaluable candidate (default `TRUE`).
#' @param ... Additional fixed arguments forwarded to
#'   \code{loso_walkforward()} (e.g. \code{buffer_weeks}, \code{use_ci}).
#'
#' @return A list with elements:
#' \describe{
#'   \item{scores}{Tibble with one row per spec: \code{spec_id} plus the
#'     grid columns, \code{mae_uniform}, \code{mae_exp}, \code{mae_weibull},
#'     \code{n_seasons}, and \code{failure_reason}.}
#'   \item{best}{Single-row tibble for the spec with lowest
#'     \code{mae_weibull}.}
#'   \item{grid}{The input grid (for reference).}
#' }
#'
#' @examples
#' \dontrun{
#' grid <- expand.grid(
#'   k_ref             = c(15L, 20L, 25L),
#'   multi_temperature = c(0.5, 1.0, 2.0),
#'   template_shift    = c(-1L, 0L, 1L),
#'   align_rise_weight = c(1.0, 2.0, 3.0),
#'   stringsAsFactors  = FALSE
#' )
#' res <- tune_m1_alignment(
#'   allD, params, grid,
#'   manual_labels = manual_labels,
#'   exclude_seasons = "2015-16",
#'   use_multi_template = TRUE,
#'   ref_method = "fs"
#' )
#' res$best
#' }
#' @export
tune_m1_alignment <- function(allD,
                              params,
                              grid,
                              manual_labels = NULL,
                              exclude_seasons = NULL,
                              n_weeks = 52L,
                              n_cores = parallel::detectCores() - 1L,
                              checkpoint_dir = "data/m1_tune_ckpt",
                              verbose = TRUE,
                              fail_fast = TRUE,
                              ...) {
  if (!dir.exists(checkpoint_dir)) {
    dir.create(checkpoint_dir, recursive = TRUE)
  }

  results_cache <- file.path(checkpoint_dir, "tune_m1_results.rds")
  dots <- list(...)
  timing_mode_cache <- dots$timing_mode %||% "legacy"
  timing_mode_cache <- match.arg(timing_mode_cache, c("legacy", "fractional"))
  timing_truth_cache <- dots$timing_truth %||% NULL
  cache_identity <- list(
    schema = "page_m1_tuning_checkpoint",
    version = 1L,
    data_id = digest::digest(allD, algo = "sha256"),
    params = params,
    manual_labels = manual_labels,
    exclude_seasons = exclude_seasons,
    n_weeks = n_weeks,
    timing_mode = timing_mode_cache,
    timing_truth = timing_truth_cache,
    fixed_args = dots[setdiff(names(dots), c("timing_mode", "timing_truth"))]
  )

  # Pre-filter excluded seasons once
  if (!is.null(exclude_seasons)) {
    allD <- dplyr::filter(allD, !season %in% exclude_seasons)
  }

  # True peak week per season (observed argmax)
  true_peaks <- allD |>
    dplyr::filter(!is.na(p), is.finite(p), N > 0) |>
    dplyr::group_by(season) |>
    dplyr::slice_max(p, n = 1L, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(season, true_peak_weekF = weekF)

  # Build stable spec IDs. Expanded grids append new rows while retaining the
  # IDs of previously scored rows, allowing the checkpoint to skip them.
  grid <- tibble::as_tibble(grid)
  .validate_m1_grid_support(grid, n_weeks = n_weeks)
  n_specs <- nrow(grid)
  if (!"spec_id" %in% names(grid)) {
    grid$spec_id <- sprintf("s%03d", seq_len(n_specs))
  } else {
    grid$spec_id <- as.character(grid$spec_id)
    missing_ids <- is.na(grid$spec_id) | !nzchar(grid$spec_id)
    if (any(missing_ids)) {
      next_id <- seq_len(sum(missing_ids)) + n_specs
      grid$spec_id[missing_ids] <- sprintf("s%03d", next_id)
    }
    if (anyDuplicated(grid$spec_id)) {
      stop("M1 grid has duplicate spec_id values; preserve existing IDs when expanding.",
        call. = FALSE
      )
    }
  }

  # Load previously completed specs
  if (file.exists(results_cache)) {
    prev <- tryCatch(readRDS(results_cache), error = function(e) NULL)
    usable <- is.list(prev) &&
      identical(prev$schema, "page_m1_tuning_checkpoint") &&
      identical(prev$identity, cache_identity) &&
      is.data.frame(prev$scores)
    if (isTRUE(usable)) {
      done_ids <- as.character(prev$scores$spec_id)
      score_rows <- split(prev$scores, seq_len(nrow(prev$scores)))
    } else {
      done_ids <- character(0)
      score_rows <- list()
    }
    if (verbose && isTRUE(usable)) {
      message(sprintf(
        "[tune_m1] Resuming: %d / %d specs already done.",
        length(done_ids), n_specs
      ))
    } else if (verbose && !isTRUE(usable)) {
      message("[tune_m1] Ignoring checkpoint with mismatched provenance.")
    }
  } else {
    done_ids <- character(0)
    score_rows <- list()
  }

  # Tunable column names (columns in grid that are loso_walkforward args)
  tune_cols <- setdiff(names(grid), "spec_id")

  dots <- list(...)

  # Parameters that only enter the ensemble softmax reweighting. Specs that
  # differ only in these axes share identical fold preparation and template
  # alignment, so they are evaluated in one shared walk-forward pass.
  weight_cols <- c(
    "slope_weight", "multi_temperature", "slope_window",
    "dynamic_temp", "dynamic_temp_pivot"
  )
  non_behavior_cols <- c(
    "allD", "checkpoint_file", "checkpoint_identity", "verbose", "n_cores"
  )

  spec_row <- function(sid) grid[grid$spec_id == sid, , drop = FALSE]

  build_wf_args <- function(spec) {
    wf_args <- list(
      allD            = allD,
      params          = params,
      manual_labels   = manual_labels,
      exclude_seasons = NULL, # already filtered
      n_weeks         = n_weeks,
      n_cores         = n_cores,
      verbose         = FALSE
    )
    for (col in tune_cols) {
      wf_args[[col]] <- spec[[col]]
    }
    for (nm in names(dots)) {
      wf_args[[nm]] <- dots[[nm]]
    }
    sid <- spec$spec_id
    wf_args$checkpoint_file <- file.path(checkpoint_dir, paste0("ckpt_", sid, ".rds"))
    wf_args$checkpoint_identity <- list(
      schema = "page_m1_walkforward_checkpoint",
      version = 1L,
      tuning = cache_identity,
      spec = spec[, setdiff(names(spec), "spec_id"), drop = FALSE]
    )
    wf_args
  }

  score_spec <- function(wf, wf_error, sid) {
    if (is.null(wf)) {
      return(tibble::tibble(
        spec_id         = sid,
        mae_uniform     = NA_real_,
        mae_exp         = NA_real_,
        mae_weibull     = NA_real_,
        mae_med_uniform = NA_real_,
        mae_med_exp     = NA_real_,
        mae_med_weibull = NA_real_,
        n_seasons       = 0L,
        failure_reason  = if (is.null(wf_error)) NA_character_ else wf_error
      ))
    }
    base_df <- wf$params_df |>
      dplyr::left_join(true_peaks, by = "season") |>
      dplyr::filter(!is.na(true_peak_weekF), eval_week <= true_peak_weekF) |>
      dplyr::mutate(
        t      = eval_week - iWeek_true,
        w_unif = 1,
        w_exp  = exp(-(0.1 * t)^1),
        w_weib = exp(-(0.1 * t)^2)
      )

    score_mean <- base_df |>
      dplyr::filter(!is.na(t_peak)) |>
      dplyr::mutate(
        error = abs((if (timing_mode_cache == "fractional") {
          t_peak - as.numeric(anchorWeek) + as.numeric(iWeek_hat)
        } else {
          round(t_peak - anchorWeek + iWeek_hat)
        }) - true_peak_weekF)
      )

    score_med <- base_df |>
      dplyr::filter(!is.na(t_peak_median)) |>
      dplyr::mutate(
        error = abs((if (timing_mode_cache == "fractional") {
          t_peak_median - as.numeric(anchorWeek) + as.numeric(iWeek_hat)
        } else {
          round(t_peak_median - anchorWeek + as.numeric(iWeek_hat))
        }) - true_peak_weekF)
      )

    tibble::tibble(
      spec_id          = sid,
      mae_uniform      = .weighted_mae(score_mean, "w_unif"),
      mae_exp          = .weighted_mae(score_mean, "w_exp"),
      mae_weibull      = .weighted_mae(score_mean, "w_weib"),
      mae_med_uniform  = .weighted_mae(score_med, "w_unif"),
      mae_med_exp      = .weighted_mae(score_med, "w_exp"),
      mae_med_weibull  = .weighted_mae(score_med, "w_weib"),
      n_seasons        = dplyr::n_distinct(base_df$season),
      failure_reason   = NA_character_
    )
  }

  checkpoint_tuning <- function() {
    saveRDS(list(
      schema = "page_m1_tuning_checkpoint",
      version = 1L,
      identity = cache_identity,
      scores = dplyr::bind_rows(score_rows)
    ), results_cache)
  }

  # Group pending specs by alignment signature. All behavior-affecting inputs
  # except the softmax reweighting axes define the signature.
  pending <- grid$spec_id[!grid$spec_id %in% done_ids]
  groups <- list()
  group_order <- character(0)
  for (sid in pending) {
    args <- build_wf_args(spec_row(sid))
    sig_names <- setdiff(names(args), c(non_behavior_cols, weight_cols))
    sig <- digest::digest(args[sig_names], algo = "sha256")
    if (is.null(groups[[sig]])) {
      groups[[sig]] <- character(0)
      group_order <- c(group_order, sig)
    }
    groups[[sig]] <- c(groups[[sig]], sid)
  }

  report_result <- function(row) {
    if (verbose) {
      message(sprintf(
        "  -> mae_weibull = %.3f  mae_med_weibull = %.3f   [%d / %d done]",
        row$mae_weibull, row$mae_med_weibull, length(done_ids), n_specs
      ))
    }
  }

  for (sig in group_order) {
    sids <- groups[[sig]]
    for (sid in sids) {
      if (verbose) {
        spec <- spec_row(sid)
        spec_str <- paste(tune_cols, "=",
          vapply(tune_cols, function(c) as.character(spec[[c]]), character(1)),
          collapse = ", "
        )
        message(sprintf(
          "[tune_m1] Spec %s  %s",
          sid, spec_str
        ))
      }
    }

    # Reuse applies only to the multi-template ensemble; the single-template
    # path ignores the weighting axes, so run it per spec as before.
    use_multi <- build_wf_args(spec_row(sids[[1L]]))$use_multi_template %||% TRUE
    if (length(sids) == 1L || !isTRUE(use_multi)) {
      for (sid in sids) {
        wf_args <- build_wf_args(spec_row(sid))
        wf_error <- NULL
        wf <- tryCatch(
          do.call(loso_walkforward, wf_args),
          error = function(e) {
            wf_error <<- conditionMessage(e)
            NULL
          }
        )
        if (!is.null(wf_error)) {
          msg <- paste0("M1 tuning specification ", sid, " failed: ", wf_error)
          if (isTRUE(fail_fast)) stop(msg, call. = FALSE)
          warning(msg, call. = FALSE)
        }
        row <- score_spec(wf, wf_error, sid)
        score_rows <- c(score_rows, list(row))
        done_ids <- c(done_ids, sid)
        checkpoint_tuning()
        report_result(row)
      }
      next
    }

    # Shared-alignment group: build once, reweight per spec.
    base <- build_wf_args(spec_row(sids[[1L]]))
    weight_sets <- list()
    for (sid in sids) {
      a <- build_wf_args(spec_row(sid))
      weight_sets[[sid]] <- list(
        slope_weight       = a$slope_weight %||% 8.0,
        temperature        = a$multi_temperature %||% 0.25,
        slope_window       = a$slope_window %||% 6L,
        dynamic_temp       = a$dynamic_temp %||% FALSE,
        dynamic_temp_pivot = a$dynamic_temp_pivot %||% 10L
      )
    }
    base <- base[setdiff(names(base), c(weight_cols, "checkpoint_file", "checkpoint_identity"))]
    checkpoint_files <- stats::setNames(
      lapply(sids, function(sid) file.path(checkpoint_dir, paste0("ckpt_", sid, ".rds"))),
      sids
    )
    checkpoint_identities <- stats::setNames(
      lapply(sids, function(sid) {
        spec <- spec_row(sid)
        list(
          schema = "page_m1_walkforward_checkpoint",
          version = 1L,
          tuning = cache_identity,
          spec = spec[, setdiff(names(spec), "spec_id"), drop = FALSE]
        )
      }),
      sids
    )

    wf_error <- NULL
    wf_all <- tryCatch(
      do.call(
        loso_walkforward_weights,
        c(base, list(
          weight_sets = weight_sets,
          checkpoint_files = checkpoint_files,
          checkpoint_identities = checkpoint_identities
        ))
      ),
      error = function(e) {
        wf_error <<- conditionMessage(e)
        NULL
      }
    )
    if (!is.null(wf_error)) {
      msg <- paste0(
        "M1 tuning specifications ", paste(sids, collapse = ", "),
        " (shared alignment group) failed: ", wf_error
      )
      if (isTRUE(fail_fast)) stop(msg, call. = FALSE)
      warning(msg, call. = FALSE)
    }

    for (sid in sids) {
      wf <- if (!is.null(wf_all)) wf_all[[sid]] else NULL
      row <- score_spec(wf, wf_error, sid)
      score_rows <- c(score_rows, list(row))
      done_ids <- c(done_ids, sid)
      checkpoint_tuning()
      report_result(row)
    }
  }

  all_scores <- dplyr::bind_rows(score_rows)

  # Merge grid columns into scores
  scores <- dplyr::left_join(
    grid,
    all_scores,
    by = "spec_id"
  ) |>
    dplyr::arrange(mae_weibull)

  best <- scores |>
    dplyr::slice_min(mae_weibull, n = 1L, with_ties = FALSE, na_rm = TRUE)

  if (verbose) {
    message(sprintf(
      "\n[tune_m1] Best spec: %s  mae_weibull = %.4f",
      best$spec_id, best$mae_weibull
    ))
    for (col in tune_cols) {
      message(sprintf("  %s = %s", col, as.character(best[[col]])))
    }
  }

  list(scores = scores, best = best, grid = grid)
}
