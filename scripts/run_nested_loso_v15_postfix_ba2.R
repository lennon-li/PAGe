#!/usr/bin/env Rscript
# ============================================================
# Nested LOSO M2 Grid Search — v15-postfix boundary probe 2 — bias_alpha
#
# v15-postfix boundary probe 2 — bias_alpha ∈ {0.9, 0.95, 1.0}, α=1.0 is the ceiling
#
# Context:
#   boundary extension (ba) found best at bias_alpha upper boundary (0.9).
#   This script probes up to the natural ceiling α=1.0 (full replacement, no EMA).
#
# Grid: minimal focused probe — pinned best spec, sweep bias_alpha only
#   delta=0, Kr=1, k_f=5, k_e=2, alpha_state=0.35,
#   k_r=0, k_de=0, k_sp=2, bias_alpha ∈ {0.9, 0.95, 1.0}, bias_beta=0
#   Total: 3 specs × 10 folds = 30 evaluations
#
# Reuses M1 phase-1 cache: data/fresh_nested_loso_v15_phase1.rds
#
# Output: data/nested_loso_v15_postfix_ba2_production.rds (final)
#         data/nested_loso_v15_postfix_ba2_phase2_ckpt.rds (resumable checkpoint)
# ============================================================

cat("=== v15-postfix boundary probe 2 — bias_alpha ∈ {0.9, 0.95, 1.0}, α=1.0 is the ceiling ===\n")
cat("Start:", format(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(PAGe)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(furrr)
  library(future)
  library(mgcv)
  library(MMWRweek)
  library(data.table)
})

for (f in c(
  "R/utils.R",
  "R/m0_retro.R", "R/flagIgnition.R",
  "R/m1_reference.R", "R/m1_reference_helpers.R",
  "R/m1_multi_template.R",
  "R/m2_spec_grid.R", "R/m2_training.R", "R/m2_nested_loso.R",
  "R/pipeline_bridge.R", "R/pipeline_runtime_helpers.R"
)) source(f)

future::plan(future::multicore, workers = 11L)
cat("Workers: 11\n\n")

# ---- 1. Data ----
n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
}

allD <- read.csv("data/flu_testing_data.csv") |>
  dplyr::select(
    season, week, year,
    start_year = seasonstart,
    date       = week_start_date,
    y          = pos_flua,
    N          = test_flu
  ) |>
  dplyr::mutate(
    neg     = N - y,
    date    = as.Date(date),
    nW_true = n_weeks_in_start_year(start_year),
    weekF   = ((week - 27L) %% nW_true) + 1L,
    p       = y / N
  ) |>
  dplyr::filter(!season %in% c("2011-12", "2020-21", "2021-22", "2025-26"))

params        <- readRDS("data/stage1_tuning.rds")$best_params
manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)
EXCLUDE_SEAS <- "2015-16"
flag_args <- list(
  p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L,
  min_window = 10L, w_min = 21L, w_max = 21L, d2_relax = -0.01
)

# ---- 2. M1 settings (LOCKED spec from v5-v7 LOSO grid, MAE=1.275) ----
M1 <- list(
  k_ref = 25L, ref_method = "fs", temperature = 0.25,
  rise_weight = 1.0, trough_weight = 0.1, peak_decay = 0.3,
  slope_weight = 8.0,   # LOCKED: interior optimum over {0 ... 30}
  slope_window = 6L,    # LOCKED: optimal window (4,6,8,10,12 tested)
  dynamic_temp = FALSE, dynamic_temp_pivot = 10L
)

test_seasons <- sort(setdiff(unique(allD$season), EXCLUDE_SEAS))
cat("Test seasons (", length(test_seasons), "):", paste(test_seasons, collapse = ", "), "\n\n")

# ---- 3. Boundary probe 2 grid: bias_alpha ∈ {0.9, 0.95, 1.0} ----
grid_v15_ba2 <- tidyr::crossing(
  delta        = 0,
  Kr           = 1L,
  k_f          = 5L,
  k_e          = 2L,
  alpha_state  = 0.35,
  k_r          = 0L,
  k_de         = 0L,
  k_sp         = 2L,
  bias_alpha   = c(0.9, 0.95, 1.0),
  bias_beta    = 0
)

cat("Boundary probe 2 grid:", nrow(grid_v15_ba2), "specs\n")

specs_v15_ba2 <- purrr::pmap(grid_v15_ba2, function(delta, Kr, k_f, k_e, alpha_state,
                                                     k_r, k_de, k_sp, bias_alpha, bias_beta) {
  stage2_make_spec(
    delta = delta, Kr = Kr, T = "S",
    k_f = k_f, k_e = k_e, alpha_state = alpha_state,
    k_r = k_r, k_de = k_de, k_sp = k_sp,
    k_n = 0L, k_w = 0L, k_s = 0L,
    lambda_w = 0, w_floor = 0.05,
    bias_alpha = bias_alpha,
    bias_beta  = bias_beta
  )
})
names(specs_v15_ba2) <- paste0(
  "d+", grid_v15_ba2$delta,
  "_Kr", grid_v15_ba2$Kr,
  "_kf", grid_v15_ba2$k_f,
  "_ke", grid_v15_ba2$k_e,
  "_as", grid_v15_ba2$alpha_state,
  "_kr", grid_v15_ba2$k_r,
  "_kde", grid_v15_ba2$k_de,
  "_ksp", grid_v15_ba2$k_sp,
  "_ba", grid_v15_ba2$bias_alpha,
  "_bb", grid_v15_ba2$bias_beta
)

cat("Grid size:", length(specs_v15_ba2), "specs\n\n")

# ============================================================
# PHASE 1: Reuse M1 cache from fresh_nested_loso_v15_phase1.rds
# M1 walk-forward already uses prospective ignition; not affected by B1-B4 fixes.
# ============================================================
cat("=== PHASE 1: Loading M1 phase-1 cache ===\n")
cat("  Reusing M1 phase-1 cache (not affected by B1-B4 fixes)\n")
cat("  Source: data/fresh_nested_loso_v15_phase1.rds\n\n")

m1_cache_path <- "data/fresh_nested_loso_v15_phase1.rds"
if (!file.exists(m1_cache_path)) {
  stop("M1 phase-1 cache not found at: ", m1_cache_path,
       "\nBuild it first with scripts/fresh_run/04_m2_loso.R (Phase 1 only).")
}

m1_cache <- readRDS(m1_cache_path)
cat("Phase 1 cache loaded:", length(m1_cache), "folds.\n\n")

# ============================================================
# PHASE 2: Evaluate all boundary-extension specs (frozen GAM + Holt + online RE)
# ============================================================
cat("=== PHASE 2: M2 grid search (v15-postfix boundary probe 2 — bias_alpha ceiling sweep) ===\n")

new_spec_ids <- names(specs_v15_ba2)
cat("Total boundary probe 2 specs to evaluate:", length(new_spec_ids), "\n\n")

phase2_ckpt <- "data/nested_loso_v15_postfix_ba2_phase2_ckpt.rds"

if (file.exists(phase2_ckpt)) {
  cv_results_new <- readRDS(phase2_ckpt)
  todo_spec_ids  <- setdiff(new_spec_ids, names(cv_results_new))
  cat("Resuming:", length(cv_results_new), "done,", length(todo_spec_ids), "remaining\n\n")
} else {
  cv_results_new <- list()
  todo_spec_ids  <- new_spec_ids
}

n_cores <- 11L

if (length(todo_spec_ids) > 0) {
  cat("(", length(todo_spec_ids), "specs x", length(test_seasons), "folds)\n\n")
  batch_size   <- n_cores
  todo_batches <- split(todo_spec_ids, ceiling(seq_along(todo_spec_ids) / batch_size))

  for (bi in seq_along(todo_batches)) {
    batch <- todo_batches[[bi]]
    cat(sprintf("Batch %d/%d (%d specs)...", bi, length(todo_batches), length(batch)))
    t0 <- proc.time()[["elapsed"]]

    batch_results <- furrr::future_map(
      stats::setNames(batch, batch),
      function(spec_id) {
        spec        <- specs_v15_ba2[[spec_id]]
        fold_scores <- vector("list", length(test_seasons))
        fold_preds  <- vector("list", length(test_seasons))
        names(fold_scores) <- names(fold_preds) <- test_seasons

        for (test_s in test_seasons) {
          fc <- m1_cache[[test_s]]

          m2_fit <- tryCatch(
            nested_loso_m2_train(
              fold           = fc$fold,
              m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0) fc$m1_train else NULL,
              spec           = spec,
              method         = "REML",
              verbose        = FALSE
            ),
            error = function(e) NULL
          )

          # B4 fix: per-fold training labels only (exclude held-out season)
          manual_labels_train_fold <- manual_labels[setdiff(names(manual_labels), test_s)]
          eval_out <- tryCatch(
            nested_loso_m2_eval_frozen_bias(
              allD                = allD,
              fold                = fc$fold,
              m2_fit              = m2_fit,
              m1_test_preds       = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0) fc$m1_test else NULL,
              spec                = spec,
              eval_window         = 12L,
              bias_alpha          = spec$bias_alpha,  # from grid row
              manual_labels_train = manual_labels_train_fold,
              manual_labels_test  = NULL,
              flag_args           = flag_args,
              verbose             = FALSE
            ),
            error = function(e) NULL
          )

          if (is.null(eval_out)) {
            fold_scores[[test_s]] <- tibble::tibble(
              season = test_s, n = NA_integer_,
              mean_nll = NA_real_, bernoulli_nll = NA_real_,
              brier = NA_real_, rmse_p = NA_real_
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

    cv_results_new <- c(cv_results_new, batch_results)
    saveRDS(cv_results_new, phase2_ckpt)

    elapsed    <- round(proc.time()[["elapsed"]] - t0)
    batch_nlls <- sapply(batch_results, function(r)
      round(mean(r$scores$bernoulli_nll, na.rm = TRUE), 4))
    cat(sprintf(" %ds | bernoulli_nll range: %.4f-%.4f\n",
                elapsed, min(batch_nlls, na.rm = TRUE), max(batch_nlls, na.rm = TRUE)))
  }

  future::plan(future::sequential)
} else {
  cat("All specs already evaluated -- skipping.\n\n")
}

# ============================================================
# Assemble boundary-extension results and report
# ============================================================
cat("\n=== Assembling boundary probe 2 results ===\n")

cv_results_all <- cv_results_new[names(specs_v15_ba2)]
cat("Total specs:", length(cv_results_all), "\n")

all_scores <- purrr::imap_dfr(cv_results_all, ~ dplyr::mutate(.x$scores, spec_id = .y))

summary_df <- all_scores |>
  dplyr::group_by(spec_id) |>
  dplyr::summarise(
    n_seasons     = dplyr::n(),
    bernoulli_nll = mean(bernoulli_nll, na.rm = TRUE),
    mean_nll      = mean(mean_nll,      na.rm = TRUE),
    brier         = mean(brier,         na.rm = TRUE),
    rmse_p        = mean(rmse_p,        na.rm = TRUE),
    .groups       = "drop"
  ) |>
  dplyr::arrange(bernoulli_nll)

best_id   <- summary_df$spec_id[1]
best_spec <- specs_v15_ba2[[best_id]]

cat("\n=== All specs by Bernoulli NLL ===\n")
print(utils::head(summary_df[, c("spec_id","bernoulli_nll","mean_nll","brier","rmse_p")], 20), n = 20)
cat("\nBest spec:", best_id, "\n")
cat("Best spec params:\n")
print(unlist(best_spec[c("k_f", "k_e", "alpha_state", "k_r", "k_de", "k_sp", "bias_alpha", "bias_beta")]))

# ---- Boundary checks ----
cat("\n=== alpha_state boundary check ===\n")
as_summary <- summary_df |>
  dplyr::mutate(alpha_state = as.numeric(sub("^.*_as([0-9.]+)_.*$", "\\1", spec_id))) |>
  dplyr::group_by(alpha_state) |>
  dplyr::summarise(min_bern_nll = min(bernoulli_nll, na.rm = TRUE), .groups = "drop") |>
  dplyr::arrange(alpha_state)
print(as_summary)

cat("\n=== bias_alpha boundary check ===\n")
ba_summary <- summary_df |>
  dplyr::mutate(bias_alpha = as.numeric(sub("^.*_ba([0-9.]+)_bb.*$", "\\1", spec_id))) |>
  dplyr::group_by(bias_alpha) |>
  dplyr::summarise(min_bern_nll = min(bernoulli_nll, na.rm = TRUE), .groups = "drop") |>
  dplyr::arrange(bias_alpha)
print(ba_summary)

# ---- Per-season NLL for best spec ----
cat("\n=== Per-season NLL for best spec ===\n")
best_season_nll <- all_scores |>
  dplyr::filter(spec_id == best_id) |>
  dplyr::select(season, bernoulli_nll, n) |>
  dplyr::arrange(season)
print(best_season_nll)

# ---- Boundary flag ----
best_ba <- as.numeric(sub("^.*_ba([0-9.]+)_bb.*$", "\\1", best_id))
cat("\n=== Boundary status ===\n")
if (best_ba >= 1.0) {
  cat("FLAG: best bias_alpha =", best_ba, "— at natural ceiling (1.0, full replacement). α=1.0 is optimal or flat plateau.\n")
} else if (best_ba <= 0.9) {
  cat("FLAG: best bias_alpha =", best_ba, "— at lower boundary of this probe (0.9). Check previous ba results.\n")
} else {
  cat("INTERIOR: best bias_alpha =", best_ba, "— interior optimum found within {0.9, 0.95, 1.0}.\n")
}

results <- list(
  scores       = all_scores,
  summary      = summary_df,
  best_spec_id = best_id,
  best_spec    = best_spec,
  cv_results   = cv_results_all,
  grid         = grid_v15_ba2
)
saveRDS(results, "data/nested_loso_v15_postfix_ba2_production.rds")

cat("\nResults saved to data/nested_loso_v15_postfix_ba2_production.rds\n")
cat("End:", format(Sys.time()), "\n")
