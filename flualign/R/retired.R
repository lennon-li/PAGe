# =========================================================================
# retired.R - Legacy / deprecated functions
#
# These functions are no longer used by the active M2 pipeline but are
# preserved here for reference.  They were extracted from:
#   - m2_spec_grid.R   (prep_stage2_m1_features, train_stage2_joint_m1,
#                        tune_stage2_loso_spec_grid,
#                        tune_stage2_loso_spec_grid_parallel)
#   - m2_training.R    (tune_stage2_loso_specs, tune_stage2_loso_shift_template,
#                        plot_tune_stage2_heatmap, make_prospective_kit,
#                        check_prospective_kit)
#   - pipeline_bridge.R (run_m0_m1_m2_weekly)
#
# Active code should NOT source this file.  It exists only as an archive.
# =========================================================================


# --- from R/m2_spec_grid.R ---

prep_stage2_m1_features <- function(alignedD_prosp,
                                    template_df,
                                    spec,
                                    ignD = NULL,
                                    eps = 1e-6,
                                    n_weeks = NULL) {
  .Deprecated("prep_stage2_joint",
              msg = paste("prep_stage2_m1_features() is deprecated.",
                          "Use prep_stage2_joint() from m2_training.R instead.",
                          "The callers of this function (tune_stage2_loso_spec_grid) are also deprecated."))
  stop("prep_stage2_m1_features() is deprecated. Use prep_stage2_joint() instead.")
  if (!is.list(spec) || !all(c("delta","Kr","alpha_state","T") %in% names(spec))) {
    stop("spec must be a list from stage2_make_spec() with delta/Kr/alpha_state/T.")
  }
  
  DT <- data.table::as.data.table(data.table::copy(alignedD_prosp))
  need <- c("season","weekF","newWeek")
  miss <- setdiff(need, names(DT))
  if (length(miss)) stop("alignedD_prosp missing columns: ", paste(miss, collapse = ", "))
  
  y_col <- if ("y" %in% names(DT)) "y" else if ("x" %in% names(DT)) "x" else stop("Need y or x.")
  n_col <- if ("N" %in% names(DT)) "N" else if ("n" %in% names(DT)) "n" else stop("Need N or n.")
  
  d1_src <- if ("d1_link" %in% names(DT)) "d1_link" else if ("d1" %in% names(DT)) "d1" else NULL
  d2_src <- if ("d2_link" %in% names(DT)) "d2_link" else if ("d2" %in% names(DT)) "d2" else NULL
  
  DT[, `:=`(
    y_now  = as.integer(get(y_col)),
    N_now  = as.integer(get(n_col)),
    d1_now = if (!is.null(d1_src)) as.numeric(get(d1_src)) else NA_real_,
    d2_now = if (!is.null(d2_src)) as.numeric(get(d2_src)) else NA_real_
  )]
  
  if (is.null(n_weeks)) n_weeks <- as.integer(max(template_df$newWeek, na.rm = TRUE))
  ref_logit_fun <- make_ref_logit_fun_from_template(template_df, n_weeks = n_weeks)
  
  # ignition week per season
  ign_tbl <- NULL
  if ("iWeek" %in% names(DT) && any(!is.na(DT$iWeek))) {
    ign_tbl <- DT[!is.na(iWeek), .(ign_weekF = suppressWarnings(min(as.integer(iWeek), na.rm = TRUE))), by = season]
    ign_tbl[!is.finite(ign_weekF), ign_weekF := NA_integer_]
  } else if ("ignition" %in% names(DT) && any(DT$ignition == 1, na.rm = TRUE)) {
    ign_tbl <- DT[ignition == 1, .(ign_weekF = min(as.integer(weekF), na.rm = TRUE)), by = season]
  } else if (!is.null(ignD)) {
    IG <- data.table::as.data.table(data.table::copy(ignD))
    if (!all(c("season","weekF") %in% names(IG))) stop("ignD must contain season and weekF.")
    if ("rule_level" %in% names(IG)) {
      ign_tbl <- IG[is.finite(rule_level) & rule_level > 0, .(ign_weekF = min(as.integer(weekF))), by = season]
    }
    if (is.null(ign_tbl) || nrow(ign_tbl) == 0L) {
      if ("rule_name" %in% names(IG)) {
        ign_tbl <- IG[!is.na(rule_name) & rule_name != "", .(ign_weekF = min(as.integer(weekF))), by = season]
      }
    }
  }
  if (is.null(ign_tbl) || nrow(ign_tbl) == 0L) {
    stop("Cannot derive ign_weekF: need iWeek or ignition in alignedD_prosp, or provide ignD.")
  }
  
  DT[ign_tbl, ign_weekF := i.ign_weekF, on = "season"]
  DT[, t_rel := as.integer(weekF) - as.integer(ign_weekF)]
  
  # template covariate with ramp omega(t;Kr)
  DT[, `:=`(omega = 0.0, newWeek_shift = NA_integer_, logit_template = NA_real_, logit_f_eff = 0.0)]
  if (!identical(spec$T, "N") && !is.na(spec$delta) && !is.na(spec$Kr)) {
    Kr <- as.integer(spec$Kr)
    DT[!is.na(ign_weekF), omega := pmin(1, pmax(0, t_rel / Kr))]
    DT[!is.na(ign_weekF), newWeek_shift := wrap_week(newWeek + as.integer(spec$delta), n_weeks)]
    DT[!is.na(ign_weekF), logit_template := ref_logit_fun(newWeek_shift)]
    DT[!is.na(ign_weekF), logit_f_eff := omega * logit_template]
  }
  
  # EWMA state
  DT[, p_now := pmin(1 - eps, pmax(eps, y_now / pmax(1L, N_now)))]
  DT[, logit_y_now := qlogis(p_now)]
  a <- as.numeric(spec$alpha_state %||% NA_real_)
  if (is.na(a)) {
    DT[, z_ema := NA_real_]
  } else {
    data.table::setorderv(DT, c("season","weekF"))
    DT[, z_ema := ewma_recursive(logit_y_now, a), by = season]
  }
  
  DT[, logN_now := log(pmax(1L, N_now))]
  DT[]
}


# ============================================================
# 4) train_stage2_joint_m1()
# ============================================================

#' Fit the Stage-2 joint M1 model for a given spec
#'
#' Internally stacks data across \code{spec$leads} and fits \code{mgcv::bam()} using \code{spec$formula}.
#' Training window is applied via:
#' \code{weekF >= ign_weekF - Kb}, where \code{Kb = spec$Kb}.
#'
#' Creates \code{season_h = interaction(season, lead)} to match your formula usage.
#' Saves \code{fit$stage2_levels} for safe LOSO/new-season prediction alignment.
#'
#' @param feat Output of \code{prep_stage2_m1_features()}.
#' @param spec Output of \code{stage2_make_spec()} (must contain \code{formula}, \code{Kb}, \code{leads}).
#' @param seasons_keep Optional vector of seasons to include for training (used in LOSO).
#' @param drop_future If TRUE, drop rows where target outcomes are unavailable.
#' @param nthreads Threads for \code{mgcv::bam()}.
#' @param method \code{bam()} fitting method (default "fREML").
#' @param discrete Logical; discrete approximation (default TRUE).
#' @param return_data If TRUE, return stacked training data as \code{d_train}.
#' @param ... Passed to \code{mgcv::bam()}.
#'
#' @return List with \code{fit}, \code{spec}, and optionally \code{d_train}.
#' @export

# --- from R/m2_spec_grid.R ---

train_stage2_joint_m1 <- function(feat,
                                  spec,
                                  seasons_keep = NULL,
                                  drop_future = TRUE,
                                  nthreads = 4L,
                                  method = "fREML",
                                  discrete = TRUE,
                                  return_data = TRUE,
                                  ...) {
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Please install data.table.")
  if (!requireNamespace("mgcv", quietly = TRUE)) stop("Please install mgcv.")
  
  DT <- data.table::as.data.table(data.table::copy(feat))
  if (!is.null(seasons_keep)) DT <- DT[season %in% seasons_keep]
  
  H  <- as.integer(spec$leads %||% c(1L,2L))
  Kb <- as.integer(spec$Kb %||% 0L)
  
  data.table::setorderv(DT, c("season","weekF"))
  
  d_train <- data.table::rbindlist(lapply(H, function(hh) {
    d <- data.table::copy(DT)
    d[, `:=`(
      lead_n = hh,
      lead   = factor(hh, levels = H),
      y_lead = data.table::shift(y_now, n = hh, type = "lead"),
      N_lead = data.table::shift(N_now, n = hh, type = "lead")
    ), by = season]
    d
  }), use.names = TRUE)
  
  d_train <- d_train[weekF >= (ign_weekF - Kb)]
  if (isTRUE(drop_future)) d_train <- d_train[!is.na(y_lead) & !is.na(N_lead)]
  
  d_train[, season := factor(season)]
  d_train[, lead   := factor(lead, levels = H)]
  d_train[, season_h := factor(interaction(season, lead, drop = TRUE))]
  
  form <- spec$formula
  if (is.null(form)) form <- stage2_build_joint_formula(spec)
  
  fit <- mgcv::bam(
    formula  = form,
    data     = d_train,
    family   = binomial(),
    method   = method,
    discrete = discrete,
    nthreads = as.integer(nthreads),
    ...
  )
  
  fit$stage2_levels <- list(
    season   = levels(d_train$season),
    lead     = levels(d_train$lead),
    season_h = levels(d_train$season_h)
  )
  
  if (isTRUE(return_data)) list(fit = fit, d_train = d_train, spec = spec) else list(fit = fit, spec = spec)
}


# ============================================================
# 5) tune_stage2_loso_spec_grid()
# ============================================================

#' LOSO tuning over a spec grid with weighted scoring near ignition
#'
#' For each spec_id in \code{spec_grid$specs}:
#' \enumerate{
#'   \item Prepare features once via \code{prep_stage2_m1_features()}.
#'   \item For each held-out season, fit \code{train_stage2_joint_m1()} on the remaining seasons.
#'   \item Predict on held-out season excluding season-dependent terms (new-season evaluation).
#'   \item Score using weighted NLL / Brier / RMSE(p).
#' }
#'
#' Weighting uses **target-week time since ignition**:
#' \deqn{t_\text{target} = (w + h) - w^{(ign)}}
#' Rows with \code{0 <= t_target <= k_t} get weight \code{w_early} (default 2),
#' later rows weight 1.
#'
#' @param alignedD_prosp Raw aligned dataset.
#' @param template_df Template reference df.
#' @param spec_grid Output of \code{expand_grid_specs()} (must include \code{$specs} and \code{$grid}).
#' @param ignD Optional ignition rule table (fallback).
#' @param seasons Optional subset of seasons to include. Must be >=3 for LOSO.
#' @param k_t Integer emphasized window length (weeks since ignition on TARGET week).
#' @param w_early Numeric multiplier for emphasized window.
#' @param exclude_newseason_terms If TRUE, exclude \code{spec$exclude_newseason} when predicting held-out season.
#' @param nthreads Threads for bam fits
#' #' Parallelization uses future.apply and works on Windows (multisession) and Linux/macOS (multicore).
#' Best practice: parallelize over "spec" and set mgcv::bam(nthreads=1) to avoid oversubscription.
#'
#' @param parallel Logical; if TRUE uses future.apply.
#' @param parallel_over "spec" (recommended) or "fold".
#' @param workers Integer; number of workers. Default uses future::availableCores().
#' @param strategy "auto"|"multisession"|"multicore"|"sequential".
#' @param verbose Logical.
#'
#' @return List with:
#' \itemize{
#'   \item \code{by_season}: per-spec per-heldout-season metrics
#'   \item \code{by_spec}: aggregated metrics per spec_id
#'   \item \code{by_spec_grid}: by_spec joined back to the grid
#'   \item \code{best}: best spec row
#'   \item \code{scoring}: k_t and w_early used
#'   \item \code{timing}: elapsed and cpu seconds
#' }
#' @export

# --- from R/m2_spec_grid.R ---

tune_stage2_loso_spec_grid <- function(alignedD_prosp,
                                       template_df,
                                       spec_grid,
                                       ignD = NULL,
                                       seasons = NULL,
                                       k_t = 10L,
                                       w_early = 2,
                                       exclude_newseason_terms = TRUE,
                                       # threading inside bam (keep 1 when parallel_over="spec")
                                       nthreads = 1L,
                                       verbose = TRUE,
                                       # parallel controls
                                       parallel = TRUE,
                                       parallel_over = c("spec","fold"),
                                       workers = NULL,
                                       strategy = c("auto","multisession","multicore","sequential"),
                                       # raise global export limit (GB); set NULL to not change
                                       max_global_size_gb = 4) {
  
  .Deprecated("nested_loso_grid_search",
              msg = paste("tune_stage2_loso_spec_grid() is deprecated.",
                          "Use nested_loso_grid_search() from m2_nested_loso.R instead.",
                          "This function depends on undefined stack_stage2_joint_data()."))
  stop("tune_stage2_loso_spec_grid() is deprecated. Use nested_loso_grid_search() instead.")
  
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Please install data.table.")
  if (!requireNamespace("future", quietly = TRUE)) stop("Please install future.")
  if (!requireNamespace("future.apply", quietly = TRUE)) stop("Please install future.apply.")
  
  parallel_over <- match.arg(parallel_over)
  strategy <- match.arg(strategy)
  
  if (parallel_over != "spec") {
    stop("For cross-platform + memory safety, use parallel_over='spec'. (Fold-parallel is possible but heavier.)")
  }
  
  stopifnot(is.list(spec_grid), !is.null(spec_grid$specs), !is.null(spec_grid$grid))
  specs <- spec_grid$specs
  grid  <- spec_grid$grid
  
  all_seasons <- seasons %||% sort(unique(alignedD_prosp$season))
  if (length(all_seasons) < 3L) stop("LOSO needs >= 3 seasons (each training fold must have >=2 season levels).")
  
  # ---- timing ----
  t_start <- Sys.time()
  pt_start <- proc.time()
  
  # ---- future settings ----
  if (!isTRUE(parallel)) strategy_use <- "sequential" else {
    if (strategy == "auto") {
      strategy_use <- if (.Platform$OS.type == "windows") "multisession" else "multicore"
    } else strategy_use <- strategy
  }
  if (is.null(workers)) workers <- future::availableCores()
  
  # Increase max globals threshold if requested
  if (!is.null(max_global_size_gb)) {
    old_max <- getOption("future.globals.maxSize")
    new_max <- max(old_max %||% 0, as.numeric(max_global_size_gb) * 1024^3)
    options(future.globals.maxSize = new_max)
    on.exit(options(future.globals.maxSize = old_max), add = TRUE)
  }
  
  old_plan <- future::plan()
  on.exit(future::plan(old_plan), add = TRUE)
  future::plan(strategy_use, workers = workers)
  
  if (isTRUE(verbose)) {
    message("[tune_stage2_loso_spec_grid] specs=", length(specs),
            " | seasons=", length(all_seasons),
            " | scoring: k_t=", k_t, " w_early=", w_early,
            " | exclude_newseason_terms=", exclude_newseason_terms,
            " | parallel=", parallel, " over=spec",
            " | strategy=", strategy_use, " workers=", workers,
            " | bam nthreads=", nthreads)
    if (isTRUE(parallel) && nthreads > 1L) {
      message("[tune_stage2_loso_spec_grid] NOTE: parallel over specs + bam(nthreads>1) can oversubscribe. Prefer nthreads=1.")
    }
  }
  
  # ---- Build X as (spec_id, spec) pairs so we DON'T export the full specs list as a global ----
  items <- Map(function(id, sp) list(spec_id = id, spec = sp), names(specs), specs)
  
  # ---- Worker FUN: set env to baseenv() to avoid capturing huge parent env ----
  worker_fun <- function(item,
                         alignedD_prosp, template_df, ignD, all_seasons,
                         k_t, w_early, exclude_newseason_terms,
                         nthreads) {
    
    spec_id <- item$spec_id
    sp      <- item$spec
    
    # ensure exclude list exists
    if (is.null(sp$exclude_newseason)) sp$exclude_newseason <- stage2_exclude_newseason(sp)
    
    # prep once per spec
    feat <- prep_stage2_m1_features(
      alignedD_prosp = alignedD_prosp,
      template_df    = template_df,
      spec           = sp,
      ignD           = ignD
    )
    
    # per-fold results
    out_list <- lapply(all_seasons, function(s_out) {
      train_seasons <- setdiff(all_seasons, s_out)
      
      out_fit <- train_stage2_joint_m1(
        feat = feat,
        spec = sp,
        seasons_keep = train_seasons,
        drop_future = TRUE,
        nthreads = nthreads,
        return_data = FALSE
      )
      fit_mod <- out_fit$fit
      
      d_test <- stack_stage2_joint_data(
        feat = feat,
        spec = sp,
        seasons_keep = s_out,
        drop_future = TRUE
      )
      
      # align levels for new-season prediction (avoid new factor levels)
      lev_lead   <- fit_mod$stage2_levels$lead
      lev_season <- fit_mod$stage2_levels$season
      lev_sh     <- fit_mod$stage2_levels$season_h
      
      d_test$lead <- factor(as.character(d_test$lead), levels = lev_lead)
      d_test$season <- factor(as.character(d_test$season), levels = lev_season)
      if (anyNA(d_test$season)) d_test$season[is.na(d_test$season)] <- lev_season[1]
      d_test$season_h <- interaction(d_test$season, d_test$lead, drop = TRUE)
      d_test$season_h <- factor(d_test$season_h, levels = lev_sh)
      if (anyNA(d_test$season_h)) d_test$season_h[is.na(d_test$season_h)] <- lev_sh[1]
      
      ex <- if (isTRUE(exclude_newseason_terms)) sp$exclude_newseason else NULL
      # Frozen LOSO: always exclude s(season) — test season is NOT in training.
      ex <- unique(c(ex, "s(season)"))
      eta <- as.numeric(stats::predict(fit_mod, newdata = d_test, type = "link", exclude = ex))
      p   <- plogis(eta)
      
      # weighted scoring by TARGET week t_target = (w+h) - ign_weekF
      t_target <- (d_test$weekF + d_test$lead_n) - d_test$ign_weekF
      w <- rep(1, length(t_target))
      w[is.finite(t_target) & t_target >= 0 & t_target <= as.integer(k_t)] <- as.numeric(w_early)
      
      y <- as.numeric(d_test$y_lead)
      N <- as.numeric(d_test$N_lead)
      p <- pmin(1 - 1e-12, pmax(1e-12, p))
      
      ok <- is.finite(y) & is.finite(N) & is.finite(p) & (N > 0) & is.finite(w)
      y <- y[ok]; N <- N[ok]; p <- p[ok]; w <- w[ok]
      
      ll <- stats::dbinom(y, size = N, prob = p, log = TRUE)
      nll <- -sum(w * ll)
      
      phat <- y / N
      se2  <- (p - phat)^2
      brier_num <- sum(w * se2)
      w_sum <- sum(w)
      
      data.table::data.table(
        spec_id = spec_id,
        season_out = as.character(s_out),
        n = length(p),
        w_sum = w_sum,
        nll = nll,
        mean_nll = nll / w_sum,
        brier = brier_num / w_sum,
        rmse_p = sqrt(brier_num / w_sum),
        brier_num = brier_num
      )
    })
    
    data.table::rbindlist(out_list)
  }
  environment(worker_fun) <- baseenv()
  
  # ---- Run parallel over specs ----
  if (isTRUE(parallel)) {
    res_list <- future.apply::future_lapply(
      items,
      worker_fun,
      alignedD_prosp = alignedD_prosp,
      template_df    = template_df,
      ignD           = ignD,
      all_seasons    = all_seasons,
      k_t            = k_t,
      w_early        = w_early,
      exclude_newseason_terms = exclude_newseason_terms,
      nthreads       = nthreads,
      future.seed    = TRUE,
      future.packages = c("data.table", "mgcv")
    )
    by_season <- data.table::rbindlist(res_list, use.names = TRUE, fill = TRUE)
  } else {
    by_season <- data.table::rbindlist(
      lapply(items, worker_fun,
             alignedD_prosp = alignedD_prosp,
             template_df    = template_df,
             ignD           = ignD,
             all_seasons    = all_seasons,
             k_t            = k_t,
             w_early        = w_early,
             exclude_newseason_terms = exclude_newseason_terms,
             nthreads       = nthreads),
      use.names = TRUE, fill = TRUE
    )
  }
  
  by_spec <- by_season[, .(
    n_total = sum(n),
    w_total = sum(w_sum),
    nll = sum(nll),
    mean_nll = sum(nll) / sum(w_sum),
    brier = sum(brier_num) / sum(w_sum),
    rmse_p = sqrt(sum(brier_num) / sum(w_sum))
  ), by = spec_id][order(mean_nll)]
  
  by_spec_grid <- data.table::as.data.table(grid)[by_spec, on = "spec_id"]
  
  # ---- timing ----
  t_end <- Sys.time()
  pt_end <- proc.time()
  timing <- list(
    start = t_start,
    end = t_end,
    elapsed_sec = as.numeric(difftime(t_end, t_start, units = "secs")),
    cpu_sec = unname((pt_end - pt_start)[["user.self"]] + (pt_end - pt_start)[["sys.self"]])
  )
  
  if (isTRUE(verbose)) {
    message(sprintf("[tune_stage2_loso_spec_grid] done in %.1f sec (cpu %.1f sec)",
                    timing$elapsed_sec, timing$cpu_sec))
  }
  
  list(
    by_season = by_season,
    by_spec = by_spec,
    by_spec_grid = by_spec_grid,
    best = by_spec[1],
    scoring = list(k_t = as.integer(k_t), w_early = as.numeric(w_early)),
    timing = timing,
    parallel = list(enabled = parallel, over = "spec", strategy = strategy_use, workers = workers, bam_nthreads = nthreads,
                    future_globals_max_gb = max_global_size_gb)
  )
}



#' LOSO tuning over a Stage-2 spec grid (disk-backed parallel; Linux + Windows)
#'
#' Performs leave-one-season-out (LOSO) tuning for Stage-2 by evaluating each
#' hyperparameter setting (spec) against held-out seasons, using weighted scoring
#' near ignition. This implementation is designed for **large grids** and
#' **cross-platform parallelism** (Windows + Linux/macOS) without hitting
#' `future.globals.maxSize` limits.
#'
#' ## Key design
#' - Writes large inputs (\code{alignedD_prosp}, \code{template_df}, \code{ignD}, \code{spec_grid$grid})
#'   to temporary \code{.rds} files once, then parallel workers receive only file paths + indices.
#' - Workers process \code{chunk_size} specs sequentially per job to reduce overhead.
#'
#' ## Requirements / dependencies
#' This function assumes these project functions already exist:
#' \itemize{
#'   \item \code{stage2_make_spec()}
#'   \item \code{prep_stage2_m1_features()}
#'   \item \code{stack_stage2_joint_data()}
#'   \item \code{train_stage2_joint_m1()}
#'   \item \code{stage2_exclude_newseason()} and \code{stage2_build_joint_formula()} (indirectly via spec)
#' }
#'
#' Also requires packages: \code{future}, \code{future.apply}, \code{data.table}, \code{mgcv}.
#'
#' ## Scoring weights
#' Uses **target-week** time-since-ignition:
#' \deqn{t_\mathrm{target} = (w + h) - w^{(\mathrm{ign})}}
#' Rows with \code{0 <= t_target <= k_t} are weighted \code{w_early} (default 2),
#' otherwise weight 1.
#'
#' ## Spec grid format
#' Uses \code{spec_grid$grid} (data.frame / data.table) with at least the columns:
#' \code{spec_id}, \code{delta}, \code{Kr}, \code{Kb}, \code{T}, \code{k_f},
#' \code{alpha_state}, \code{k_w}, \code{k_s}, \code{k_e}, \code{k_n},
#' \code{k_1}, \code{k_2}, \code{bs_week}, \code{bs_fs_marginal}.
#'
#' @param alignedD_prosp Aligned prospective dataset (all seasons) used for feature prep.
#'   Must contain your required columns (season/weekF/newWeek plus y/N etc).
#' @param template_df Template reference data.frame with columns \code{newWeek} and \code{fit}
#'   (logit-scale template).
#' @param spec_grid Output from \code{expand_grid_specs()}, containing \code{$grid} with
#'   the hyperparameter combinations and a unique \code{spec_id} per row.
#' @param ignD Optional ignition-rule table used as a fallback to derive ignition week
#'   when \code{iWeek} / \code{ignition} are not present in \code{alignedD_prosp}.
#' @param seasons Optional character vector of seasons to include in LOSO.
#'   If NULL, uses all seasons in \code{alignedD_prosp}. Must be >= 3.
#' @param k_t Integer. Number of **target weeks since ignition** to upweight in scoring.
#' @param w_early Numeric. Weight multiplier for the emphasized window (default 2).
#' @param exclude_newseason_terms Logical. If TRUE, predictions on the held-out season
#'   exclude season-dependent terms using \code{spec$exclude_newseason}.
#' @param workers Integer. Number of parallel workers.
#' @param strategy Future plan strategy. \code{"auto"} chooses \code{"multisession"} on Windows
#'   and \code{"multicore"} on Linux/macOS. You can force \code{"multisession"} for portability.
#' @param chunk_size Integer. Number of specs evaluated per worker job (reduces overhead).
#'   Typical values 4–16.
#' @param nthreads Integer. Threads passed to \code{mgcv::bam()} inside each worker.
#'   When \code{workers>1}, set \code{nthreads=1} to avoid CPU oversubscription.
#' @param cache_dir Directory for temporary \code{.rds} files. Defaults to \code{tempdir()}.
#'   Files are removed automatically on exit.
#' @param verbose Logical. If TRUE, prints a short run header and timing summary.
#'
#' @return A list with:
#' \itemize{
#'   \item \code{by_season}: data.table of per-spec per-heldout-season metrics
#'   \item \code{by_spec}: aggregated metrics per \code{spec_id} (ordered by \code{mean_nll})
#'   \item \code{by_spec_grid}: \code{by_spec} joined back onto \code{spec_grid$grid}
#'   \item \code{best}: best row of \code{by_spec}
#'   \item \code{scoring}: list(k_t, w_early)
#'   \item \code{timing}: list(start, end, elapsed_sec, cpu_sec)
#'   \item \code{parallel}: list(strategy, workers, chunk_size, bam_nthreads)
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' spec_grid <- expand_grid_specs(
#'   delta_grid = -1:1,
#'   Kr_grid = 1:3,
#'   Kb_grid = c(0L,1L),
#'   T_grid = c("O","S"),
#'   k_f_grid = c(6L,8L),
#'   alpha_state = c(0.25,0.35),
#'   k_w_grid = c(6L,8L),
#'   k_s_grid = c(0L),
#'   k_e_grid = c(0L,6L),
#'   k_n_grid = c(0L,6L),
#'   k_1_grid = c(4L,6L),
#'   k_2_grid = c(0L)
#' )

# --- from R/m2_spec_grid.R ---

tune_stage2_loso_spec_grid_parallel <- function(alignedD_prosp,
                                                template_df,
                                                spec_grid,
                                                ignD = NULL,
                                                seasons = NULL,
                                                k_t = 10L,
                                                w_early = 2,
                                                exclude_newseason_terms = TRUE,
                                                # parallel controls
                                                workers = 8L,
                                                strategy = c("auto","multisession","multicore"),
                                                chunk_size = 8L,
                                                # bam threads inside each worker (keep 1 if parallel)
                                                nthreads = 1L,
                                                cache_dir = tempdir(),
                                                verbose = TRUE) {
  
  .Deprecated("nested_loso_grid_search",
              msg = paste("tune_stage2_loso_spec_grid_parallel() is deprecated.",
                          "Use nested_loso_grid_search() from m2_nested_loso.R instead.",
                          "This function depends on undefined stack_stage2_joint_data()."))
  stop("tune_stage2_loso_spec_grid_parallel() is deprecated. Use nested_loso_grid_search() instead.")
  
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need data.table")
  if (!requireNamespace("mgcv", quietly = TRUE)) stop("Need mgcv")
  if (!requireNamespace("future", quietly = TRUE)) stop("Need future")
  if (!requireNamespace("future.apply", quietly = TRUE)) stop("Need future.apply")
  
  strategy <- match.arg(strategy)
  stopifnot(is.list(spec_grid), !is.null(spec_grid$grid))
  grid <- data.table::as.data.table(spec_grid$grid)
  
  all_seasons <- seasons %||% sort(unique(alignedD_prosp$season))
  if (length(all_seasons) < 3L) stop("Need >= 3 seasons for LOSO.")
  
  # ---- timing ----
  t_start <- Sys.time()
  pt_start <- proc.time()
  
  # ---- choose plan ----
  if (strategy == "auto") {
    strat <- if (.Platform$OS.type == "windows") "multisession" else "multicore"
  } else strat <- strategy
  
  old_plan <- future::plan()
  on.exit(future::plan(old_plan), add = TRUE)
  future::plan(strat, workers = as.integer(workers))
  
  if (isTRUE(verbose)) {
    message("[tune_stage2_loso_spec_grid_parallel] grid_rows=", nrow(grid),
            " | seasons=", length(all_seasons),
            " | k_t=", k_t, " w_early=", w_early,
            " | strategy=", strat, " workers=", workers,
            " | chunk_size=", chunk_size,
            " | bam nthreads=", nthreads)
    if (nthreads > 1L) message("NOTE: with parallel workers, prefer bam nthreads=1 to avoid oversubscription.")
  }
  
  # ---- save big objects to disk (tiny globals to workers) ----
  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
  f_dat  <- file.path(cache_dir, paste0("stage2_dat_",  Sys.getpid(), "_", as.integer(runif(1,1,1e9)), ".rds"))
  f_tmp  <- file.path(cache_dir, paste0("stage2_tmp_",  Sys.getpid(), "_", as.integer(runif(1,1,1e9)), ".rds"))
  f_ign  <- file.path(cache_dir, paste0("stage2_ign_",  Sys.getpid(), "_", as.integer(runif(1,1,1e9)), ".rds"))
  f_grid <- file.path(cache_dir, paste0("stage2_grid_", Sys.getpid(), "_", as.integer(runif(1,1,1e9)), ".rds"))
  
  saveRDS(alignedD_prosp, f_dat)
  saveRDS(template_df,    f_tmp)
  saveRDS(ignD,           f_ign)
  saveRDS(grid,           f_grid)
  
  on.exit(unlink(c(f_dat, f_tmp, f_ign, f_grid), force = TRUE), add = TRUE)
  
  # ---- chunk indices ----
  idx <- seq_len(nrow(grid))
  chunk_size <- as.integer(max(1L, chunk_size))
  chunks <- split(idx, ceiling(idx / chunk_size))
  
  # ---- scoring helper inside worker (no closures that capture big env) ----
  worker_chunk <- function(idxs, f_dat, f_tmp, f_ign, f_grid,
                           all_seasons, k_t, w_early, exclude_newseason_terms, nthreads) {
    
    library(data.table)
    library(mgcv)
    
    dat  <- readRDS(f_dat)
    tmp  <- readRDS(f_tmp)
    ign  <- readRDS(f_ign)
    grid <- data.table::as.data.table(readRDS(f_grid))
    
    out <- vector("list", length(idxs))
    
    for (j in seq_along(idxs)) {
      i <- idxs[j]
      row <- grid[i]
      
      # build spec from grid row
      sp <- stage2_make_spec(
        delta = row$delta,
        Kr    = row$Kr,
        Kb    = row$Kb,
        T     = row$T,
        k_f   = ifelse(is.na(row$k_f), 6L, row$k_f),
        alpha_state = row$alpha_state,
        
        k_w = row$k_w, k_s = row$k_s, k_e = row$k_e, k_n = row$k_n, k_1 = row$k_1, k_2 = row$k_2,
        bs_week = row$bs_week, bs_fs_marginal = row$bs_fs_marginal
      )
      
      # prep once per spec
      feat <- prep_stage2_m1_features(
        alignedD_prosp = dat,
        template_df    = tmp,
        spec           = sp,
        ignD           = ign
      )
      
      # LOSO folds
      fold_res <- lapply(all_seasons, function(s_out) {
        train_seasons <- setdiff(all_seasons, s_out)
        
        fit_mod <- train_stage2_joint_m1(
          feat = feat, spec = sp,
          seasons_keep = train_seasons,
          drop_future = TRUE,
          nthreads = nthreads,
          return_data = FALSE
        )$fit
        
        d_test <- stack_stage2_joint_data(
          feat = feat, spec = sp,
          seasons_keep = s_out,
          drop_future = TRUE
        )
        
        # align factor levels safely (avoid new levels)
        lev_lead   <- fit_mod$stage2_levels$lead
        lev_season <- fit_mod$stage2_levels$season
        lev_sh     <- fit_mod$stage2_levels$season_h
        
        d_test$lead   <- factor(as.character(d_test$lead), levels = lev_lead)
        d_test$season <- factor(as.character(d_test$season), levels = lev_season)
        if (anyNA(d_test$season)) d_test$season[is.na(d_test$season)] <- lev_season[1]
        
        d_test$season_h <- interaction(d_test$season, d_test$lead, drop = TRUE)
        d_test$season_h <- factor(d_test$season_h, levels = lev_sh)
        if (anyNA(d_test$season_h)) d_test$season_h[is.na(d_test$season_h)] <- lev_sh[1]
        
        ex <- if (isTRUE(exclude_newseason_terms)) sp$exclude_newseason else NULL
        # Frozen LOSO: always exclude s(season) — test season is NOT in training.
        ex <- unique(c(ex, "s(season)"))
        eta <- as.numeric(stats::predict(fit_mod, newdata = d_test, type = "link", exclude = ex))
        p   <- plogis(eta)
        
        # weights by TARGET week: (w+h) - ign_weekF
        t_target <- (d_test$weekF + d_test$lead_n) - d_test$ign_weekF
        w <- rep(1, length(t_target))
        w[is.finite(t_target) & t_target >= 0 & t_target <= as.integer(k_t)] <- as.numeric(w_early)
        
        y <- as.numeric(d_test$y_lead)
        N <- as.numeric(d_test$N_lead)
        p <- pmin(1 - 1e-12, pmax(1e-12, p))
        
        ok <- is.finite(y) & is.finite(N) & is.finite(p) & (N > 0) & is.finite(w)
        y <- y[ok]; N <- N[ok]; p <- p[ok]; w <- w[ok]
        
        ll <- stats::dbinom(y, size = N, prob = p, log = TRUE)
        nll <- -sum(w * ll)
        
        phat <- y / N
        se2  <- (p - phat)^2
        brier_num <- sum(w * se2)
        w_sum <- sum(w)
        
        data.table(
          spec_id = row$spec_id,
          season_out = as.character(s_out),
          n = length(p),
          w_sum = w_sum,
          nll = nll,
          mean_nll = nll / w_sum,
          brier = brier_num / w_sum,
          rmse_p = sqrt(brier_num / w_sum),
          brier_num = brier_num
        )
      })
      
      out[[j]] <- rbindlist(fold_res)
    }
    
    rbindlist(out, use.names = TRUE, fill = TRUE)
  }
  environment(worker_chunk) <- baseenv()
  
  # ---- run parallel over chunks ----
  res_chunks <- future.apply::future_lapply(
    chunks,
    worker_chunk,
    f_dat = f_dat, f_tmp = f_tmp, f_ign = f_ign, f_grid = f_grid,
    all_seasons = all_seasons,
    k_t = k_t, w_early = w_early,
    exclude_newseason_terms = exclude_newseason_terms,
    nthreads = as.integer(nthreads),
    future.seed = TRUE,
    future.packages = c("data.table", "mgcv")
  )
  
  by_season <- data.table::rbindlist(res_chunks, use.names = TRUE, fill = TRUE)
  
  by_spec <- by_season[, .(
    n_total = sum(n),
    w_total = sum(w_sum),
    nll = sum(nll),
    mean_nll = sum(nll) / sum(w_sum),
    brier = sum(brier_num) / sum(w_sum),
    rmse_p = sqrt(sum(brier_num) / sum(w_sum))
  ), by = spec_id][order(mean_nll)]
  
  by_spec_grid <- data.table::as.data.table(grid)[by_spec, on = "spec_id"]
  
  t_end <- Sys.time()
  pt_end <- proc.time()
  timing <- list(
    start = t_start,
    end = t_end,
    elapsed_sec = as.numeric(difftime(t_end, t_start, units = "secs")),
    cpu_sec = unname((pt_end - pt_start)[["user.self"]] + (pt_end - pt_start)[["sys.self"]])
  )
  
  list(
    by_season = by_season,
    by_spec = by_spec,
    by_spec_grid = by_spec_grid,
    best = by_spec[1],
    scoring = list(k_t = as.integer(k_t), w_early = as.numeric(w_early)),
    timing = timing,
    parallel = list(strategy = strat, workers = workers, chunk_size = chunk_size, bam_nthreads = nthreads)
  )
}

# ============================================================
# 6) plot_stage2_joint_fit_by_season()
# ============================================================

#' Plot Stage-2 fit vs observed by season (observed all weeks; fit post-ignition only)
#'
#' Black points: observed lead positivity for all observed target weeks in \code{feat_full}.
#' Red lines: fitted probabilities drawn only for weeks at/after ignition.
#'
#' @param out_m1 Output of \code{train_stage2_joint_m1(return_data=TRUE)}.
#' @param feat_full Full feature table from \code{prep_stage2_m1_features()} (used for pre-ignition points).
#' @param dat_raw Optional raw data with columns season/weekF/phase to compute a "true" ignition line.
#' @param ign_hat_df Optional df with columns season, iWeek_hat (dashed line).
#' @param exclude_season_re If TRUE, exclude only \code{s(season)} in prediction.
#' @param exclude_newseason_terms If TRUE, exclude \code{out_m1$spec$exclude_newseason} in prediction.
#' @param facet_by_lead If TRUE use \code{facet_grid(lead ~ season)} else \code{facet_wrap(~season)}.
#'
#' @return A ggplot object.
#' @export

# --- from R/m2_training.R ---

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

# --- from R/m2_training.R ---

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


# --- from R/m2_training.R ---

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

# --- from R/m2_training.R ---

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


# --- from R/m2_training.R ---

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

# --- from R/pipeline_bridge.R ---

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

  .Deprecated("run_prospective_pipeline",
              msg = paste("run_m0_m1_m2_weekly() is deprecated.",
                          "Use run_prospective_pipeline() from pipeline_runtime.R instead.",
                          "It supports both frozen-fit and weekly-refit modes."))

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
