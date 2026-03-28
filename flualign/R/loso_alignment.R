#' Leave-one-season-out (or user-specified split) alignment evaluation
#'
#' For each test season, estimates the reference curve on the training seasons,
#' learns alignment hyperparameters from the training data, then applies the
#' full alignment pipeline to the test season. By default performs LOSO:
#' each season is held out in turn and aligned against the curve estimated on
#' all other seasons.
#'
#' @param alignedD Data frame returned by \code{alignIgnition()}, containing
#'   at least \code{season}, \code{newWeek}, \code{y}, \code{neg}.
#' @param train_seasons Character vector of season labels to use for training.
#'   If \code{NULL} (default), training seasons are all seasons except the
#'   current test season (i.e., LOSO).
#' @param test_seasons Character vector of season labels to evaluate.
#'   If \code{NULL} (default), all seasons in \code{alignedD} are used as
#'   test seasons (full LOSO).
#' @param k Basis dimension passed to \code{estimateRef()} for the cyclic smooth.
#' @param n_weeks Integer. Template domain length passed to \code{estimateRef()}.
#' @param allow_scale Logical or \code{NULL}. If \code{NULL} (default),
#'   scale identifiability is checked automatically per fold via
#'   \code{check_scale_identifiability()}.
#' @param level Numeric. Confidence level for prediction intervals (default 0.95).
#' @param verbose Logical. Print progress messages (default \code{TRUE}).
#'
#' @return A list with two elements:
#' \describe{
#'   \item{results}{Named list (one entry per test season). Each entry is the
#'     output of \code{align_forecast_pipeline_dilate()} augmented with
#'     \code{season}, \code{train_seasons}, and \code{anchorWeek}.}
#'   \item{summary}{A tibble with one row per test season containing:
#'     \code{season}, \code{n_train}, \code{tau}, \code{delta}, \code{a},
#'     \code{b}, \code{allow_scale}, \code{delta_on}, \code{t_peak},
#'     \code{t_peak_lo}, \code{t_peak_hi}, \code{anchorWeek}.}
#' }
#'
#' @examples
#' \dontrun{
#' # Full LOSO (default)
#' loso <- loso_alignment(alignedD)
#' loso$summary
#'
#' # Hold out specific seasons as test
#' loso2 <- loso_alignment(alignedD, test_seasons = c("2017-18", "2019-20"))
#'
#' # Fixed train/test split
#' loso3 <- loso_alignment(
#'   alignedD,
#'   train_seasons = c("2012-13","2013-14","2014-15","2015-16","2016-17"),
#'   test_seasons  = c("2017-18","2018-19","2019-20")
#' )
#' }
#' @export
loso_alignment <- function(alignedD,
                            train_seasons = NULL,
                            test_seasons  = NULL,
                            k             = 10,
                            n_weeks       = 52L,
                            allow_scale   = NULL,
                            level         = 0.95,
                            verbose       = TRUE) {

  all_seasons <- sort(unique(alignedD$season))

  if (is.null(test_seasons)) {
    test_seasons <- all_seasons
  }

  # validate
  bad <- setdiff(test_seasons, all_seasons)
  if (length(bad) > 0)
    stop("test_seasons not found in alignedD: ", paste(bad, collapse = ", "))

  if (!is.null(train_seasons)) {
    bad_tr <- setdiff(train_seasons, all_seasons)
    if (length(bad_tr) > 0)
      stop("train_seasons not found in alignedD: ", paste(bad_tr, collapse = ", "))
  }

  results <- vector("list", length(test_seasons))
  names(results) <- test_seasons

  for (test_s in test_seasons) {

    # --- determine training set ---
    tr_seasons <- if (!is.null(train_seasons)) {
      train_seasons
    } else {
      setdiff(all_seasons, test_s)
    }

    if (length(tr_seasons) < 2)
      stop("Fewer than 2 training seasons for test season '", test_s,
           "'. Cannot fit reference curve.")

    if (verbose)
      message(sprintf("[loso_alignment] test: %-9s | training on %d seasons",
                      test_s, length(tr_seasons)))

    # --- fit reference curve on training seasons ---
    ex_for_ref <- setdiff(all_seasons, tr_seasons)   # exclude test + any others not in train
    ref <- estimateRef(
      alignedD  = alignedD,
      exSeason  = ex_for_ref,
      k         = k,
      n_weeks   = n_weeks
    )

    # --- learn hyperparameters from training data ---
    hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)

    # --- test season data ---
    currentD <- dplyr::filter(alignedD, season == test_s)

    # --- scale identifiability ---
    scale_rec <- if (!is.null(allow_scale)) {
      allow_scale
    } else {
      check_scale_identifiability(
        currentD  = currentD,
        g_ref_fun = ref$g_ref_fun,
        hyper     = hyper
      )$allow_scale_rec
    }

    # --- alignment + forecast ---
    res <- align_forecast_pipeline_dilate(
      currentD    = currentD,
      g_ref_fun   = ref$g_ref_fun,
      g_ref_mu_se = ref$g_ref_mu_se,
      hyper       = hyper,
      allow_scale = scale_rec,
      level       = level
    )

    res$season        <- test_s
    res$train_seasons <- tr_seasons
    res$anchorWeek    <- ref$anchorWeek

    results[[test_s]] <- res
  }

  # --- build summary tibble ---
  summary_df <- purrr::map_dfr(results, function(r) {
    pk <- r$peak
    tibble::tibble(
      season     = r$season,
      n_train    = length(r$train_seasons),
      tau        = r$tau,
      delta      = r$delta,
      a          = r$a,
      b          = r$b,
      allow_scale = r$allow_scale,
      delta_on   = r$delta_on,
      t_peak     = pk$t_peak,
      t_peak_lo  = pk$t_peak_ci[1],
      t_peak_hi  = pk$t_peak_ci[2],
      anchorWeek = r$anchorWeek
    )
  })

  list(results = results, summary = summary_df)
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
#' @param use_smoothed Logical. If \code{TRUE}, feed pre-smoothed synthetic counts
#'   into \code{estimateRef()} instead of raw counts (default \code{FALSE}).
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
#' @export
loso_walkforward <- function(allD,
                              params,
                              walk_start      = NULL,
                              walk_end        = NULL,
                              manual_labels   = NULL,
                              train_seasons   = NULL,
                              test_seasons    = NULL,
                              exclude_seasons = NULL,
                              k_deriv         = 10L,
                              k_ref           = 10L,
                              n_weeks         = 52L,
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
                              allow_scale     = NULL,
                              level           = 0.95,
                              use_ci          = TRUE,
                              buffer_weeks    = 0L,
                              n_cores         = parallel::detectCores() - 1L,
                              min_obs         = 4L,
                              curvature_ratio = 1.0,
                              template_shift  = 0L,
                              peak_weight_boost  = 1,
                              peak_weight_decay  = 0.3,
                              # --- Alignment loss weighting (Improvement C) ---
                              align_trough_weight = 0.1,
                              align_rise_weight   = 1.0,
                              align_peak_decay    = 0.3,
                              # --- Multi-template ensemble (Improvement A) ---
                              use_multi_template        = FALSE,
                              ref_method                = "binomial",
                              multi_temperature         = 1.0,
                              multi_top_k               = NULL,
                              multi_blend_alpha         = 1.0,
                              checkpoint_file = NULL,
                              verbose         = TRUE) {

  all_seasons <- sort(unique(as.character(allD$season)))

  # Exclude bad seasons from data and universe before any other logic
  if (!is.null(exclude_seasons)) {
    allD        <- dplyr::filter(allD, !season %in% exclude_seasons)
    all_seasons <- setdiff(all_seasons, exclude_seasons)
  }

  if (is.null(test_seasons)) test_seasons <- all_seasons

  bad <- setdiff(test_seasons, all_seasons)
  if (length(bad) > 0)
    stop("test_seasons not found in allD: ", paste(bad, collapse = ", "))

  if (!is.null(train_seasons)) {
    bad_tr <- setdiff(train_seasons, all_seasons)
    if (length(bad_tr) > 0)
      stop("train_seasons not found in allD: ", paste(bad_tr, collapse = ", "))
  }

  # --- set up parallel plan; restore on exit ---
  n_workers <- max(1L, as.integer(n_cores))
  old_plan  <- future::plan()
  if (n_workers > 1L) {
    future::plan(future::multisession, workers = n_workers)
  }
  on.exit(future::plan(old_plan), add = TRUE)

  params_list   <- vector("list", length(test_seasons))
  forecast_list <- vector("list", length(test_seasons))
  ref_list      <- vector("list", length(test_seasons))
  names(params_list) <- names(forecast_list) <- names(ref_list) <- test_seasons

  # --- Resume from checkpoint if available ---
  completed_seasons <- character(0)
  if (!is.null(checkpoint_file) && file.exists(checkpoint_file)) {
    ckpt <- readRDS(checkpoint_file)
    completed_seasons <- ckpt$completed_seasons %||% character(0)
    for (s in intersect(completed_seasons, test_seasons)) {
      params_list[[s]]   <- ckpt$params_list[[s]]
      forecast_list[[s]] <- ckpt$forecast_list[[s]]
      ref_list[[s]]      <- ckpt$ref_list[[s]]
    }
    if (verbose && length(completed_seasons))
      message(sprintf("[loso_walkforward] Resuming from checkpoint: %d/%d seasons done (%s)",
                      length(intersect(completed_seasons, test_seasons)),
                      length(test_seasons),
                      paste(intersect(completed_seasons, test_seasons), collapse = ", ")))
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

    if (length(tr_seasons) < 2)
      stop("Fewer than 2 training seasons for test season '", test_s, "'.")

    # --- resolve walk bounds for this season ---
    season_weeks <- dplyr::filter(allD, season == test_s)$weekF
    walk_end_s   <- if (!is.null(walk_end))   as.integer(walk_end)   else max(season_weeks, na.rm = TRUE)

    # --- 1. Build aligned training data (retrospective) ---
    train_allD  <- dplyr::filter(allD, season %in% tr_seasons)
    res_deriv   <- estimateDerivs(train_allD, k = k_deriv,
                                  peak_weight_boost = peak_weight_boost,
                                  peak_weight_decay = peak_weight_decay,
                                  ignition_weeks    = manual_labels)

    train_outs <- res_deriv$data %>%
      dplyr::group_by(season) %>%
      dplyr::group_split(.keep = TRUE) %>%
      purrr::map(~ do.call(flagIgnition,
                           c(list(df = .x, manual_labels = manual_labels), flag_args)))

    aligned_train <- alignIgnition(train_outs)

    # --- 2. Fit reference curve on aligned training data ---
    ref_meth <- if (use_multi_template) "fs" else ref_method
    ref   <- estimateRef(alignedD = aligned_train, exSeason = character(0),
                         k = k_ref, n_weeks = n_weeks,
                         method = ref_meth)

    # Store original (unshifted) template for plotting, then apply lag if requested
    ref$g_ref_fun_orig <- ref$g_ref_fun
    if (as.integer(template_shift) != 0L) {
      s_int <- as.integer(template_shift)
      orig_fun    <- ref$g_ref_fun
      orig_mu_se  <- ref$g_ref_mu_se
      orig_safe   <- ref$g_ref_safe
      ref$g_ref_fun  <- function(u) orig_fun(u - s_int)
      ref$g_ref_safe <- function(u) orig_fun(pmin(pmax(u - s_int, 1L), n_weeks))
      ref$g_ref_mu_se <- function(u) orig_mu_se(u - s_int)
    }

    hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)
    ref_list[[test_s]] <- ref

    # iWeek_true from manual_labels (ground truth for diagnostics)
    iWeek_true <- if (!is.null(manual_labels) && test_s %in% names(manual_labels))
      as.integer(manual_labels[[test_s]]) else NA_integer_

    # --- 3. Prospective ignition detection on test season (run once) ---
    raw_test_D <- dplyr::filter(allD, season == test_s, weekF <= walk_end_s)
    det_start  <- if (!is.null(walk_start)) as.integer(walk_start) else 1L
    ign_out <- run_ignition_weekly(
      currentSeason  = raw_test_D,
      ign_fit_or_gam = NULL,
      params         = params,
      start_week     = det_start
    )

    # --- resolve walk_start for this season ---
    walk_start_s <- if (!is.null(walk_start)) {
      as.integer(walk_start)
    } else if (!is.na(ign_out$ign_week_locked)) {
      as.integer(ign_out$ign_week_locked)
    } else {
      walk_end_s + 1L   # empty sequence — no ignition detected
    }
    eval_weeks_s <- seq(walk_start_s, walk_end_s)

    if (verbose)
      message(sprintf("[loso_walkforward] test: %-9s | train: %d seasons | weeks %d-%d | workers: %d",
                      test_s, length(tr_seasons), walk_start_s, walk_end_s, n_workers))

    # capture locals for parallel workers
    .ref          <- ref
    .hyper        <- hyper
    .allD_test    <- dplyr::filter(allD, season == test_s)
    .allow_scale  <- allow_scale
    .test_s       <- test_s
    .tr_seasons   <- tr_seasons
    .min_obs         <- min_obs
    .level           <- level
    .iWeek_true      <- iWeek_true
    .ign_out         <- ign_out
    .use_ci          <- use_ci
    .buffer_weeks    <- buffer_weeks
    .curvature_ratio <- curvature_ratio
    .trough_weight   <- align_trough_weight
    .rise_weight     <- align_rise_weight
    .peak_decay      <- align_peak_decay
    .use_multi       <- use_multi_template
    .multi_temp      <- multi_temperature
    .multi_top_k     <- multi_top_k
    .multi_blend     <- multi_blend_alpha

    # --- 4. Walk-forward: parallelise over eval_weeks ---
    week_results <- furrr::future_map(eval_weeks_s, function(ew) {

      season_data_to_ew <- dplyr::filter(.allD_test, weekF <= ew)
      n_obs             <- nrow(season_data_to_ew)

      # Dispatch: multi-template ensemble or single-template alignment
      if (.use_multi && !is.null(.ref$eta_mat)) {
        ap <- run_alignment_prospective_multi(
          currentSeason   = season_data_to_ew,
          ref             = .ref,
          hyper           = .hyper,
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
          temperature     = .multi_temp,
          top_k           = .multi_top_k,
          blend_alpha     = .multi_blend
        )
      } else {
        ap <- run_alignment_prospective(
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
          peak_decay      = .peak_decay
        )
      }

      if (ap$state == "pre_ignition") {
        ign_locked_w <- .ign_out$ign_week_locked
        reason <- if (is.na(ign_locked_w) || ign_locked_w > ew) {
          "no_ignition"
        } else if (n_obs < .min_obs) {
          "too_few_obs"
        } else {
          "alignment_error"
        }
        iWeek_hat_ew <- if (!is.na(ign_locked_w) && ign_locked_w <= ew)
          as.integer(.ign_out$iWeek_hat_locked) else NA_integer_

        na_row <- tibble::tibble(
          season = .test_s, eval_week = ew, n_obs = n_obs,
          iWeek_hat = iWeek_hat_ew, iWeek_true = .iWeek_true,
          tau = NA_real_, delta = NA_real_, a = NA_real_, b = NA_real_,
          allow_scale = NA, delta_on = NA,
          t_peak = NA_real_, t_peak_lo = NA_real_, t_peak_hi = NA_real_,
          peak_weekF = NA_integer_, peak_passed = FALSE,
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
        t_peak_lo       = ap$t_peak_ci[1],
        t_peak_hi       = ap$t_peak_ci[2],
        peak_weekF      = ap$peak_weekF,
        peak_passed     = ap$peak_passed,
        fallback_reason = ap$fallback_reason,
        n_train         = length(.tr_seasons),
        anchorWeek      = .ref$anchorWeek
      )

      forecast_row <- ap$forecast_df %>%
        dplyr::mutate(season = .test_s, eval_week = ew,
                      newWeek = as.numeric(newWeek),
                      p_hat   = as.numeric(p_hat),
                      p_lo    = as.numeric(p_lo),
                      p_hi    = as.numeric(p_hi)) %>%
        dplyr::select(season, eval_week, newWeek, p_hat, p_lo, p_hi, kind)

      list(params = params_row, forecast = forecast_row)

    }, .options = furrr::furrr_options(seed = TRUE))

    params_list[[test_s]]   <- dplyr::bind_rows(purrr::map(week_results, "params"))
    forecast_list[[test_s]] <- dplyr::bind_rows(purrr::map(week_results, "forecast"))

    # --- Checkpoint: save progress after each season ---
    if (!is.null(checkpoint_file)) {
      completed_seasons <- union(completed_seasons, test_s)
      saveRDS(list(
        completed_seasons = completed_seasons,
        params_list       = params_list[completed_seasons],
        forecast_list     = forecast_list[completed_seasons],
        ref_list          = ref_list[completed_seasons]
      ), checkpoint_file)
      if (verbose)
        message(sprintf("[loso_walkforward] Checkpoint saved: %d/%d seasons (%s)",
                        length(completed_seasons), length(test_seasons), checkpoint_file))
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


#' Tune k_ref via LOSO walk-forward
#'
#' Runs \code{loso_walkforward()} for each candidate value of \code{k_ref} and
#' summarises alignment quality using prospective peak MAE under three Weibull
#' weighting schemes. For each \code{(season, eval_week)} row from ignition lock
#' through the true peak week (post-peak excluded), the error is
#' \eqn{|\hat{t}_{peak} - t_{peak}^{true}|} in weeks. Weight function:
#' \eqn{w(t) = \exp(-(\lambda t)^p)}, where
#' \eqn{t = \text{eval\_week} - \text{iWeek\_true}} (weeks since true ignition).
#' \itemize{
#'   \item \strong{Weibull p=1, λ=0}: \eqn{w = 1} — unweighted baseline.
#'   \item \strong{Weibull p=1, λ=0.1}: \eqn{w = \exp(-0.1t)} — exponential decay.
#'   \item \strong{Weibull p=2, λ=0.1}: \eqn{w = \exp(-(0.1t)^2)} — flat early,
#'     then sharper decay; upweights the first few weeks more uniformly.
#' }
#'
#' @param allD Raw data frame passed directly to \code{loso_walkforward()}.
#' @param params Stage-1 detector parameters list.
#' @param k_ref_grid Integer vector of \code{k_ref} values to evaluate
#'   (default \code{c(6, 8, 10, 12, 15, 20)}).
#' @param manual_labels Named integer vector of verified ignition weeks.
#' @param exclude_seasons Character vector of seasons to exclude (passed to
#'   \code{loso_walkforward()}).
#' @param n_weeks Integer. Template length (default 52).
#' @param n_cores Integer. Workers per \code{loso_walkforward()} call
#'   (default \code{parallel::detectCores() - 1}).
#' @param use_smoothed_peaks Logical. If \code{TRUE}, compute true peaks from
#'   \code{estimateDerivs()} smoothed fits (\code{argmax(fit)}) instead of raw
#'   observed positivity \code{argmax(p)} (default \code{FALSE}).
#' @param k_smooth Integer. Basis dimension for the per-season GAM used to
#'   compute smoothed peaks (default 10). Only used when
#'   \code{use_smoothed_peaks = TRUE}.
#' @param peak_weight_boost Numeric >= 1. Multiplicative weight for observations
#'   between ignition and peak in per-season smoothing (default 1 = no boost).
#'   Applied both to smoothed-peak computation and to the \code{loso_walkforward()}
#'   reference curve estimation.
#' @param peak_weight_decay Numeric > 0. Exponential decay rate for weights after
#'   the observed peak (default 0.3).
#' @param use_smoothed Logical. If \code{TRUE}, pass pre-smoothed synthetic counts
#'   to \code{estimateRef()} within each LOSO fold (default \code{FALSE}).
#' @param verbose Logical. Print progress per k value (default \code{TRUE}).
#' @param ... Additional arguments forwarded to \code{loso_walkforward()}.
#'
#' @return A tibble with one row per \code{k_ref} value and columns:
#'   \code{k_ref}, \code{mae_w_p1_l0}, \code{mae_w_p1_l01}, \code{mae_w_p2_l01},
#'   \code{n_seasons}.
#'
#' @examples
#' \dontrun{
#' tuned <- readRDS("data/stage1_tuning.rds")
#' k_results <- tune_loso_k(
#'   allD            = allD,
#'   params          = tuned$best_params,
#'   manual_labels   = manual_labels,
#'   exclude_seasons = "2015-16"
#' )
#' k_results
#' }
#' @export
tune_loso_k <- function(allD,
                         params,
                         k_ref_grid      = c(6L, 8L, 10L, 12L, 15L, 20L),
                         manual_labels   = NULL,
                         exclude_seasons = NULL,
                         n_weeks         = 52L,
                         n_cores         = parallel::detectCores() - 1L,
                         use_smoothed_peaks = FALSE,
                         k_smooth           = 10L,
                         peak_weight_boost  = 1,
                         peak_weight_decay  = 0.3,
                         use_smoothed       = FALSE,
                         verbose         = TRUE,
                         ...) {

  # Pre-filter once
  if (!is.null(exclude_seasons)) {
    allD <- dplyr::filter(allD, !season %in% exclude_seasons)
  }

  # True peak week per season: smoothed or raw
  if (use_smoothed_peaks) {
    deriv_all <- estimateDerivs(allD, k = k_smooth,
                                peak_weight_boost = peak_weight_boost,
                                peak_weight_decay = peak_weight_decay,
                                ignition_weeks    = manual_labels)
    true_peaks <- deriv_all$data %>%
      dplyr::filter(!is.na(fit), is.finite(fit)) %>%
      dplyr::group_by(season) %>%
      dplyr::slice_max(fit, n = 1L, with_ties = FALSE) %>%
      dplyr::ungroup() %>%
      dplyr::select(season, true_peak_weekF = weekF)
  } else {
    true_peaks <- allD %>%
      dplyr::filter(!is.na(p), is.finite(p), N > 0) %>%
      dplyr::group_by(season) %>%
      dplyr::slice_max(p, n = 1L, with_ties = FALSE) %>%
      dplyr::ungroup() %>%
      dplyr::select(season, true_peak_weekF = weekF)
  }

  results <- purrr::map_dfr(k_ref_grid, function(k) {

    if (verbose) message(sprintf("[tune_loso_k] k_ref = %d", k))

    wf <- loso_walkforward(
      allD            = allD,
      params          = params,
      manual_labels   = manual_labels,
      exclude_seasons = NULL,   # already filtered above
      k_ref           = k,
      n_weeks         = n_weeks,
      n_cores         = n_cores,
      use_smoothed       = use_smoothed,
      peak_weight_boost  = peak_weight_boost,
      peak_weight_decay  = peak_weight_decay,
      verbose         = FALSE,
      ...
    )

    pdf <- wf$params_df

    # Prospective peak MAE under three Weibull weighting schemes.
    # w(t) = exp(-(lambda * t)^p), t = weeks since true ignition (0 at lock).
    # Rows: ignition locked, t_peak available, eval_week <= true peak.
    score_df <- pdf %>%
      dplyr::filter(!is.na(t_peak), !is.na(iWeek_true)) %>%
      dplyr::mutate(
        pred_peak_weekF = round(t_peak - anchorWeek + iWeek_hat)
      ) %>%
      dplyr::left_join(true_peaks, by = "season") %>%
      dplyr::filter(!is.na(true_peak_weekF),
                    eval_week <= true_peak_weekF) %>%
      dplyr::mutate(
        error      = abs(pred_peak_weekF - true_peak_weekF),
        t          = eval_week - iWeek_true,
        w_p1_l0    = 1,                          # p=1, lambda=0: unweighted
        w_p1_l01   = exp(-(0.1 * t)^1),          # p=1, lambda=0.1: exponential
        w_p2_l01   = exp(-(0.1 * t)^2)           # p=2, lambda=0.1: Weibull shape 2
      )

    wmae <- function(w) {
      if (nrow(score_df) == 0 || sum(w) == 0) NA_real_
      else sum(w * score_df$error) / sum(w)
    }

    tibble::tibble(
      k_ref        = k,
      mae_w_p1_l0  = wmae(score_df$w_p1_l0),
      mae_w_p1_l01 = wmae(score_df$w_p1_l01),
      mae_w_p2_l01 = wmae(score_df$w_p2_l01),
      n_seasons    = dplyr::n_distinct(score_df$season)
    )
  })

  results
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
#' @param ... Additional fixed arguments forwarded to
#'   \code{loso_walkforward()} (e.g. \code{buffer_weeks}, \code{use_ci}).
#'
#' @return A list with elements:
#' \describe{
#'   \item{scores}{Tibble with one row per spec: \code{spec_id} plus the
#'     grid columns, \code{mae_uniform}, \code{mae_exp}, \code{mae_weibull},
#'     \code{n_seasons}.}
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
#'   manual_labels   = manual_labels,
#'   exclude_seasons = "2015-16",
#'   use_multi_template = TRUE,
#'   ref_method         = "fs"
#' )
#' res$best
#' }
#' @export
tune_m1_alignment <- function(allD,
                               params,
                               grid,
                               manual_labels   = NULL,
                               exclude_seasons = NULL,
                               n_weeks         = 52L,
                               n_cores         = parallel::detectCores() - 1L,
                               checkpoint_dir  = "data/m1_tune_ckpt",
                               verbose         = TRUE,
                               ...) {

  if (!dir.exists(checkpoint_dir))
    dir.create(checkpoint_dir, recursive = TRUE)

  results_cache <- file.path(checkpoint_dir, "tune_m1_results.rds")

  # Pre-filter excluded seasons once
  if (!is.null(exclude_seasons)) {
    allD <- dplyr::filter(allD, !season %in% exclude_seasons)
  }

  # True peak week per season (observed argmax)
  true_peaks <- allD %>%
    dplyr::filter(!is.na(p), is.finite(p), N > 0) %>%
    dplyr::group_by(season) %>%
    dplyr::slice_max(p, n = 1L, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::select(season, true_peak_weekF = weekF)

  # Build spec IDs
  grid <- tibble::as_tibble(grid)
  n_specs <- nrow(grid)
  grid$spec_id <- sprintf("s%03d", seq_len(n_specs))

  # Load previously completed specs
  if (file.exists(results_cache)) {
    prev <- readRDS(results_cache)
    done_ids <- prev$spec_id
    score_rows <- split(prev, seq_len(nrow(prev)))
    if (verbose) message(sprintf("[tune_m1] Resuming: %d / %d specs already done.",
                                 length(done_ids), n_specs))
  } else {
    done_ids <- character(0)
    score_rows <- list()
  }

  # Tunable column names (columns in grid that are loso_walkforward args)
  tune_cols <- setdiff(names(grid), "spec_id")

  for (i in seq_len(n_specs)) {
    sid <- grid$spec_id[i]
    if (sid %in% done_ids) next

    spec <- grid[i, ]
    if (verbose) {
      spec_str <- paste(tune_cols, "=",
                        vapply(tune_cols, function(c) as.character(spec[[c]]),
                               character(1)),
                        collapse = ", ")
      message(sprintf("[tune_m1] Spec %d / %d  (%s)  %s",
                      i, n_specs, sid, spec_str))
    }

    # Build loso_walkforward arguments from the spec row
    wf_args <- list(
      allD            = allD,
      params          = params,
      manual_labels   = manual_labels,
      exclude_seasons = NULL,   # already filtered
      n_weeks         = n_weeks,
      n_cores         = n_cores,
      verbose         = FALSE
    )
    # Overlay tunable params from grid
    for (col in tune_cols) {
      wf_args[[col]] <- spec[[col]]
    }
    # Overlay fixed caller args (...)
    dots <- list(...)
    for (nm in names(dots)) {
      wf_args[[nm]] <- dots[[nm]]
    }
    # Per-spec checkpoint
    wf_args$checkpoint_file <- file.path(checkpoint_dir,
                                         paste0("ckpt_", sid, ".rds"))

    wf <- tryCatch(
      do.call(loso_walkforward, wf_args),
      error = function(e) {
        warning(sprintf("[tune_m1] Spec %s failed: %s", sid, conditionMessage(e)))
        NULL
      }
    )

    if (is.null(wf)) {
      row <- tibble::tibble(
        spec_id      = sid,
        mae_uniform  = NA_real_,
        mae_exp      = NA_real_,
        mae_weibull  = NA_real_,
        n_seasons    = 0L
      )
    } else {
      score_df <- wf$params_df %>%
        dplyr::filter(!is.na(t_peak), !is.na(iWeek_true)) %>%
        dplyr::mutate(
          pred_peak_weekF = round(t_peak - anchorWeek + iWeek_hat)
        ) %>%
        dplyr::left_join(true_peaks, by = "season") %>%
        dplyr::filter(!is.na(true_peak_weekF),
                      eval_week <= true_peak_weekF) %>%
        dplyr::mutate(
          error    = abs(pred_peak_weekF - true_peak_weekF),
          t        = eval_week - iWeek_true,
          w_unif   = 1,
          w_exp    = exp(-(0.1 * t)^1),
          w_weib   = exp(-(0.1 * t)^2)
        )

      wmae <- function(w) {
        if (nrow(score_df) == 0 || sum(w) == 0) NA_real_
        else sum(w * score_df$error) / sum(w)
      }

      row <- tibble::tibble(
        spec_id      = sid,
        mae_uniform  = wmae(score_df$w_unif),
        mae_exp      = wmae(score_df$w_exp),
        mae_weibull  = wmae(score_df$w_weib),
        n_seasons    = dplyr::n_distinct(score_df$season)
      )
    }

    score_rows <- c(score_rows, list(row))
    done_ids <- c(done_ids, sid)

    # Checkpoint after every spec
    all_scores <- dplyr::bind_rows(score_rows)
    saveRDS(all_scores, results_cache)

    if (verbose) {
      message(sprintf("  -> mae_weibull = %.3f   [%d / %d done]",
                      row$mae_weibull, length(done_ids), n_specs))
    }
  }

  all_scores <- dplyr::bind_rows(score_rows)

  # Merge grid columns into scores
  scores <- dplyr::left_join(
    grid,
    all_scores,
    by = "spec_id"
  ) %>%
    dplyr::arrange(mae_weibull)

  best <- scores %>% dplyr::slice_min(mae_weibull, n = 1L, with_ties = FALSE)

  if (verbose) {
    message(sprintf("\n[tune_m1] Best spec: %s  mae_weibull = %.4f",
                    best$spec_id, best$mae_weibull))
    for (col in tune_cols) {
      message(sprintf("  %s = %s", col, as.character(best[[col]])))
    }
  }

  list(scores = scores, best = best, grid = grid)
}
