# ============================================================
# Nested M1 -> M2 LOSO: Orchestration, grid search, diagnostics
#
# Sections 6-9: run_fold, cv, grid_search, refit_best,
#               plot_nested_loso_predictions.
# ============================================================

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

# ---------- 6. Orchestrate one fold ----------

#' Run a complete nested LOSO fold
#'
#' Orchestrates the five steps for a single held-out season:
#' build fold -> M1 train -> M2 train -> M1 test -> M2 eval.
#' Returns aggregated results; handles errors gracefully.
#'
#' @param allD Full multi-season data frame.
#' @param test_season Character scalar - the held-out season.
#' @param params M0 detection parameters.
#' @param spec M2 hyperparameter spec object.
#' @param exclude_seasons Character vector of seasons to exclude entirely.
#' @param horizons Integer vector of forecast horizons (default \code{c(1L, 2L)}).
#' @param eval_window Integer; max weeks post-ignition (default 12L).
#' @param k_deriv Integer; basis dim for derivatives (default 10L).
#' @param k_ref Integer; basis dim for reference curve (default 10L).
#' @param ref_method Reference-curve method passed to \code{estimateRef()}.
#' @param n_weeks Integer; reference curve period (default 52L).
#' @param manual_labels Optional manual ignition labels.
#' @param flag_args Named list forwarded to \code{flagIgnition()}.
#' @param allow_scale Passed to M1 walk-forward.
#' @param use_ci Logical; peak CI control (default TRUE).
#' @param buffer_weeks Integer; peak buffer (default 0L).
#' @param min_obs Integer; minimum rows for alignment (default 4L).
#' @param curvature_ratio Numeric; delta curvature gate (default 1.0).
#' @param temperature,rise_weight,trough_weight,peak_decay Ensemble and
#'   alignment-loss controls.
#' @param slope_weight,slope_window Growth-rate similarity controls.
#' @param dynamic_temp,dynamic_temp_pivot Early-season temperature controls.
#' @param top_k,blend_alpha Template filtering and blending controls.
#' @param skip_m1 Logical; reuse supplied M1 predictions when supported.
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
                                 slope_weight       = 8.0,
                                 slope_window       = 6L,
                                 dynamic_temp       = FALSE,
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

  # Step 5: Evaluate M2 (frozen GAM + trend-augmented bias correction)
  eval_out <- nested_loso_m2_eval_frozen_bias(
    allD          = allD,
    fold          = fold,
    m2_fit        = m2_fit,
    m1_test_preds = m1_test_preds,
    spec          = spec,
    eval_window   = eval_window,
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

#' Nested M1 -> M2 leave-one-season-out cross-validation
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
#' @param ref_method Reference-curve method passed to \code{estimateRef()}.
#' @param n_weeks Integer; reference curve period (default 52L).
#' @param manual_labels Optional manual ignition labels.
#' @param flag_args Named list forwarded to \code{flagIgnition()}.
#' @param allow_scale Passed to M1 walk-forward.
#' @param use_ci Logical; peak CI control (default TRUE).
#' @param buffer_weeks Integer; peak buffer (default 0L).
#' @param min_obs Integer; minimum rows for alignment (default 4L).
#' @param curvature_ratio Numeric; delta curvature gate (default 1.0).
#' @param temperature,rise_weight,trough_weight,peak_decay Ensemble and
#'   alignment-loss controls.
#' @param slope_weight,slope_window Growth-rate similarity controls.
#' @param dynamic_temp,dynamic_temp_pivot Early-season temperature controls.
#' @param top_k,blend_alpha Template filtering and blending controls.
#' @param skip_m1 Logical; reuse supplied M1 predictions when supported.
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
         "Check warnings above - all specs likely failed during fold execution.")
  }

  has_bern <- "bernoulli_nll" %in% names(scores_df)
  summary_df <- scores_df |>
    dplyr::group_by(.data$spec_id) |>
    dplyr::summarise(
      n_seasons     = dplyr::n(),
      mean_nll      = mean(.data$mean_nll, na.rm = TRUE),
      bernoulli_nll = if (has_bern) mean(.data$bernoulli_nll, na.rm = TRUE) else NA_real_,
      brier         = mean(.data$brier,    na.rm = TRUE),
      rmse_p        = mean(.data$rmse_p,   na.rm = TRUE),
      .groups       = "drop"
    ) |>
    dplyr::arrange(if (has_bern) .data$bernoulli_nll else .data$mean_nll)

  best_id <- summary_df$spec_id[1]

  message("\n====== Grid search complete ======")
  if (has_bern)
    message("  Best spec: ", best_id,
            " (bernoulli_nll=", round(summary_df$bernoulli_nll[1], 4),
            " mean_nll=", round(summary_df$mean_nll[1], 4), ")")
  else
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
#' @param template_df Reference curve template (newWeek, fit) - typically
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
#' @return Output of \code{train_stage2_joint()} - a list with
#'   \code{fit}, \code{train_data}, \code{spec}, \code{tuned}, etc.
#'
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
#' @param y_max Numeric upper y-axis limit.
#' @param show_ci Logical; draw approximate prediction intervals.
#' @param title Plot title.
#'
#' @return A ggplot object.
#'
#' @export
plot_nested_loso_predictions <- function(cv_result,
                                         dat_raw = NULL,
                                         y_max   = 0.5,
                                         show_ci = TRUE,
                                         title   = "Nested LOSO: predicted vs observed by season") {

  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Please install ggplot2.")

  preds <- cv_result$predictions
  if (is.null(preds) || nrow(preds) == 0) {
    message("No predictions to plot.")
    return(ggplot2::ggplot() + ggplot2::theme_void())
  }

  # Approximate 95% CI: binomial SE from p_hat and N_lead (sampling uncertainty)
  if (show_ci && "N_lead" %in% names(preds)) {
    preds <- preds |>
      dplyr::mutate(
        se_hat = sqrt(.data$p_hat * (1 - .data$p_hat) / pmax(.data$N_lead, 1L)),
        p_lo   = pmax(0, .data$p_hat - 1.96 * .data$se_hat),
        p_hi   = pmin(1, .data$p_hat + 1.96 * .data$se_hat)
      )
  } else {
    show_ci <- FALSE
  }

  p <- ggplot2::ggplot(preds, ggplot2::aes(x = .data$t_since))

  if (show_ci) {
    p <- p + ggplot2::geom_ribbon(
      ggplot2::aes(ymin = .data$p_lo, ymax = .data$p_hi, fill = .data$lead),
      alpha = 0.18
    ) +
    ggplot2::scale_fill_manual(
      values = c("h1" = "steelblue", "h2" = "tomato",
                 "1"  = "steelblue", "2"  = "tomato"),
      labels = c("h1" = "h=1 week", "h2" = "h=2 weeks",
                 "1"  = "h=1 week", "2"  = "h=2 weeks"),
      guide  = "none"
    )
  }

  # Use t_since (weeks since ignition) so all seasons start at 0 and the
  # 13-week evaluation window is directly visible.
  p +
    ggplot2::geom_point(ggplot2::aes(y = .data$p_obs),
                        colour = "black", size = 1.2, alpha = 0.7) +
    ggplot2::geom_line(ggplot2::aes(y = .data$p_hat, colour = .data$lead),
                       linewidth = 0.9) +
    ggplot2::scale_colour_manual(
      values = c("h1" = "steelblue", "h2" = "tomato",
                 "1"  = "steelblue", "2"  = "tomato"),
      labels = c("h1" = "h=1 week", "h2" = "h=2 weeks",
                 "1"  = "h=1 week", "2"  = "h=2 weeks")
    ) +
    ggplot2::scale_y_continuous(limits = c(0, y_max)) +
    ggplot2::labs(
      x      = "Weeks since ignition",
      y      = "Positivity",
      colour = "Horizon",
      title  = title,
      caption = paste0(
        "Dots = observed positivity.  Lines = LOSO out-of-sample predictions ",
        "(GAM trained on other 9 seasons + Holt bias correction).\n",
        "Shaded bands = approx. 95% CI from binomial SE (p\u0302\u00b11.96\u00d7SE, N=lead-week tests).",
        "\nx = 0 is ignition week; evaluation window is ignition to ignition + 12 weeks."
      )
    ) +
    ggplot2::theme_bw() +
    ggplot2::facet_wrap(~ season, scales = "fixed", ncol = 3)
}
