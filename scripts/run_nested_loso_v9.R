#!/usr/bin/env Rscript
# ============================================================
# Nested LOSO M2 Grid Search — v9 (comprehensive parameter search)
#
# Key differences from v8:
#   - Searches ALL tunable hyperparameters (delta, k_s, k_w, lambda_w,
#     k_1, k_2 were fixed at 0 in v4-v8 — now varied).
#   - Season RE fix: weekly-refit predictions INCLUDE the test season's
#     random effect (the refit model estimates it), fixing the systematic
#     underestimation from excluding s(season) for known seasons.
#   - Grid design: ~2400 specs, focusing on parameters that were
#     previously unexplored while keeping grid tractable.
#
# Output: data/nested_loso_v9_phase2.rds (resumable)
#         data/nested_loso_v9_production.rds (final)
# ============================================================

cat("=== Nested LOSO M2 grid search (v9 — full parameter search) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(flualign)
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

wd <- getwd()
setwd(wd)
cat("Working dir:", wd, "\n")

# ---- 1. Data ----
n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
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

# ---- 2. M1 settings ----
M1 <- list(
  k_ref = 25L, ref_method = "fs", temperature = 0.25,
  rise_weight = 1.0, trough_weight = 0.1, peak_decay = 0.3,
  slope_weight = 0.5, slope_window = 4L,
  dynamic_temp = TRUE, dynamic_temp_pivot = 10L
)

# ---- 3. v9 comprehensive spec grid ----
# Design: vary ALL key hyperparameters that were fixed in v4-v8.
#
# Parameters and their roles:
#   delta    — template time-shift (weeks). 0 = aligned, negative = early.
#   Kr       — ramp length (ignition → full template). Larger = slower onset.
#   k_f      — basis dim for logit_f_eff smooth (M1 prediction).
#   k_e      — basis dim for z_ema smooth (EWMA of positivity).
#   alpha_state — EWMA decay rate for z_ema. Higher = more responsive.
#   k_1      — basis dim for d1_now (1st derivative) smooth.
#   k_2      — basis dim for d2_now (2nd derivative) smooth. 0 = disabled.
#   k_w      — basis dim for week smooth. 0 = disabled.
#   k_s      — basis dim for factor-smooth (season-specific trend). 0 = disabled.
#   lambda_w — Weibull recency weight for LOSO evaluation. 0 = equal weights.

grid_v9 <- tidyr::crossing(
  delta       = c(-1L, 0L, 1L),
  Kr          = c(1L, 2L, 3L),
  k_f         = c(3L, 5L, 7L),
  k_e         = c(2L, 4L),
  alpha_state = c(0.05, 0.10, 0.20),
  k_1         = c(0L, 4L),
  k_2         = c(0L),
  k_w         = c(0L, 6L),
  k_s         = c(0L, 4L),
  lambda_w    = c(0)
)

cat("Raw grid size:", nrow(grid_v9), "\n")

# Build spec objects
specs_v9 <- purrr::pmap(grid_v9, function(delta, Kr, k_f, k_e, alpha_state,
                                           k_1, k_2, k_w, k_s, lambda_w) {
  stage2_make_spec(
    delta       = delta,
    Kr          = Kr,
    T           = "S",
    k_f         = k_f,
    k_e         = k_e,
    k_1         = k_1,
    k_2         = k_2,
    k_w         = k_w,
    k_s         = k_s,
    alpha_state = alpha_state,
    lambda_w    = lambda_w,
    w_floor     = 0.05,
    anchorWeek  = 20L
  )
})
names(specs_v9) <- sprintf(
  "d%+d_Kr%d_kf%d_ke%d_a%.0f_k1%d_k2%d_kw%d_ks%d",
  grid_v9$delta, grid_v9$Kr, grid_v9$k_f, grid_v9$k_e,
  grid_v9$alpha_state * 100,
  grid_v9$k_1, grid_v9$k_2, grid_v9$k_w, grid_v9$k_s
)
cat("Full v9 grid:", length(specs_v9), "specs\n")

# ---- 4. Test seasons ----
test_seasons <- sort(setdiff(unique(allD$season), EXCLUDE_SEAS))
cat("Test seasons (", length(test_seasons), "):", paste(test_seasons, collapse = ", "), "\n\n")

# ---- 5. Parallelism ----
n_cores <- parallel::detectCores()
cat("Cores:", n_cores, "\n\n")

# ============================================================
# PHASE 1: Reuse v8 M1 cache (M0+M1 are unchanged)
# ============================================================
cat("=== PHASE 1: Loading M1 cache ===\n")

for (src in c(
  "data/nested_loso_v8_phase1.rds",
  "data/nested_loso_v5_phase1.rds",
  "data/nested_loso_v4_phase1.rds"
)) {
  if (file.exists(src)) {
    m1_cache <- readRDS(src)
    cat("Loaded Phase 1 from:", src, "—", length(m1_cache), "folds\n")
    break
  }
}

if (!exists("m1_cache")) {
  cat("No Phase 1 cache found — computing from scratch.\n")
  m1_cache <- list()
}

remaining_p1 <- setdiff(test_seasons, names(m1_cache))
if (length(remaining_p1) > 0) {
  cat("Computing", length(remaining_p1), "missing folds...\n")
  future::plan(future::multisession, workers = n_cores)
  for (test_s in remaining_p1) {
    cat(sprintf("[%s] Building fold + M1...\n", test_s))
    t0 <- proc.time()[["elapsed"]]
    fold <- nested_loso_build_fold(
      allD = allD, test_season = test_s, exclude_seasons = EXCLUDE_SEAS,
      k_ref = M1$k_ref, ref_method = M1$ref_method,
      manual_labels = manual_labels, verbose = FALSE
    )
    m1_train <- m1_walkforward_multi(
      allD = allD, ref = fold$ref, hyper = fold$hyper, params = params,
      seasons = fold$train_seasons, temperature = M1$temperature,
      rise_weight = M1$rise_weight, trough_weight = M1$trough_weight,
      peak_decay = M1$peak_decay, slope_weight = M1$slope_weight,
      slope_window = M1$slope_window, dynamic_temp = M1$dynamic_temp,
      dynamic_temp_pivot = M1$dynamic_temp_pivot, parallel = TRUE, verbose = FALSE
    )
    m1_test <- m1_walkforward_predictions(
      seasonD = allD[allD$season == test_s, ], ref = fold$ref, hyper = fold$hyper,
      params = params, temperature = M1$temperature, rise_weight = M1$rise_weight,
      trough_weight = M1$trough_weight, peak_decay = M1$peak_decay,
      slope_weight = M1$slope_weight, slope_window = M1$slope_window,
      dynamic_temp = M1$dynamic_temp, dynamic_temp_pivot = M1$dynamic_temp_pivot
    )
    m1_cache[[test_s]] <- list(fold = fold, m1_train = m1_train, m1_test = m1_test)
    cat(sprintf("  Done in %ds\n\n", round(proc.time()[["elapsed"]] - t0)))
  }
} else {
  cat("All folds cached — skipping Phase 1.\n\n")
}

# Save Phase 1 cache
p1_save <- "data/nested_loso_v9_phase1.rds"
if (!file.exists(p1_save)) {
  file.copy(src, p1_save)
  cat("Saved Phase 1 cache to", p1_save, "\n")
}

cat("Phase 1 complete:", length(m1_cache), "folds.\n\n")

# ============================================================
# PHASE 2: Evaluate all v9 specs (weekly refit + season RE fix)
# ============================================================
cat("=== PHASE 2: M2 grid search (v9 — all specs) ===\n")

new_spec_ids <- names(specs_v9)
cat("Total v9 specs to evaluate:", length(new_spec_ids), "\n\n")

phase2_ckpt <- "data/nested_loso_v9_phase2.rds"

if (file.exists(phase2_ckpt)) {
  cv_results_new <- readRDS(phase2_ckpt)
  todo_spec_ids  <- setdiff(new_spec_ids, names(cv_results_new))
  cat("Resuming:", length(cv_results_new), "done,", length(todo_spec_ids), "remaining\n\n")
} else {
  cv_results_new <- list()
  todo_spec_ids  <- new_spec_ids
}

if (length(todo_spec_ids) > 0) {
  cat("(", length(todo_spec_ids), "specs x", length(test_seasons), "folds)\n\n")
  batch_size   <- n_cores
  todo_batches <- split(todo_spec_ids, ceiling(seq_along(todo_spec_ids) / batch_size))
  future::plan(future::multisession, workers = n_cores)

  for (bi in seq_along(todo_batches)) {
    batch <- todo_batches[[bi]]
    cat(sprintf("Batch %d/%d (%d specs)...", bi, length(todo_batches), length(batch)))
    t0 <- proc.time()[["elapsed"]]

    batch_results <- furrr::future_map(
      stats::setNames(batch, batch),
      function(spec_id) {
        spec        <- specs_v9[[spec_id]]
        fold_scores <- vector("list", length(test_seasons))
        fold_preds  <- vector("list", length(test_seasons))
        names(fold_scores) <- names(fold_preds) <- test_seasons

        for (test_s in test_seasons) {
          fc <- m1_cache[[test_s]]

          eval_out <- tryCatch(
            nested_loso_m2_eval_weekly_refit(
              allD           = allD,
              fold           = fc$fold,
              m1_test_preds  = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0) fc$m1_test else NULL,
              spec           = spec,
              m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0) fc$m1_train else NULL,
              eval_window    = 12L,
              manual_labels  = manual_labels,
              flag_args      = flag_args,
              verbose        = FALSE
            ),
            error = function(e) NULL
          )
          if (is.null(eval_out)) {
            fold_scores[[test_s]] <- tibble::tibble(season = test_s, n = NA_integer_,
              mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_)
            fold_preds[[test_s]]  <- tibble::tibble()
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
    batch_nlls <- sapply(batch_results, function(r) round(mean(r$scores$mean_nll, na.rm = TRUE), 3))
    cat(sprintf(" %ds | nll range: %.3f–%.3f\n",
                elapsed, min(batch_nlls, na.rm = TRUE), max(batch_nlls, na.rm = TRUE)))
  }

  future::plan(future::sequential)
} else {
  cat("All specs already evaluated — skipping.\n\n")
}

# ============================================================
# Assemble v9 results and report
# ============================================================
cat("\n=== Assembling v9 results ===\n")

cv_results_all <- cv_results_new[names(specs_v9)]
cat("Total specs:", length(cv_results_all), "\n")

all_scores <- purrr::imap_dfr(cv_results_all, ~ dplyr::mutate(.x$scores, spec_id = .y))

summary_df <- all_scores |>
  dplyr::group_by(spec_id) |>
  dplyr::summarise(
    n_seasons = dplyr::n(),
    mean_nll  = mean(mean_nll, na.rm = TRUE),
    brier     = mean(brier,    na.rm = TRUE),
    rmse_p    = mean(rmse_p,   na.rm = TRUE),
    .groups   = "drop"
  ) |>
  dplyr::arrange(mean_nll)

best_id   <- summary_df$spec_id[1]
best_spec <- specs_v9[[best_id]]

cat("\n=== Top 10 specs by mean NLL ===\n")
print(utils::head(summary_df, 10), n = 10)
cat("\nBest spec:", best_id, "\n")
cat("  delta=", best_spec$delta, " Kr=", best_spec$Kr,
    " k_f=", best_spec$k_f, " k_e=", best_spec$k_e,
    " alpha=", best_spec$alpha_state,
    " k_1=", best_spec$k_1, " k_2=", best_spec$k_2,
    " k_w=", best_spec$k_w, " k_s=", best_spec$k_s, "\n")

results <- list(
  scores       = all_scores,
  summary      = summary_df,
  best_spec_id = best_id,
  best_spec    = best_spec,
  cv_results   = cv_results_all,
  grid         = grid_v9
)
saveRDS(results, "data/nested_loso_v9_production.rds")

cat("\nResults saved to data/nested_loso_v9_production.rds\n")
cat("End:", format(Sys.time()), "\n")
