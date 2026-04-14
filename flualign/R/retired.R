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

#' Retired: prepare Stage-2 M1 features
#'
#' Retired. Use \code{prep_stage2_joint()} from \code{m2_training.R} instead.
#' Calling this function stops with an error via \code{.Deprecated()}.
#'
#' @keywords internal
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

#' Retired: fit Stage-2 joint M1 model for a given spec
#'
#' Retired. Use \code{train_stage2_joint()} from \code{m2_training.R} instead.
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
#' @keywords internal
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

#' Retired: LOSO tuning over a spec grid with weighted scoring near ignition
#'
#' Retired. Use \code{nested_loso_grid_search()} from \code{m2_nested_loso.R}
#' instead. Calling this function stops with an error via \code{.Deprecated()}.
#'
#' @keywords internal
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



#' Retired: LOSO tuning over a Stage-2 spec grid (disk-backed parallel; Linux + Windows)
#'
#' Retired. Use \code{nested_loso_grid_search()} from \code{m2_nested_loso.R}
#' instead. Calling this function stops with an error via \code{.Deprecated()}.
#'
#' @keywords internal
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
# 6) tune_stage2_loso_specs()
# ============================================================

# --- from R/m2_training.R ---

#' Retired: LOSO spec comparison for Stage-2 models
#'
#' Retired. Use \code{nested_loso_grid_search()} from \code{m2_nested_loso.R}
#' instead. Evaluates a list of \code{stage2_make_spec()} specs via LOSO and
#' returns per-spec NLL/Brier/RMSE metrics.
#'
#' @keywords internal
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

#' Retired: tune Stage-2 over (delta,K,k_f,alpha_state) with a fixed model structure
#'
#' Retired. Use \code{nested_loso_grid_search()} from \code{m2_nested_loso.R}
#' instead. Calling this function stops with an error via \code{.Deprecated()}.
#'
#' @keywords internal
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

#' Retired: heatmap plot for Stage-2 LOSO tuning results
#'
#' Retired. Use \code{plot_nested_loso_scores()} from \code{m2_nested_loso.R}
#' or build a custom ggplot from the \code{by_spec_grid} table instead.
#'
#' @keywords internal
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


# --- from R/m2_training.R ---

#' Retired: bundle all trained components into a prospective forecasting kit
#'
#' Retired. Use \code{load_prospective_kit()} from \code{pipeline_runtime.R}
#' instead.
#'
#' @keywords internal
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

#' Retired: validate a prospective forecasting kit
#'
#' Retired. Use \code{load_prospective_kit()} from \code{pipeline_runtime.R}
#' instead, which validates structure on load.
#'
#' @keywords internal
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

#' Retired: run the full M0/M1/M2 weekly prospective pipeline
#'
#' Retired. Use \code{run_prospective_pipeline()} from
#' \code{pipeline_runtime.R} instead. Calling this function issues a
#' deprecation warning via \code{.Deprecated()}.
#'
#' @keywords internal
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


# =========================================================================
# Retired 2026-04-xx: dead code removed from active pipeline files
#
#   identifiability.R    -> check_scale_identifiability_old
#   m1_fit.R             -> fit_tau_delta_old
#   m1_peak_flags.R      -> flagPeak
#   m1_reference_loader.R -> load_refCurve
#   m1_reference_helpers.R -> make_reference_functions, set_reference,
#                             get_reference, fit_reference_gam
#   m1_loso.R            -> loso_alignment, tune_loso_k
#   m1_peak_distribution.R -> peak_week_distribution
#   m1_alignment_plots.R -> plot_alignment_evolution
#   m2_nested_loso.R     -> nested_loso_m2_eval, plot_nested_loso_scores
#   pipeline_bridge.R    -> loso_m1_m2_joint
# =========================================================================

# --- from R/identifiability.R ---
#' @export
check_scale_identifiability_old <- function(currentD,
                                        g_ref_fun,   # you pass g_ref_fun; we use g_ref_safe inside
                                        hyper,
                                        min_week    = 20,   # don't turn on scale too early
                                        min_range_p = 0.10, # 10 percentage-points variation in p_obs
                                        min_range_g = 0.50  # 0.5 on logit scale for template
) {
  # Use the same "safe" reference you already use elsewhere
  g_ref_safe <- function(u) g_ref_fun(pmin(pmax(u, 1), 52))
  
  dat <- currentD %>%
    dplyr::mutate(n = y + neg) %>%
    dplyr::filter(n > 0)
  
  t <- dat$newWeek
  y <- dat$y
  n <- dat$n
  
  # 1) observed positivity variation
  p_obs   <- y / n
  range_p <- diff(range(p_obs, na.rm = TRUE))
  last_wk <- max(t, na.rm = TRUE)
  
  # 2) τ-only alignment to get tau_hat (δ = 0, b = 1)
  tp <- tau_profile_se(
    currentD   = dat,
    g_ref      = g_ref_safe,
    allow_scale = FALSE,
    tau0       = 0,
    tau_bounds = hyper$TAU_BOUNDS
  )
  tau_hat <- tp$tau_hat
  
  # 3) template variation over aligned weeks
  u_aligned <- (t - tau_hat)          # delta = 0
  g_vals    <- g_ref_safe(u_aligned)
  range_g   <- diff(range(g_vals, na.rm = TRUE))
  
  # 4) rule-of-thumb decision
  allow_scale_rec <- (last_wk >= min_week) &&
    (range_p  > min_range_p) &&
    (range_g  > min_range_g)
  
  tibble::tibble(
    last_week        = last_wk,
    tau_hat          = tau_hat,
    range_p_obs      = range_p,
    range_g_template = range_g,
    allow_scale_rec  = allow_scale_rec
  )
}


# --- from R/m1_peak_flags.R ---
#' Flag whether the epidemic has passed its peak (real time)
#'
#' Uses only information up to each week (dynamic peak_so_far), and
#' checks whether there has been a sustained drop from that peak.
#'
#' @param df data frame for a single season, with at least:
#'   \itemize{
#'     \item newWeek: monotone-increasing epidemic week index
#'     \item p: positivity (if missing, y/(y+neg) will be computed)
#'   }
#' @param value_col name of the column to treat as positivity (default: "p";
#'   if NULL and p is absent, uses y/(y+neg)).
#' @param min_week minimum newWeek to start considering a "past-peak" flag.
#' @param max_week maximum newWeek to consider (Inf = no upper limit).
#' @param drop_frac required relative drop from the peak_so_far:
#'   flag when rel_drop >= drop_frac.
#' @param min_abs_drop required absolute drop from peak_so_far:
#'   flag when abs_drop >= min_abs_drop.
#' @param min_consec_below number of consecutive weeks that must satisfy
#'   the drop condition before declaring "past peak".
#'
#' @return A list with:
#'   \itemize{
#'     \item df: original data plus helper columns:
#'       \code{peak_so_far}, \code{abs_drop}, \code{rel_drop},
#'       \code{drop_cond}, \code{drop_streak}, \code{eligible},
#'       \code{past_peak_flag}
#'     \item flag_week: newWeek at which "past peak" is first flagged (NA if none)
#'     \item peak_week_so_far: newWeek of the global max within df
#'     \item peak_value_so_far: value at that peak
#'   }
#' @export
flagPeak <- function(df,
                     value_col       = NULL,
                     min_week        = 1L,
                     max_week        = Inf,
                     drop_frac       = 0.25,
                     min_abs_drop    = 0.05,
                     min_consec_below = 2L) {
  
  if (!"newWeek" %in% names(df)) {
    stop("df must contain 'newWeek'.")
  }
  
  # ---- choose value_col (p or y/(y+neg)) ----
  if (is.null(value_col)) {
    if ("p" %in% names(df)) {
      value_col <- "p"
    } else if (all(c("y", "neg") %in% names(df))) {
      df <- dplyr::mutate(df, p = .data$y / (.data$y + .data$neg))
      value_col <- "p"
    } else {
      stop("Need either column 'p' or columns 'y' and 'neg' to define positivity.")
    }
  }
  
  if (!value_col %in% names(df)) {
    stop("Column '", value_col, "' not found in df.")
  }
  
  # ---- sort by newWeek and work on a copy ----
  df <- df %>%
    dplyr::arrange(.data$newWeek)
  
  val <- df[[value_col]]
  
  # guard against all NA
  if (all(!is.finite(val))) {
    warning("All positivity values are NA/inf; cannot flag peak.")
    df$peak_so_far      <- NA_real_
    df$abs_drop         <- NA_real_
    df$rel_drop         <- NA_real_
    df$drop_cond        <- FALSE
    df$drop_streak      <- 0L
    df$eligible         <- FALSE
    df$past_peak_flag   <- FALSE
    return(list(
      df               = df,
      flag_week        = NA_integer_,
      peak_week_so_far = NA_integer_,
      peak_value_so_far = NA_real_
    ))
  }
  
  # ---- dynamic peak so far (only using data up to each week) ----
  peak_so_far <- cummax(val)
  
  abs_drop <- pmax(0, peak_so_far - val)
  rel_drop <- ifelse(peak_so_far > 0,
                     abs_drop / peak_so_far,
                     0)
  
  drop_cond <- (rel_drop >= drop_frac) | (abs_drop >= min_abs_drop)
  
  # eligible window in newWeek space
  eligible <- (df$newWeek >= min_week) &
    (df$newWeek <= max_week)
  
  drop_eff <- drop_cond & eligible
  
  # ---- run-length of consecutive TRUEs for drop_eff ----
  # no explicit loops; reset streak when drop_eff == FALSE
  drop_streak <- ave(
    drop_eff,
    cumsum(!drop_eff),
    FUN = function(x) ifelse(x, seq_along(x), 0L)
  )
  
  # first index where we meet the streak condition
  idx_flag <- which(drop_streak >= min_consec_below)[1L]
  
  flag_week <- if (length(idx_flag) == 0L) NA_integer_ else df$newWeek[idx_flag]
  
  # global peak (within df) for reporting
  peak_idx <- which.max(val)
  peak_week_so_far  <- df$newWeek[peak_idx]
  peak_value_so_far <- val[peak_idx]
  
  df$peak_so_far    <- peak_so_far
  df$abs_drop       <- abs_drop
  df$rel_drop       <- rel_drop
  df$drop_cond      <- drop_cond
  df$drop_streak    <- as.integer(drop_streak)
  df$eligible       <- eligible
  df$past_peak_flag <- !is.na(flag_week) & (df$newWeek >= flag_week)
  
  list(
    df                = df,
    flag_week         = flag_week,
    peak_week_so_far  = peak_week_so_far,
    peak_value_so_far = peak_value_so_far
  )
}


# --- from R/m1_reference_loader.R ---
#' Load all flualign example objects
#'
#' Loads all objects stored in the bundled ref_curve.RData file
#' into the specified environment (default: caller).
#'
#' @param envir environment to load into. Defaults to parent.frame().
#' @export
load_refCurve <- function(envir = parent.frame()) {
  f <- system.file("extdata", "ref_curve.RData", package = "flualign")
  if (f == "") stop("ref_curve.RData not found in flualign")
  load(f, envir = envir)
}

# --- from R/m1_peak_distribution.R ---
#' Peak week (newWeek) per season + suggested peak-rule parameters
#'
#' @param theD historical data with at least:
#'   season, newWeek, and either p or (y, neg).
#' @param value_col column to define the peak. If NULL, uses p if present,
#'   otherwise computes p = y/(y+neg).
#' @param k_for_drop integer: how many weeks after the peak to look at
#'   when estimating the typical drop (also used as suggested min_consec_below).
#' @param drop_prob quantile of the *relative* drop to use, e.g. 0.5 for median.
#' @param abs_drop_prob quantile of the *absolute* drop to use for min_abs_drop.
#' @param max_week_prob quantile of peak_newWeek to use for max_week (e.g. 0.95).
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{peaks}: tibble(season, peak_newWeek, peak_value)
#'     \item \code{suggested}: list with
#'       \itemize{
#'         \item \code{min_week}
#'         \item \code{max_week}
#'         \item \code{drop_frac}
#'         \item \code{min_abs_drop}
#'         \item \code{min_consec_below}
#'       }
#'   }
#' @export
peak_week_distribution <- function(theD,
                                   value_col     = NULL,
                                   k_for_drop    = 2L,
                                   drop_prob     = 0.5,
                                   abs_drop_prob = 0.5,
                                   max_week_prob = 0.95) {
  
  # --- choose value_col (p or y/(y+neg)) ---
  if (is.null(value_col)) {
    if ("p" %in% names(theD)) {
      value_col <- "p"
    } else if (all(c("y", "neg") %in% names(theD))) {
      theD <- dplyr::mutate(theD, p = .data$y / (.data$y + .data$neg))
      value_col <- "p"
    } else {
      stop("Need either column 'p' or columns 'y' and 'neg' to define a peak.")
    }
  }
  
  if (!all(c("season", "newWeek", value_col) %in% names(theD))) {
    stop("theD must contain 'season', 'newWeek' and ", value_col)
  }
  
  # --- 1) Peak per season ---
  peaks <- theD %>%
    dplyr::group_by(.data$season) %>%
    dplyr::filter(
      is.finite(.data[[value_col]]),
      is.finite(.data$newWeek)
    ) %>%
    dplyr::slice_max(
      order_by  = .data[[value_col]],
      with_ties = FALSE
    ) %>%
    dplyr::ungroup() %>%
    dplyr::transmute(
      season,
      peak_newWeek = .data$newWeek,
      peak_value   = .data[[value_col]]
    )
  
  # --- 2) Relative + absolute drop after k_for_drop weeks ---
  future_pts <- peaks %>%
    dplyr::mutate(
      newWeek_future = .data$peak_newWeek + as.integer(k_for_drop)
    )
  
  drop_df <- future_pts %>%
    dplyr::left_join(
      theD %>%
        dplyr::select(season, newWeek, !!rlang::sym(value_col)),
      by = c("season", "newWeek_future" = "newWeek")
    ) %>%
    dplyr::rename(value_future = !!rlang::sym(value_col)) %>%
    dplyr::filter(
      is.finite(.data$value_future),
      is.finite(.data$peak_value)
    ) %>%
    dplyr::mutate(
      abs_drop = .data$peak_value - .data$value_future,
      rel_drop = .data$abs_drop / .data$peak_value
    )
  
  if (nrow(drop_df) == 0L) {
    warning("No seasons have data ", k_for_drop,
            " weeks after peak; cannot estimate drop_frac or min_abs_drop.")
    drop_frac_hat   <- NA_real_
    abs_drop_hat    <- NA_real_
  } else {
    drop_frac_hat <- stats::quantile(
      drop_df$rel_drop,
      probs = drop_prob,
      na.rm = TRUE
    )
    abs_drop_hat  <- stats::quantile(
      drop_df$abs_drop,
      probs = abs_drop_prob,
      na.rm = TRUE
    )
  }
  
  # --- 3) max_week from historical peak distribution ---
  max_week_hat <- as.integer(
    stats::quantile(peaks$peak_newWeek,
                    probs = max_week_prob,
                    na.rm = TRUE)
  )
  

  
  list(
    peaks     = peaks,
    min_week         = min(peaks$peak_newWeek, na.rm = TRUE),
    max_week         = max_week_hat,
    drop_frac        = as.numeric(drop_frac_hat),
    min_abs_drop     = as.numeric(abs_drop_hat),
    min_consec_below = as.integer(k_for_drop)
  )
}


# --- from R/m1_alignment_plots.R ---
#' Plot multiple aligned curves (full season) as observation window grows
#'
#' @param currentSeason data frame with at least:
#'   newWeek, weekF, y, neg, date (date can be NA; will be derived).
#' @param season character like "2017-2018" (you already use this).
#' @param startWeek integer, starting week-of-year for the template season.
#' @param start_cut_week epidemiologic week (in `currentSeason$week`) at which
#'   you start re-fitting (e.g. 44).
#' @param g_ref_fun reference spline on link scale.
#' @param g_ref_mu_se function(u) returning list(mu, se) from GAM.
#' @param hyper list from learn_alignment_hyperparams().
#' @param ref_df data frame with reference curve, typically having
#'   `newWeek` and `p_gamm`.
#' @param allow_scale base setting passed to align_forecast_pipeline_dilate()
#'   if no override is triggered (can be TRUE/FALSE/NULL).
#' @param force_allow_scale_from_week epi week; from this week onward
#'   (in surveillance-week space) we FORCE allow_scale = TRUE for that cut.
#'   Before that, we use `allow_scale` as given (including NULL).
#' @param max_newWeek optional scalar (aligned newWeek). If non-NULL, do not
#'   fit cuts whose last observed newWeek exceeds this. Each fitted cut still
#'   forecasts out to the season end.
#' @param peak_newWeek optional scalar in newWeek space giving the (known)
#'   epidemic peak location. For cuts with last observed newWeek >= peak_newWeek,
#'   use a GAM tail (from `forecast_post_peak_gam`) for newWeek > cut, instead
#'   of continued alignment-based extrapolation.
#' @param k_smooth_post basis dimension for the post-peak GAM tail.
#' @param use_weights logical, passed to pipeline.
#' @param level CI level.
#'
#' @return plotly object with all curves; each cut has its own legend entry.
#' @export
plot_alignment_evolution <- function(currentSeason,
                                     season,
                                     startWeek,
                                     start_cut_week,
                                     g_ref_fun,
                                     g_ref_mu_se,
                                     hyper,
                                     ref_df,
                                     allow_scale = NULL,
                                     force_allow_scale_from_week = NULL,
                                     max_newWeek = 52,
                                     peak_newWeek = NULL,
                                     k_smooth_post = 8,
                                     use_weights = TRUE,
                                     level = 0.95) {
  
  # ---- Basic checks ----
  needed_cols <- c("newWeek", "week", "weekF", "y", "neg")
  missing <- setdiff(needed_cols, names(currentSeason))
  if (length(missing) > 0) {
    stop("currentSeason is missing columns: ",
         paste(missing, collapse = ", "))
  }
  
  # 1) translate start_cut_week (epi week-of-year) -> starting newWeek
  start_newWeek <- currentSeason %>%
    dplyr::filter(.data$week == !!start_cut_week) %>%
    dplyr::summarise(min_nw = min(.data$newWeek, na.rm = TRUE)) %>%
    dplyr::pull(.data$min_nw)
  
  if (!is.finite(start_newWeek)) {
    stop("start_cut_week = ", start_cut_week,
         " not found in currentSeason$week")
  }
  
  last_obs_newWeek <- max(currentSeason$newWeek, na.rm = TRUE)
  
  # apply max_newWeek limit for which cuts we FIT
  if (!is.null(max_newWeek)) {
    if (!is.numeric(max_newWeek) || length(max_newWeek) != 1L || !is.finite(max_newWeek)) {
      stop("max_newWeek must be a single finite numeric")
    }
    last_cut_newWeek <- min(last_obs_newWeek, max_newWeek)
  } else {
    last_cut_newWeek <- last_obs_newWeek
  }
  
  if (last_cut_newWeek < start_newWeek) {
    stop("max_newWeek < start_newWeek; no cuts to fit.")
  }
  
  # all cut points in "newWeek" space (truncated only for *fitting*)
  cut_newWeeks <- seq(from = start_newWeek, to = last_cut_newWeek, by = 1L)
  
  # map each newWeek cut to its surveillance week (currentSeason$week)
  cut_info <- tibble::tibble(cut_newWeek = cut_newWeeks) %>%
    dplyr::left_join(
      currentSeason %>%
        dplyr::select(newWeek, week) %>%
        dplyr::distinct(),
      by = c("cut_newWeek" = "newWeek")
    )
  
  # legend labels in *surveillance week* space
  cut_labels <- paste0("≤ week ", cut_info$week)
  
  start_year <- as.integer(substr(season, 1, 4))
  max_newWeek_season <- if (!is.null(max_newWeek)) as.integer(max_newWeek) else max(currentSeason$newWeek, na.rm = TRUE)

  
  # ---- helper: build xD from a res object ----
  build_xD <- function(res, season_label) {
    res$pred_df %>%
      dplyr::left_join(
        currentSeason %>%
          dplyr::select(date, newWeek = .data$weekF),
        by = "newWeek"
      ) %>%
      tibble::add_column(season = season_label) %>%
      dplyr::mutate(
        date       = as.Date(.data$date),
        start_year = start_year,
        nW_true    = n_weeks_in_start_year(start_year),
        week       = ((.data$newWeek + startWeek - 2L) %% .data$nW_true) + 1L,
        mmwr_year  = ifelse(.data$week >= 35L, start_year, start_year + 1L),
        Rdate      = MMWRweek::MMWRweek2Date(.data$mmwr_year, .data$week, 1L),
        date       = as.Date(ifelse(is.na(.data$date), .data$Rdate, .data$date))
      ) %>%
      dplyr::left_join(ref_df, by = "newWeek")
  }
  
  # ---- Optional: global post-peak GAM tail (used only if peak_newWeek not NULL) ----
  xD_post_template <- NULL
  if (!is.null(peak_newWeek)) {
    post_gam_res <- flualign::forecast_post_peak_gam(
      currentSeason = currentSeason,
      g_ref_fun     = g_ref_fun,
      max_newWeek   = max_newWeek_season,
      k_smooth      = k_smooth_post,
      use_weights   = use_weights,
      level         = level
    )
    xD_post_template <- build_xD(post_gam_res, season_label = season)
  }
  
  # ---- 2) loop over cuts, refit, build xD for each ----
  all_xD <- purrr::map2_dfr(
    cut_newWeeks,
    cut_labels,
    function(cn, lab) {
      
      # data up to this cut
      currentD_cut <- currentSeason %>%
        dplyr::filter(.data$newWeek <= cn) %>%
        dplyr::select(.data$newWeek, .data$y, .data$neg)
      
      # epi-week of the last observation in this cut (surveillance-week scale)
      epi_last <- currentSeason %>%
        dplyr::filter(.data$newWeek == cn) %>%
        dplyr::summarise(w = max(.data$week, na.rm = TRUE)) %>%
        dplyr::pull(.data$w)
      
      # decide allow_scale for THIS cut:
      allow_scale_cut <-
        if (!is.null(force_allow_scale_from_week) &&
            is.finite(epi_last) &&
            epi_last >= force_allow_scale_from_week) {
          TRUE
        } else {
          allow_scale   # TRUE/FALSE/NULL
        }
      
      # alignment-based fit for this cut (full-season prediction)
      res_align <- align_forecast_pipeline_dilate(
        currentD    = currentD_cut,
        g_ref_fun   = g_ref_fun,
        g_ref_mu_se = g_ref_mu_se,
        hyper       = hyper,
        allow_scale = allow_scale_cut,
        use_weights = use_weights,
        level       = level
      )
      
      xD_align <- build_xD(res_align, season_label = season)
      
      # If no peak_newWeek provided OR this cut is before peak -> pure alignment
      if (is.null(peak_newWeek) || cn < peak_newWeek || is.null(xD_post_template)) {
        return(
          xD_align %>%
            dplyr::mutate(cut_label = lab)
        )
      }
      
      # Otherwise: peak has (in truth) occurred already, so:
      # - use alignment up to the cut newWeek
      # - use GAM tail (from xD_post_template) after the cut
      
      x_pre <- xD_align %>%
        dplyr::filter(.data$newWeek <= cn)
      
      x_tail <- xD_post_template %>%
        dplyr::filter(.data$newWeek > cn) %>%
        dplyr::mutate(
          # for this hypothetical cut, everything after cn is "forecast"
          kind = "forecast"
        )
      
      dplyr::bind_rows(x_pre, x_tail) %>%
        dplyr::arrange(.data$newWeek) %>%
        dplyr::mutate(cut_label = lab)
    }
  )
  
  # ---- 3) single ggplot with many curves (each full season curve) ----
  p <- ggplot2::ggplot(all_xD, ggplot2::aes(x = .data$date, y = .data$p_hat)) +
    ggplot2::geom_ribbon(
      ggplot2::aes(
        ymin   = .data$p_lo,
        ymax   = .data$p_hi,
        fill   = .data$cut_label,
        group  = .data$cut_label
      ),
      alpha = 0.15,
      colour = NA
    ) +
    ggplot2::geom_line(
      ggplot2::aes(
        colour = .data$cut_label,
        group  = .data$cut_label
      ),
      linewidth = 0.7
    ) +
    ggplot2::geom_point(
      data = all_xD %>% dplyr::filter(.data$kind == "observed"),
      ggplot2::aes(x = .data$date, y = .data$p_hat),
      inherit.aes = FALSE,
      colour = "black",
      size = 1.5
    ) +
    ggplot2::geom_line(
      ggplot2::aes(y = .data$p_gamm),
      colour = "steelblue",
      linewidth = 0.9,
      inherit.aes = TRUE
    ) +
    ggplot2::scale_x_date(
      breaks = all_xD$date,
      labels = all_xD$week
    ) +
    ggplot2::ylab("Percentage Positivity") +
    ggplot2::xlab("Surveillance Week") +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(
        angle = 90, vjust = 0.5, hjust = 1
      )
    ) +
    ggplot2::labs(
      colour = "Cut at",
      fill   = "Cut at",
      title  = paste0("Alignment evolution for ", season),
      subtitle = paste0(
        "Curves re-fitted from week ", start_cut_week,
        " to ", max(currentSeason$week, na.rm = TRUE),
        if (!is.null(max_newWeek))
          paste0("; last alignment cut at newWeek ", last_cut_newWeek)
        else "",
        if (!is.null(peak_newWeek))
          paste0("; post-peak tail from GAM (peak newWeek ≈ ", peak_newWeek, ")")
        else ""
      )
    )
  
  p_multi <- plotly::ggplotly(
    p,
    tooltip = c("cut_label", "date", "week", "p_hat", "p_lo", "p_hi", "kind")
  )
  
  # clean legend names (remove "(...,1)" junk from ggplotly)
  for (i in seq_along(p_multi$x$data)) {
    nm <- p_multi$x$data[[i]]$name
    if (!is.null(nm) && nzchar(nm)) {
      nm_clean <- sub("^\\(([^,]+),.*\\)$", "\\1", nm)
      p_multi$x$data[[i]]$name <- nm_clean
    }
  }
  
  p_multi
}


# --- from R/m1_fit.R (fit_tau_delta_old) ---
#' @return A list with \code{tau}, \code{a}, \code{b}, \code{delta},
#'   \code{allow_scale}, \code{delta_on}, \code{value}, \code{status}, and
#'   \code{predict_prob}.
#' @keywords internal
fit_tau_delta_old <- function(currentD, g_ref_fun,
                          tau_bounds, delta_bounds,
                          allow_scale = NULL,
                          week_threshold_delta,
                          lam_delta,
                          use_weights = TRUE) {

  t <- currentD$newWeek; y <- currentD$y; n <- currentD$y + currentD$neg
  w <- if (use_weights) n else rep(1, length(n))

  if (is.null(allow_scale)) allow_scale <- max(t, na.rm = TRUE) >= 28
  delta_on <- max(t, na.rm = TRUE) >= week_threshold_delta

  g0   <- g_ref_safe(t)
  ok   <- is.finite(g0) & n > 0
  t0   <- t[ok]; y0 <- y[ok]; n0 <- n[ok]; w0 <- w[ok]; g0 <- g0[ok]

  if (allow_scale) {
    fit0 <- try(glm(cbind(y0, n0 - y0) ~ g0, family = binomial(), weights = w0), silent = TRUE)
    if (inherits(fit0, "try-error")) { a0 <- qlogis(pmax(mean(y0/n0), 1e-6)); b0 <- 1 } else {
      a0 <- unname(coef(fit0)[1]); b0 <- unname(coef(fit0)[2])
    }
  } else {
    fit0 <- try(glm(cbind(y0, n0 - y0) ~ 1 + offset(g0), family = binomial(), weights = w0), silent = TRUE)
    a0 <- if (inherits(fit0, "try-error")) qlogis(pmax(mean(y0/n0), 1e-6)) else unname(coef(fit0)[1])
    b0 <- 1
  }

  tau0 <- median(c(0, tau_bounds[1] + 1e-3, tau_bounds[2] - 1e-3))
  del0 <- if (delta_on) median(c(0, delta_bounds[1] + 1e-4, delta_bounds[2] - 1e-4)) else 0
  a0   <- median(c(a0, -10, 10))
  b0   <- if (allow_scale) median(c(b0, 0.2, 5.0)) else 1

  if (allow_scale && delta_on) {
    x0 <- c(tau0, a0, b0, del0)
    lb <- c(tau_bounds[1], -10, 0.2, delta_bounds[1])
    ub <- c(tau_bounds[2],  10, 5.0,  delta_bounds[2])
  } else if (allow_scale && !delta_on) {
    x0 <- c(tau0, a0, b0, 0)
    lb <- c(tau_bounds[1], -10, 0.2, 0)
    ub <- c(tau_bounds[2],  10, 5.0,  0)
  } else if (!allow_scale && delta_on) {
    x0 <- c(tau0, a0, del0)
    lb <- c(tau_bounds[1], -10, delta_bounds[1])
    ub <- c(tau_bounds[2],  10, delta_bounds[2])
  } else {
    x0 <- c(tau0, a0, 0)
    lb <- c(tau_bounds[1], -10, 0)
    ub <- c(tau_bounds[2],  10, 0)
  }

  obj <- function(par) safe_obj(par, t, y, n, gfun = g_ref_safe,
                                allow_scale = allow_scale, lam = lam_delta, w = w)

  if (!is.finite(obj(x0))) {
    for (sc in c(0, 0.25, 0.5, 1)) {
      x_try <- x0
      x_try[1] <- median(c(x0[1] + sc, tau_bounds[1] + 1e-3, tau_bounds[2] - 1e-3))
      if (is.finite(obj(x_try))) { x0 <- x_try; break }
    }
  }

  opt <- nloptr::sbplx(x0 = x0, fn = obj, lower = lb, upper = ub,
                       control = list(xtol_rel = 1e-7, maxeval = 3000))

  par <- opt$par
  tau_hat <- par[1]; a_hat <- par[2]
  if (allow_scale) { b_hat <- par[3]; del_hat <- par[4] } else { b_hat <- 1; del_hat <- par[3] }

  predict_prob <- function(tt) {
    u <- (tt - tau_hat) / (1 + del_hat)
    plogis(a_hat + b_hat * g_ref_safe(u))
  }

  list(
    tau = tau_hat, a = a_hat, b = b_hat, delta = del_hat,
    allow_scale = allow_scale, delta_on = delta_on,
    value = opt$value, status = opt$convergence,
    predict_prob = predict_prob,
    t = t, y = y, n = n, w = w, g_ref_fun = g_ref_safe
  )
}



# --- from R/m1_reference_helpers.R (make_reference_functions, set_reference, get_reference, fit_reference_gam) ---
#' Create closures for reference link-scale mean g(u) and se{g(u)}
#' @param gam_obj fitted GAM (e.g., gam_fit$gam) on binomial link scale
#' @param grid data.frame with column newWeek over support (e.g., 1:52)
#' @return list(g_ref_fun, g_ref_safe, g_ref_mu_se)
make_reference_functions <- function(gam_obj, grid) {
  stopifnot("newWeek" %in% names(grid))
  # smoother (link scale) for integer weeks
  eta_hat <- drop(predict(gam_obj, newdata = grid, type = "link", se.fit = FALSE))
  spl <- splinefun(grid$newWeek, eta_hat, method = "natural")
  g_ref_fun <- function(u) spl(u)
  g_ref_safe <- function(u) {
    u2 <- pmax(pmin(u, max(grid$newWeek)), min(grid$newWeek))
    spl(u2)
  }
  g_ref_mu_se <- function(u) {
    nd <- data.frame(newWeek = u)
    pr <- predict(gam_obj, newdata = nd, type = "link", se.fit = TRUE)
    list(mu = drop(pr$fit), se = drop(pr$se.fit))
  }
  list(g_ref_fun = g_ref_fun, g_ref_safe = g_ref_safe, g_ref_mu_se = g_ref_mu_se)
}

#' Set reference closures globally for convenience
set_reference <- function(gam_obj, grid) {
  fns <- make_reference_functions(gam_obj, grid)
  .flualign_ref_env$g_ref_fun   <- fns$g_ref_fun
  .flualign_ref_env$g_ref_safe  <- fns$g_ref_safe
  .flualign_ref_env$g_ref_mu_se <- fns$g_ref_mu_se
  invisible(TRUE)
}

#' Get the current reference closures
get_reference <- function() {
  list(
    g_ref_fun   = get("g_ref_fun",   envir = .flualign_ref_env, inherits = FALSE),
    g_ref_safe  = get("g_ref_safe",  envir = .flualign_ref_env, inherits = FALSE),
    g_ref_mu_se = get("g_ref_mu_se", envir = .flualign_ref_env, inherits = FALSE)
  )
}

# Convenience: fit GAM and set reference in one step
#' Fit reference GAM and set closures
#' @param df data.frame(season, newWeek, y, neg)
#' @param k basis dimension for s(newWeek)
fit_reference_gam <- function(df, k = 12) {
  stopifnot(all(c("newWeek","y","neg","season") %in% names(df)))
  fm <- gamm4::gamm4(cbind(y, neg) ~ s(newWeek, k = k),
                      random = ~(1|season), data = df,
                      family = binomial(), method = "REML")
  grid <- data.frame(newWeek = sort(unique(df$newWeek)))
  set_reference(fm$gam, grid)
  invisible(fm)
}


# --- from R/m1_loso.R (loso_alignment) ---
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


# --- from R/m1_loso.R (tune_loso_k) ---
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


# --- from R/m2_nested_loso.R (nested_loso_m2_eval) ---


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

  # Frozen LOSO: test season is NOT in training data — exclude s(season).
  ex_terms_with_season <- unique(c(ex_terms, "s(season)"))

  p_hat <- as.numeric(stats::predict(fit_obj, newdata = d_test,
                                     type = "response", exclude = ex_terms_with_season))
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


# --- from R/m2_nested_loso.R (plot_nested_loso_scores) ---
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


# --- from R/pipeline_bridge.R (loso_m1_m2_joint) ---

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

    # --- Step 3-4: Train M2 with M1 predictions as template ---
    if (!"N" %in% names(aligned_train))
      aligned_train$N <- aligned_train$y + aligned_train$neg
    if (isTRUE(verbose)) message("  Step 3-4: Training M2 with M1-stacked template")

    m2_fit <- tryCatch(
      train_stage2_joint(
        dat         = aligned_train,
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
    if (!"N" %in% names(aligned_test))
      aligned_test$N <- aligned_test$y + aligned_test$neg

    # Build M2 test data with M1 test predictions
    d_test <- tryCatch(
      prep_stage2_joint(
        dat           = aligned_test,
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

    # Frozen LOSO: test season is NOT in training data — exclude s(season).
    ex_with_season <- unique(c(ex, "s(season)"))
    p_hat <- as.numeric(stats::predict(fit_obj, newdata = d_test, type = "response", exclude = ex_with_season))
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

