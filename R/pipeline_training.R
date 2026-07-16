# High-level training API: build_*, tune_*, train_*, assemble_kit()
# Thin orchestration wrappers around existing low-level functions.
# Low-level functions are unchanged.

`%||%` <- function(x, y) if (is.null(x)) y else x

# ============================================================
# Default configuration helpers (unexported)
# ============================================================

.default_manual_labels <- function() {
  c(
    "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
    "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
    "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
    "2023-24" = 20L, "2024-25" = 23L
  )
}

.default_flag_args <- function() {
  list(
    p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L,
    min_window = 10L, w_min = 21L, w_max = 21L, d2_relax = -0.01
  )
}

.default_m1_params <- function() {
  list(
    k_ref = 25L, ref_method = "fs",
    temperature = 0.25, rise_weight = 1.0, trough_weight = 0.1,
    peak_decay = 0.3, slope_weight = 8.0, slope_window = 6L,
    dynamic_temp = FALSE, dynamic_temp_pivot = 10L
  )
}

.default_m0_params <- function() {
  list(
    cls_thr = 0.26, p_thr = 0.005, prev_thr = 0.001,
    p_sum_thr = 0.06, eps = 0, n_consec = 5L, L = 2L,
    K_sum = 5L, N_req = 4L, w_min = 13L, w_max = 26L
  )
}

.default_m2_spec <- function() {
  stage2_make_spec(
    delta = 0L, Kr = 1L, T = "S", k_f = 4L, k_e = 2L,
    alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
    k_n = 0L, k_w = 0L, k_s = 0L, lambda_w = 0, w_floor = 0.05,
    bias_alpha = 0.05, bias_beta = 0
  )
}

#' Construct an M1 alignment parameter list
#'
#' Builds the named list consumed by \code{build_m1()}, \code{build_m2()}, and
#' \code{train_m2()} via their \code{m1_params} argument. Calling this function
#' is the recommended way to customise alignment settings rather than
#' hand-crafting a raw list, as it documents every knob and enforces defaults.
#'
#' @param k_ref Integer. Reference curve GAM basis dimension (default 25).
#' @param ref_method Character. Reference fitting method passed to
#'   \code{estimateRef()}. One of \code{"fs"} (factor-smooth, default) or
#'   \code{"re"}.
#' @param temperature Numeric. Softmax temperature for template weighting
#'   (default 0.25). Lower values concentrate weight on the best-matching
#'   template.
#' @param rise_weight Numeric. Weight given to rise-phase similarity (default
#'   1.0).
#' @param trough_weight Numeric. Weight given to trough similarity (default
#'   0.1).
#' @param peak_decay Numeric. Exponential decay on peak-proximity weight
#'   (default 0.3).
#' @param slope_weight Numeric. Weight on slope similarity at aligned positions
#'   (default 8.0).
#' @param slope_window Integer. Number of weeks used to compute the local slope
#'   (default 6).
#' @param dynamic_temp Logical. If \code{TRUE}, temperature adapts over the
#'   season (default \code{FALSE}).
#' @param dynamic_temp_pivot Integer. Week at which dynamic temperature pivots
#'   (default 10; ignored when \code{dynamic_temp = FALSE}).
#'
#' @return A named list suitable for the \code{m1_params} argument of
#'   \code{build_m1()}, \code{build_m2()}, and \code{train_m2()}.
#'
#' @examples
#' params <- m1_make_params()
#' params_custom <- m1_make_params(slope_weight = 12, temperature = 0.15)
#'
#' @export
m1_make_params <- function(k_ref             = 25L,
                            ref_method        = "fs",
                            temperature       = 0.25,
                            rise_weight       = 1.0,
                            trough_weight     = 0.1,
                            peak_decay        = 0.3,
                            slope_weight      = 8.0,
                            slope_window      = 6L,
                            dynamic_temp      = FALSE,
                            dynamic_temp_pivot = 10L) {
  list(
    k_ref              = as.integer(k_ref),
    ref_method         = ref_method,
    temperature        = temperature,
    rise_weight        = rise_weight,
    trough_weight      = trough_weight,
    peak_decay         = peak_decay,
    slope_weight       = slope_weight,
    slope_window       = as.integer(slope_window),
    dynamic_temp       = dynamic_temp,
    dynamic_temp_pivot = as.integer(dynamic_temp_pivot)
  )
}

.default_m0_grid <- function() {
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need 'data.table'.")
  data.table::CJ(
    cls_thr   = 0.26,
    use_cls   = FALSE,
    p_thr     = c(0.002, 0.003, 0.004, 0.005),
    prev_thr  = c(0.001, 0.002, 0.003),
    n_consec  = 5L,
    L         = 2L,
    eps       = 0,
    K_sum     = 5L,
    p_sum_thr = c(0.050, 0.055, 0.060),
    N_req     = 4L,
    w_min     = 13L,
    w_max     = 26L,
    K_dp      = 3L,
    dp_thr    = 0.01,
    sorted    = FALSE
  )
}

#' Return the default M1 alignment tuning grid
#'
#' @return A tibble with 20 rows (4 k_ref x 5 slope_weight combinations).
#' @export
default_m1_grid <- function() {
  if (!requireNamespace("tidyr", quietly = TRUE)) stop("Need 'tidyr'.")
  tidyr::crossing(
    k_ref             = c(25L, 30L, 40L, 50L),
    multi_temperature = 0.25,
    template_shift    = 0L,
    align_rise_weight = 1.0,
    slope_window      = 6L,
    slope_weight      = c(8.0, 12.0, 16.0, 20.0, 30.0)
  )
}

#' Return the default M2 forecast tuning grid
#'
#' Delegates to \code{plan_m2_grid()} to return the compact initial grid. The
#' deployed v16 incumbent is always included, with one-factor neighbors and
#' per-row provenance instead of an explosive Cartesian product.
#'
#' @return A data frame with M2 parameters, stable specification IDs, and
#'   provenance.
#' @export
default_m2_grid <- function() {
  plan_m2_grid()
}

# Internal season selector
.select_loso_seasons <- function(available, loso_seasons) {
  if (identical(loso_seasons, "all"))         return(available)
  if (identical(loso_seasons, "alternating")) return(available[c(TRUE, FALSE)])
  if (is.character(loso_seasons))             return(intersect(loso_seasons, available))
  stop("loso_seasons must be 'all', 'alternating', or a character vector")
}


# ============================================================
# M0
# ============================================================

#' Build aligned training data using M0 ignition detection
#'
#' Computes seasonal derivative signals via \code{estimateDerivs()}, flags
#' ignition events via \code{flagIgnition()}, and aligns all seasons to a
#' common \code{newWeek} coordinate via \code{alignIgnition()}.
#'
#' @param allD Multi-season surveillance data frame with columns
#'   \code{season}, \code{weekF}, \code{y}, \code{N}, \code{p}.
#' @param exclude Character vector of seasons to exclude permanently.
#' @param manual_labels Named integer vector of manually-verified ignition weeks
#'   (names = season labels). Defaults to canonical production labels.
#' @param flag_args List of ignition-flagging hyperparameters. Defaults to
#'   canonical production values.
#' @param best_params Locked production M0 parameters. Defaults to the deployed
#'   fresh-run values and is returned for downstream M1/M2 training.
#' @param k_deriv Integer. GAM basis functions for derivative smoothing (default
#'   \code{10L}).
#'
#' @return A list with \code{aligned} (aligned data frame), \code{seasons_used},
#'   \code{manual_labels}, \code{flag_args}, and \code{best_params}.
#'
#' @export
build_m0 <- function(allD,
                     exclude       = c("2011-12", "2015-16", "2020-21", "2021-22"),
                     manual_labels = .default_manual_labels(),
                     flag_args     = .default_flag_args(),
                     best_params   = .default_m0_params(),
                     k_deriv       = 10L) {
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Need 'dplyr'.")
  if (!requireNamespace("purrr", quietly = TRUE)) stop("Need 'purrr'.")

  dat <- if (length(exclude) > 0)
    dplyr::filter(allD, !.data$season %in% exclude) else allD
  seasons_used <- sort(unique(dat$season))

  res_deriv <- estimateDerivs(dat, k = as.integer(k_deriv))
  outs <- res_deriv$data |>
    dplyr::group_by(.data$season) |>
    dplyr::group_split(.keep = TRUE) |>
    purrr::map(function(df)
      do.call(flagIgnition, c(list(df = df, manual_labels = manual_labels), flag_args)))
  aligned <- alignIgnition(outs)

  list(
    aligned       = aligned,
    seasons_used  = seasons_used,
    manual_labels = manual_labels,
    flag_args     = flag_args,
    best_params   = best_params
  )
}


#' Tune M0 ignition detection hyperparameters via LOSO grid search
#'
#' Runs leave-one-season-out grid search over M0 detection parameters using
#' \code{loso_M0v2()}. The 36-spec grid matches the production tuning run.
#'
#' @param allD Multi-season surveillance data frame.
#' @param loso_seasons Which seasons to evaluate as LOSO test folds.
#'   \code{"all"} (default) evaluates every season; \code{"alternating"}
#'   uses every other season (removes non-selected from training too --
#'   acceptable for quick demos). A character vector selects specific seasons.
#' @param exclude Character vector of seasons to permanently exclude.
#' @param grid Tuning grid as a data frame. Default: \code{.default_m0_grid()}.
#' @param manual_labels Named integer vector of manual ignition labels.
#' @param flag_args List of ignition-flagging parameters.
#' @param n_cores Integer. Parallel cores (default: all minus 1).
#' @param verbose Logical. Print progress.
#'
#' @return A list with \code{best_params}, \code{tuning} (full
#'   \code{loso_M0v2()} output), \code{aligned}, \code{seasons_used},
#'   \code{manual_labels}, and \code{flag_args}. Pass directly to
#'   \code{build_m1()}, \code{build_m2()}, and \code{train_m2()}.
#'
#' @export
tune_m0 <- function(allD,
                    loso_seasons  = "all",
                    exclude       = c("2011-12", "2015-16", "2020-21", "2021-22"),
                    grid          = .default_m0_grid(),
                    manual_labels = .default_manual_labels(),
                    flag_args     = .default_flag_args(),
                    n_cores       = parallel::detectCores() - 1L,
                    verbose       = TRUE) {

  m0_built <- build_m0(allD, exclude = exclude,
                        manual_labels = manual_labels, flag_args = flag_args)
  aligned  <- m0_built$aligned

  # loso_seasons controls which test folds are evaluated.
  # Non-selected seasons are passed as drop_seasons (also removes from training
  # -- acceptable trade-off for "alternating" quick-demo mode).
  all_seas   <- sort(unique(aligned$season))
  test_seas  <- .select_loso_seasons(all_seas, loso_seasons)
  extra_drop <- setdiff(all_seas, test_seas)
  # "2015-16" always dropped (ignition outlier)
  drop_all   <- intersect(unique(c("2015-16", extra_drop)), all_seas)

  tune_args_use <- list(
    miss_penalty = 0, lambda = 20, kappa = 0,
    gamma = 25, gamma_late = 0,
    iWeek = TRUE, ncores = as.integer(max(1L, n_cores)),
    verbose = FALSE, progress_every = 50L
  )
  fit_args_use <- list(
    fit_base = TRUE, fit_slope = FALSE, fit_fs = FALSE,
    event_k = 1L, lead = 1L, A_pre = 6L, B_post = 6L,
    k_week = 6L, k_p = 8L, k_fs = 4L,
    select = FALSE, verbose = FALSE
  )

  if (verbose)
    message(sprintf("[tune_m0] %d-spec grid | %d test folds | %d cores",
                    nrow(as.data.frame(grid)), length(test_seas), n_cores))

  tuning <- loso_M0v2(
    dat           = aligned,
    grid          = as.data.frame(grid),
    score_col     = "p_cls_p",
    drop_seasons  = if (length(drop_all) > 0) drop_all else NULL,
    exSeason_tune = NULL,
    fit_args      = fit_args_use,
    tune_args     = tune_args_use,
    verbose       = verbose
  )

  list(
    best_params   = tuning$best_params,
    tuning        = tuning,
    aligned       = aligned,
    seasons_used  = m0_built$seasons_used,
    manual_labels = manual_labels,
    flag_args     = flag_args
  )
}


# ============================================================
# M1
# ============================================================

#' Build M1 reference curve and alignment hyperparameters
#'
#' Fits the epidemic reference curve via \code{estimateRef()} and learns
#' alignment search bounds via \code{learn_alignment_hyperparams()}.
#' Inherits \code{manual_labels} and \code{flag_args} from \code{m0}.
#'
#' @param allD Multi-season surveillance data frame.
#' @param m0 Output of \code{tune_m0()} or \code{build_m0()}. Carries
#'   \code{manual_labels} and \code{flag_args} for consistent alignment.
#' @param exclude Character vector of seasons to exclude from the reference
#'   fit. Default excludes permanent invalid seasons and the 2015-16
#'   ignition outlier; 2025-26 is kept for production training.
#' @param exclude_live Logical. When \code{TRUE} (default), seasons with
#'   fewer than \code{min_live_weeks} observed weeks are also excluded
#'   (guards against partial current-season bias in the reference curve).
#' @param min_live_weeks Integer. Partial-season threshold (default \code{20L}).
#' @param m1_params Named list of M1 alignment parameters. Defaults to the
#'   canonical production specification.
#'
#' @return A list with \code{ref}, \code{hyper}, \code{aligned_train},
#'   \code{m1_params}, and \code{seasons_used}. Pass to \code{tune_m1()},
#'   \code{build_m2()}, and \code{train_m2()}.
#'
#' @export
build_m1 <- function(allD,
                     m0,
                     exclude        = c("2011-12", "2015-16", "2020-21", "2021-22"),
                     exclude_live   = TRUE,
                     min_live_weeks = 20L,
                     m1_params      = .default_m1_params()) {
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Need 'dplyr'.")

  manual_labels <- m0$manual_labels %||% .default_manual_labels()
  flag_args     <- m0$flag_args     %||% .default_flag_args()

  dat <- if (length(exclude) > 0)
    dplyr::filter(allD, !.data$season %in% exclude) else allD

  if (exclude_live) {
    week_counts <- tapply(dat$weekF, dat$season,
                          function(x) length(unique(x[!is.na(x)])))
    partial <- names(week_counts)[week_counts < as.integer(min_live_weeks)]
    if (length(partial) > 0) {
      message(sprintf("[build_m1] Excluding partial seasons: %s",
                      paste(partial, collapse = ", ")))
      dat <- dplyr::filter(dat, !.data$season %in% partial)
    }
  }

  seasons_used  <- sort(unique(dat$season))
  aligned_train <- build_m0(dat, exclude = character(0),
                             manual_labels = manual_labels,
                             flag_args = flag_args)$aligned

  ref   <- estimateRef(
    alignedD = aligned_train,
    exSeason = character(0),
    k        = as.integer(m1_params$k_ref %||% 25L),
    n_weeks  = 52L,
    method   = m1_params$ref_method %||% "fs"
  )
  hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)

  list(
    ref           = ref,
    hyper         = hyper,
    aligned_train = aligned_train,
    m1_params     = m1_params,
    seasons_used  = seasons_used
  )
}


#' Tune M1 alignment hyperparameters via LOSO grid search
#'
#' Runs leave-one-season-out grid search over M1 alignment parameters using
#' \code{tune_m1_alignment()}. Supports resumable checkpoints.
#'
#' @param allD Multi-season surveillance data frame.
#' @param m0 Output of \code{tune_m0()}. Must include \code{best_params}.
#' @param m1 Output of \code{build_m1()}. Provides \code{m1_params}.
#' @param loso_seasons Which seasons to use as LOSO test folds.
#'   \code{"all"} (default) tests every season; \code{"alternating"} tests
#'   every other season.
#' @param grid Tuning grid. Default: \code{default_m1_grid()}.
#' @param n_cores Integer. Parallel cores.
#' @param checkpoint_dir Character. Directory for resumable checkpoints.
#'   Uses a temp directory if \code{NULL}.
#' @param verbose Logical. Print progress.
#'
#' @return Output of \code{tune_m1_alignment()} -- a list with per-spec MAE
#'   scores and the best spec parameters.
#'
#' @export
tune_m1 <- function(allD,
                    m0,
                    m1,
                    loso_seasons   = "all",
                    grid           = default_m1_grid(),
                    n_cores        = parallel::detectCores() - 1L,
                    checkpoint_dir = NULL,
                    verbose        = TRUE) {
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Need 'dplyr'.")

  manual_labels <- m0$manual_labels %||% .default_manual_labels()
  m1_params     <- m1$m1_params     %||% .default_m1_params()
  params        <- m0$best_params
  if (is.null(params))
    stop("tune_m1 requires m0 from tune_m0() (needs best_params).")

  # loso_seasons controls test folds; non-selected seasons are excluded from
  # training too (acceptable trade-off for quick-demo mode).
  perm_excl  <- c("2011-12", "2020-21", "2021-22")
  all_seas   <- sort(setdiff(unique(allD$season), c(perm_excl, "2015-16")))
  test_seas  <- .select_loso_seasons(all_seas, loso_seasons)
  extra_excl <- setdiff(all_seas, test_seas)
  exclude_all <- unique(c("2015-16", extra_excl))

  if (is.null(checkpoint_dir))
    checkpoint_dir <- file.path(tempdir(), "m1_tune_ckpt")
  dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)

  # M1 tuning uses -1L offset on manual_labels (matches _extended_tune_m1_v7.R)
  manual_labels_v7 <- manual_labels - 1L

  if (verbose)
    message(sprintf("[tune_m1] %d-spec grid | %d test folds | %d cores",
                    nrow(as.data.frame(grid)), length(test_seas), n_cores))

  tune_m1_alignment(
    allD                = allD,
    params              = params,
    grid                = grid,
    manual_labels       = manual_labels_v7,
    exclude_seasons     = if (length(exclude_all) > 0) exclude_all else NULL,
    n_weeks             = 52L,
    use_multi_template  = TRUE,
    ref_method          = m1_params$ref_method %||% "fs",
    checkpoint_dir      = checkpoint_dir,
    n_cores             = as.integer(max(1L, n_cores)),
    verbose             = verbose,
    dynamic_temp        = isTRUE(m1_params$dynamic_temp),
    k_deriv             = 20L,
    buffer_weeks        = 5L,
    curvature_ratio     = 1.0,
    align_peak_decay    = m1_params$peak_decay    %||% 0.3,
    align_trough_weight = m1_params$trough_weight %||% 0.1,
    peak_weight_boost   = 3,
    peak_weight_decay   = 0.3
  )
}


# ============================================================
# M2
# ============================================================

#' Build M2 forecast model via nested LOSO grid search
#'
#' Runs Phase 1 (M1 walk-forward cache per LOSO fold) and Phase 2 (frozen
#' GAM + Holt EMA bias grid search) to identify the best M2 spec.
#' Uses \code{loso_seasons = "alternating"} by default for fast demos;
#' switch to \code{"all"} for production tuning.
#'
#' @param allD Multi-season surveillance data frame.
#' @param m0 Output of \code{tune_m0()}. Must include \code{best_params}.
#' @param m1 Output of \code{build_m1()}. Provides reference curve and params.
#' @param loso_seasons Which seasons to evaluate as LOSO test folds.
#'   \code{"alternating"} (default) halves tuning time; \code{"all"} for
#'   production quality. A character vector selects specific seasons.
#' @param exclude_seas Seasons to exclude from LOSO folds entirely.
#' @param holdout_season Prospective season excluded by default. Set to NULL
#'   only after an explicit promotion release.
#' @param grid Tuning grid. Default: compact \code{default_m2_grid()} plan.
#'   Per-row \code{bias_alpha} and \code{bias_beta} columns override their
#'   scalar fallbacks.
#' @param bias_alpha,bias_beta Numeric. Backward-compatible Holt EMA scalar
#'   fallbacks used when the grid omits the corresponding columns.
#' @param n_cores Integer. Parallel cores.
#' @param checkpoint_dir Character. Directory for Phase 2 checkpoint files.
#'   Pass \code{NULL} to disable checkpointing.
#' @param verbose Logical. Print progress.
#'
#' @return A list with \code{best_spec}, \code{best_spec_id}, \code{summary}
#'   (ranked by Bernoulli NLL), \code{scores}, \code{cv_results}, and
#'   \code{grid}. Pass \code{best_spec} to \code{train_m2()}.
#'
#' @export
build_m2 <- function(allD,
                     m0,
                     m1,
                     loso_seasons   = "alternating",
                     exclude_seas   = "2015-16",
                     holdout_season = "2025-26",
                     grid           = default_m2_grid(),
                     bias_alpha     = 0.4,
                     bias_beta      = 0,
                     n_cores        = parallel::detectCores() - 1L,
                     checkpoint_dir = NULL,
                     verbose        = TRUE) {
  if (!requireNamespace("dplyr",  quietly = TRUE)) stop("Need 'dplyr'.")
  if (!requireNamespace("purrr",  quietly = TRUE)) stop("Need 'purrr'.")
  if (!requireNamespace("furrr",  quietly = TRUE)) stop("Need 'furrr'.")
  if (!requireNamespace("future", quietly = TRUE)) stop("Need 'future'.")
  if (!requireNamespace("tibble", quietly = TRUE)) stop("Need 'tibble'.")

  manual_labels <- m0$manual_labels %||% .default_manual_labels()
  flag_args_use <- m0$flag_args     %||% .default_flag_args()
  m1_params     <- m1$m1_params     %||% .default_m1_params()
  params        <- m0$best_params
  ref           <- m1$ref
  hyper         <- m1$hyper
  if (is.null(params)) stop("build_m2 requires m0 from tune_m0() (needs best_params).")
  if (is.null(ref))    stop("build_m2 requires m1 from build_m1() (needs ref).")

  converted <- .m2_specs_from_grid(
    grid, bias_alpha = bias_alpha, bias_beta = bias_beta
  )
  grid_df <- converted$grid
  specs_list <- converted$specs
  spec_ids <- grid_df$spec_id
  perm_excl <- c("2011-12", "2020-21", "2021-22")
  exclude_all <- unique(c(exclude_seas, holdout_season, perm_excl))
  all_seas  <- sort(setdiff(unique(allD$season), exclude_all))
  test_seasons <- .select_loso_seasons(all_seas, loso_seasons)

  if (verbose)
    message(sprintf("[build_m2] %d specs | %d folds | loso=%s | %d cores",
                    nrow(grid_df), length(test_seasons), loso_seasons, n_cores))

  # ---- Phase 1: M1 cache per test fold ----
  if (verbose)
    message("[build_m2] Phase 1: M1 cache for ", length(test_seasons), " folds...")
  future::plan(future::multisession, workers = as.integer(max(1L, n_cores)))

  m1_cache <- list()
  for (test_s in test_seasons) {
    if (verbose) message(sprintf("  [%s] build_fold + M1...", test_s))
    fold <- tryCatch(
      nested_loso_build_fold(
        allD            = allD, test_season    = test_s,
        exclude_seasons = exclude_all,
        k_ref           = as.integer(m1_params$k_ref %||% 25L),
        ref_method      = m1_params$ref_method %||% "fs",
        manual_labels   = manual_labels, verbose = FALSE
      ),
      error = function(e) { message("  ERROR fold: ", conditionMessage(e)); NULL }
    )
    if (is.null(fold)) next

    m1_train <- tryCatch(
      m1_walkforward_multi(
        allD               = allD, ref = fold$ref, hyper = fold$hyper, params = params,
        seasons            = fold$train_seasons,
        temperature        = m1_params$temperature   %||% 0.25,
        rise_weight        = m1_params$rise_weight   %||% 1.0,
        trough_weight      = m1_params$trough_weight %||% 0.1,
        peak_decay         = m1_params$peak_decay    %||% 0.3,
        slope_weight       = m1_params$slope_weight  %||% 8.0,
        slope_window       = m1_params$slope_window  %||% 6L,
        dynamic_temp       = isTRUE(m1_params$dynamic_temp),
        dynamic_temp_pivot = m1_params$dynamic_temp_pivot %||% 10L,
        parallel = TRUE, verbose = FALSE
      ),
      error = function(e) { message("  ERROR m1_train: ", conditionMessage(e)); NULL }
    )
    m1_test <- tryCatch(
      m1_walkforward_predictions(
        seasonD            = allD[allD$season == test_s, ],
        ref = fold$ref, hyper = fold$hyper, params = params,
        temperature        = m1_params$temperature   %||% 0.25,
        rise_weight        = m1_params$rise_weight   %||% 1.0,
        trough_weight      = m1_params$trough_weight %||% 0.1,
        peak_decay         = m1_params$peak_decay    %||% 0.3,
        slope_weight       = m1_params$slope_weight  %||% 8.0,
        slope_window       = m1_params$slope_window  %||% 6L,
        dynamic_temp       = isTRUE(m1_params$dynamic_temp),
        dynamic_temp_pivot = m1_params$dynamic_temp_pivot %||% 10L
      ),
      error = function(e) { message("  ERROR m1_test: ", conditionMessage(e)); NULL }
    )
    m1_cache[[test_s]] <- list(fold = fold, m1_train = m1_train, m1_test = m1_test)
  }
  if (verbose) message("[build_m2] Phase 1 complete: ", length(m1_cache), " folds.\n")

  # ---- Phase 2: M2 grid search ----
  if (verbose) message("[build_m2] Phase 2: ", length(spec_ids), " specs...")

  cv_results <- list()
  todo_ids   <- spec_ids

  if (!is.null(checkpoint_dir)) {
    dir.create(checkpoint_dir, recursive = TRUE, showWarnings = FALSE)
    ckpt_file <- file.path(checkpoint_dir, "build_m2_phase2.rds")
    if (file.exists(ckpt_file)) {
      cv_results <- readRDS(ckpt_file)
      todo_ids   <- setdiff(spec_ids, names(cv_results))
      if (verbose)
        message(sprintf("[build_m2] Resuming: %d done, %d remaining",
                        length(cv_results), length(todo_ids)))
    }
  }

  if (length(todo_ids) > 0) {
    n_workers    <- as.integer(max(1L, n_cores))
    todo_batches <- split(todo_ids, ceiling(seq_along(todo_ids) / n_workers))
    future::plan(future::multisession, workers = n_workers)

    for (bi in seq_along(todo_batches)) {
      batch <- todo_batches[[bi]]
      if (verbose) cat(sprintf("  Batch %d/%d (%d specs)...", bi, length(todo_batches), length(batch)))
      t0 <- proc.time()[["elapsed"]]

      batch_res <- furrr::future_map(
        stats::setNames(batch, batch),
        function(spec_id) {
          spec        <- specs_list[[spec_id]]
          fold_scores <- vector("list", length(test_seasons))
          fold_preds  <- vector("list", length(test_seasons))
          names(fold_scores) <- names(fold_preds) <- test_seasons

          for (test_s in test_seasons) {
            fc <- m1_cache[[test_s]]
            if (is.null(fc)) next
            m2_fit <- tryCatch(
              nested_loso_m2_train(
                fold           = fc$fold,
                m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0)
                  fc$m1_train else NULL,
                spec = spec, method = "REML", verbose = FALSE
              ),
              error = function(e) NULL
            )
            eval_out <- tryCatch(
              nested_loso_m2_eval_frozen_bias(
                allD          = allD, fold = fc$fold, m2_fit = m2_fit,
                m1_test_preds = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0)
                  fc$m1_test else NULL,
                spec          = spec, eval_window = 12L,
                bias_alpha    = spec$bias_alpha, bias_beta = spec$bias_beta,
                manual_labels = manual_labels, flag_args = flag_args_use, verbose = FALSE
              ),
              error = function(e) NULL
            )
            if (is.null(eval_out)) {
              fold_scores[[test_s]] <- tibble::tibble(
                season = test_s, n = NA_integer_, mean_nll = NA_real_,
                bernoulli_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_
              )
              fold_preds[[test_s]] <- tibble::tibble()
            } else {
              fold_scores[[test_s]] <- eval_out$scores
              fold_preds[[test_s]]  <- eval_out$predictions
            }
          }
          list(scores = dplyr::bind_rows(fold_scores), predictions = dplyr::bind_rows(fold_preds))
        },
        .options = furrr::furrr_options(seed = TRUE)
      )
      cv_results <- c(cv_results, batch_res)
      if (!is.null(checkpoint_dir)) saveRDS(cv_results, ckpt_file)

      elapsed <- round(proc.time()[["elapsed"]] - t0)
      if (verbose) {
        batch_nlls <- sapply(batch_res, function(r)
          round(mean(r$scores$bernoulli_nll, na.rm = TRUE), 4))
        cat(sprintf(" %ds | NLL %.4f\u2013%.4f\n", elapsed,
                    min(batch_nlls, na.rm = TRUE), max(batch_nlls, na.rm = TRUE)))
      }
    }
    future::plan(future::sequential)
  }

  # Assemble results
  cv_all     <- cv_results[spec_ids]
  all_scores <- purrr::imap_dfr(cv_all, ~ dplyr::mutate(.x$scores, spec_id = .y))
  summary_df <- all_scores |>
    dplyr::group_by(.data$spec_id) |>
    dplyr::summarise(
      n_seasons     = dplyr::n(),
      bernoulli_nll = mean(.data$bernoulli_nll, na.rm = TRUE),
      mean_nll      = mean(.data$mean_nll,      na.rm = TRUE),
      brier         = mean(.data$brier,         na.rm = TRUE),
      rmse_p        = mean(.data$rmse_p,        na.rm = TRUE),
      .groups       = "drop"
    ) |>
    dplyr::arrange(.data$bernoulli_nll)

  best_id   <- summary_df$spec_id[1]
  best_spec <- specs_list[[best_id]]

  if (verbose) {
    message(sprintf("[build_m2] Best spec: %s (NLL=%.4f)",
                    best_id, summary_df$bernoulli_nll[1]))
    print(utils::head(summary_df[, c("spec_id", "bernoulli_nll")], 5))
  }

  list(
    best_spec    = best_spec,
    best_spec_id = best_id,
    summary      = summary_df,
    scores       = all_scores,
    cv_results   = cv_all,
    grid         = grid_df
  )
}


#' Fit the M2 production GAM on all training seasons
#'
#' Trains the Stage-2 GAM on all non-excluded seasons using the best spec
#' from \code{build_m2()}. Runs M1 walk-forward predictions before fitting.
#'
#' @param allD Multi-season surveillance data frame.
#' @param m0 Output of \code{tune_m0()}. Must include \code{best_params}.
#' @param m1 Output of \code{build_m1()}. Provides \code{ref} and \code{hyper}.
#' @param best_spec Stage-2 spec from \code{build_m2()$best_spec} or
#'   \code{stage2_make_spec()}. When \code{NULL}, uses the locked deployed v16
#'   specification for a production-data refresh without retuning.
#' @param exclude Character vector of seasons to exclude from training.
#'   Default excludes permanent invalid seasons and 2015-16. Note: 2025-26
#'   is kept (production training uses the current season).
#' @param verbose Logical. Print progress.
#'
#' @return A list with \code{fit} (GAM), \code{feature_ranges}, \code{m1_train_preds},
#'   \code{spec}, \code{training_seasons}, and \code{spec_version}. Pass to
#'   \code{assemble_kit()}.
#'
#' @export
train_m2 <- function(allD,
                     m0,
                     m1,
                     best_spec = NULL,
                     exclude  = c("2011-12", "2015-16", "2020-21", "2021-22"),
                     verbose  = FALSE) {
  if (!requireNamespace("dplyr",  quietly = TRUE)) stop("Need 'dplyr'.")
  if (!requireNamespace("purrr",  quietly = TRUE)) stop("Need 'purrr'.")
  if (!requireNamespace("future", quietly = TRUE)) stop("Need 'future'.")

  if (is.null(best_spec)) best_spec <- .default_m2_spec()

  manual_labels <- m0$manual_labels %||% .default_manual_labels()
  flag_args_use <- m0$flag_args     %||% .default_flag_args()
  m1_params     <- m1$m1_params     %||% .default_m1_params()
  params        <- m0$best_params
  ref           <- m1$ref
  hyper         <- m1$hyper

  if (is.null(params)) stop("train_m2 requires m0 from tune_m0() (needs best_params).")
  if (is.null(ref))    stop("train_m2 requires m1 from build_m1() (needs ref).")

  allD_prod  <- if (length(exclude) > 0)
    dplyr::filter(allD, !.data$season %in% exclude) else allD
  train_seas <- sort(unique(allD_prod$season))

  if (verbose) message(sprintf("[train_m2] %d training seasons", length(train_seas)))

  # Align production training data
  res_deriv   <- estimateDerivs(allD_prod, k = 10L)
  train_outs  <- res_deriv$data |>
    dplyr::group_by(.data$season) |>
    dplyr::group_split(.keep = TRUE) |>
    purrr::map(function(df)
      do.call(flagIgnition, c(list(df = df, manual_labels = manual_labels), flag_args_use)))
  aligned_train <- alignIgnition(train_outs)

  # M1 walk-forward predictions for all training seasons
  if (verbose) message("[train_m2] M1 walk-forward predictions...")
  future::plan(future::multisession,
               workers = max(1L, parallel::detectCores() - 1L))
  m1_train_preds <- m1_walkforward_multi(
    allD               = allD, ref = ref, hyper = hyper, params = params,
    seasons            = train_seas,
    temperature        = m1_params$temperature   %||% 0.25,
    rise_weight        = m1_params$rise_weight   %||% 1.0,
    trough_weight      = m1_params$trough_weight %||% 0.1,
    peak_decay         = m1_params$peak_decay    %||% 0.3,
    slope_weight       = m1_params$slope_weight  %||% 8.0,
    slope_window       = m1_params$slope_window  %||% 6L,
    dynamic_temp       = isTRUE(m1_params$dynamic_temp),
    dynamic_temp_pivot = m1_params$dynamic_temp_pivot %||% 10L,
    parallel = TRUE, verbose = verbose
  )
  future::plan(future::sequential)

  # Fit production GAM
  if (verbose) message("[train_m2] Fitting production GAM...")
  joint_out <- train_stage2_joint(
    dat         = add_prospective_derivs_link(aligned_train),
    template_df = ref$pred_df[, c("newWeek", "fit")],
    spec        = best_spec,
    method      = "REML",
    m1_preds    = if (nrow(m1_train_preds) > 0) m1_train_preds else NULL,
    verbose     = verbose
  )

  if (verbose)
    message(sprintf("[train_m2] GAM EDF = %.2f | %d training seasons",
                    round(sum(joint_out$fit$edf), 2), length(train_seas)))

  list(
    fit              = joint_out$fit,
    feature_ranges   = joint_out$feature_ranges,
    m1_train_preds   = m1_train_preds,
    spec             = best_spec,
    training_seasons = train_seas,
    spec_version     = "assembled"
  )
}


# ============================================================
# Kit assembly
# ============================================================

#' Bundle trained artifacts for prospective deployment
#'
#' Assembles M0, M1, and M2 training outputs into the format returned by
#' \code{load_prospective_kit()}, ready for use with \code{run_pipeline()},
#' \code{run_m0()}, \code{run_m1()}, and \code{run_m2()}. Optionally saves
#' reference and M2 bundles to disk.
#'
#' @param m0 Output of \code{tune_m0()}.
#' @param m1 Output of \code{build_m1()}.
#' @param m2_model Output of \code{train_m2()}.
#' @param best_spec_id Character label for the best M2 spec (optional;
#'   taken from \code{build_m2()$best_spec_id}).
#' @param save_ref_path Character. If set, saves the reference bundle
#'   (\code{ref_production.rds} format) to this path.
#' @param save_m2_path Character. If set, saves the M2 bundle
#'   (\code{m2_production.rds} format) to this path.
#'
#' @return A kit list compatible with all \code{run_*()} functions.
#'
#' @export
assemble_kit <- function(m0,
                         m1,
                         m2_model,
                         best_spec_id  = NULL,
                         save_ref_path = NULL,
                         save_m2_path  = NULL) {
  manual_labels <- m0$manual_labels %||% .default_manual_labels()
  flag_args     <- m0$flag_args     %||% .default_flag_args()
  m1_params     <- m1$m1_params     %||% .default_m1_params()

  ref_bundle <- list(
    ref           = m1$ref,
    hyper         = m1$hyper,
    hist_data     = m1$aligned_train,
    M1_PARAMS     = m1_params,
    flag_args     = flag_args,
    manual_labels = manual_labels
  )

  m2_bundle <- list(
    spec             = m2_model$spec,
    fit              = m2_model$fit,
    feature_ranges   = m2_model$feature_ranges,
    m1_train_preds   = m2_model$m1_train_preds,
    training_seasons = m2_model$training_seasons,
    spec_version     = m2_model$spec_version %||% "assembled",
    best_spec_id     = best_spec_id %||% ""
  )

  if (!is.null(save_ref_path)) {
    saveRDS(ref_bundle, save_ref_path)
    message("[assemble_kit] Saved ref bundle to: ", save_ref_path)
  }
  if (!is.null(save_m2_path)) {
    saveRDS(m2_bundle, save_m2_path)
    message("[assemble_kit] Saved M2 bundle to: ", save_m2_path)
  }

  # M1_PARAMS slot in kit matches load_prospective_kit() fallback structure
  M1_PARAMS_kit <- list(
    k_ref              = m1_params$k_ref              %||% 25L,
    temperature        = m1_params$temperature        %||% 0.25,
    rise_weight        = m1_params$rise_weight        %||% 1.0,
    trough_weight      = m1_params$trough_weight      %||% 0.1,
    peak_decay         = m1_params$peak_decay         %||% 0.3,
    slope_weight       = m1_params$slope_weight       %||% 0.5,
    slope_window       = m1_params$slope_window       %||% 4L,
    dynamic_temp       = m1_params$dynamic_temp       %||% FALSE,
    dynamic_temp_pivot = m1_params$dynamic_temp_pivot %||% 10L
  )

  list(
    ref            = m1$ref,
    hyper          = m1$hyper,
    M1_PARAMS      = M1_PARAMS_kit,
    m0_params      = m0$best_params,
    m2_production  = m2_bundle,
    best_spec      = m2_model$spec,
    flag_args      = flag_args,
    manual_labels  = manual_labels,
    hist_data      = m1$aligned_train,
    m1_train_preds = m2_model$m1_train_preds,
    template_df    = m1$ref$pred_df[, c("newWeek", "fit")]
  )
}
