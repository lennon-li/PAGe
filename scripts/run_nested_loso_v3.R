#!/usr/bin/env Rscript
# ============================================================
# Nested LOSO M2 Grid Search — v3 (expanded grid)
#
# Based on v2 results:
#   - delta, K (Kr) do not differentiate — fix delta=0
#   - k_s=0 (no per-season deviation) wins cleanly
#   - Expand lower-boundary winners: Kr, k_f, alpha_state
#
# Grid: Kr in {1,2,3} x k_f in {2,3,4} x alpha in {0.10,0.15,0.20,0.25}
#       = 36 specs (fixed: delta=0, k_s=0, lambda_w=0)
#
# Architecture: same two-phase design as v2.
#   Phase 1 — M1 predictions per fold  (checkpoint: nested_loso_v3_phase1.rds)
#              Reuses v2 Phase 1 if available (same M1 settings).
#   Phase 2 — M2-only grid search       (checkpoint: nested_loso_v3_phase2.rds)
#
# Resume after crash: re-run; checkpoints skip completed work.
# Fresh start: delete both checkpoint files.
#
# Usage:
#   source("scripts/run_nested_loso_v3.R")   # interactive R session
#   Rscript scripts/run_nested_loso_v3.R      # terminal
# ============================================================

cat("=== Nested LOSO M2 grid search (v3 — expanded grid) ===\n")
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

wd <- here::here()
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

cat("Data:", nrow(allD), "rows,", length(unique(allD$season)), "seasons\n")

params <- readRDS("data/stage1_tuning.rds")$best_params

manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)

EXCLUDE_SEAS <- "2015-16"

flag_args <- list(
  p_thresh   = 0.01,
  k1         = 0.4,
  k_c        = 0.01,
  n_consec   = 2L,
  min_window = 10L,
  w_min      = 21L,
  w_max      = 21L,
  d2_relax   = -0.01
)

# ---- 2. M1 settings (fixed, already tuned) ----
M1 <- list(
  k_ref              = 25L,
  ref_method         = "fs",
  temperature        = 0.25,
  rise_weight        = 1.0,
  trough_weight      = 0.1,
  peak_decay         = 0.3,
  slope_weight       = 0.5,
  slope_window       = 4L,
  dynamic_temp       = TRUE,
  dynamic_temp_pivot = 10L
)

# ---- 3. M2 spec grid (expanded) ----
# v2 findings: delta and Kr=3/5 tied -> fix delta=0; k_s=0 wins -> fix k_s=0
# Expand lower-boundary winners: Kr, k_f, alpha_state
grid <- tidyr::crossing(
  Kr          = c(1L, 2L, 3L),
  k_f         = c(2L, 3L, 4L),
  alpha_state = c(0.10, 0.15, 0.20, 0.25)
)

specs <- purrr::pmap(grid, function(Kr, k_f, alpha_state) {
  stage2_make_spec(
    delta       = 0L,
    Kr          = Kr,
    T           = "S",
    k_f         = k_f,
    k_e         = 6L,
    k_1         = 4L,
    k_2         = 0L,
    k_w         = 0L,
    k_s         = 0L,
    alpha_state = alpha_state,
    lambda_w    = 0,
    w_floor     = 0.05
  )
})
names(specs) <- sprintf(
  "Kr%d_kf%d_a%.0f",
  grid$Kr, grid$k_f, grid$alpha_state * 100
)
cat("Grid:", length(specs), "specs\n")
cat("  Kr in {1,2,3} x k_f in {2,3,4} x alpha in {0.10,0.15,0.20,0.25}\n")
cat("  Fixed: delta=0, k_s=0, lambda_w=0\n\n")

# ---- 4. Test seasons ----
test_seasons <- sort(setdiff(unique(allD$season), EXCLUDE_SEAS))
cat("Test seasons (", length(test_seasons), "):", paste(test_seasons, collapse = ", "), "\n\n")

# ---- 5. Parallelism ----
n_cores <- min(parallel::detectCores() - 1L, 10L)
cat("Cores available:", n_cores, "\n\n")

# ============================================================
# PHASE 1: Build folds + pre-compute M1 predictions
# Reuse v2 Phase 1 checkpoint if available (same M1 settings).
# ============================================================
cat("=== PHASE 1: Folds + M1 predictions ===\n")

phase1_ckpt    <- "data/nested_loso_v3_phase1.rds"
phase1_ckpt_v2 <- "data/nested_loso_v2_phase1.rds"

if (file.exists(phase1_ckpt)) {
  m1_cache  <- readRDS(phase1_ckpt)
  remaining <- setdiff(test_seasons, names(m1_cache))
  cat("Resuming v3 Phase 1:", length(m1_cache), "folds done,", length(remaining), "remaining\n\n")
} else if (file.exists(phase1_ckpt_v2)) {
  m1_cache <- readRDS(phase1_ckpt_v2)
  cat("Reusing v2 Phase 1 cache:", length(m1_cache), "folds\n")
  remaining <- setdiff(test_seasons, names(m1_cache))
  if (length(remaining) == 0) {
    cat("All folds already in v2 cache — skipping Phase 1.\n\n")
  } else {
    cat("Missing folds:", paste(remaining, collapse = ", "), "\n\n")
  }
  saveRDS(m1_cache, phase1_ckpt)
} else {
  m1_cache  <- list()
  remaining <- test_seasons
  cat("No cache found — computing all", length(remaining), "folds.\n\n")
}

future::plan(future::multicore, workers = n_cores)

for (test_s in remaining) {
  cat(sprintf("[%s] Building fold + M1...\n", test_s))
  t0 <- proc.time()[["elapsed"]]

  fold <- nested_loso_build_fold(
    allD            = allD,
    test_season     = test_s,
    exclude_seasons = EXCLUDE_SEAS,
    k_ref           = M1$k_ref,
    ref_method      = M1$ref_method,
    manual_labels   = manual_labels,
    verbose         = FALSE
  )

  m1_train <- m1_walkforward_multi(
    allD               = allD,
    ref                = fold$ref,
    hyper              = fold$hyper,
    params             = params,
    seasons            = fold$train_seasons,
    temperature        = M1$temperature,
    rise_weight        = M1$rise_weight,
    trough_weight      = M1$trough_weight,
    peak_decay         = M1$peak_decay,
    slope_weight       = M1$slope_weight,
    slope_window       = M1$slope_window,
    dynamic_temp       = M1$dynamic_temp,
    dynamic_temp_pivot = M1$dynamic_temp_pivot,
    parallel           = TRUE,
    verbose            = FALSE
  )

  m1_test <- m1_walkforward_predictions(
    seasonD            = allD[allD$season == test_s, ],
    ref                = fold$ref,
    hyper              = fold$hyper,
    params             = params,
    temperature        = M1$temperature,
    rise_weight        = M1$rise_weight,
    trough_weight      = M1$trough_weight,
    peak_decay         = M1$peak_decay,
    slope_weight       = M1$slope_weight,
    slope_window       = M1$slope_window,
    dynamic_temp       = M1$dynamic_temp,
    dynamic_temp_pivot = M1$dynamic_temp_pivot
  )

  m1_cache[[test_s]] <- list(fold = fold, m1_train = m1_train, m1_test = m1_test)
  saveRDS(m1_cache, phase1_ckpt)

  elapsed <- round(proc.time()[["elapsed"]] - t0)
  cat(sprintf("  Done in %ds | m1_train=%d rows | m1_test=%d rows\n\n",
              elapsed, nrow(m1_train), nrow(m1_test)))
}

cat("Phase 1 complete.\n\n")

# ============================================================
# PHASE 2: M2 grid search
# ============================================================
cat("=== PHASE 2: M2 grid search ===\n")
cat("(", length(specs), "specs x", length(test_seasons), "folds)\n\n")

phase2_ckpt <- "data/nested_loso_v3_phase2.rds"

if (file.exists(phase2_ckpt)) {
  cv_results    <- readRDS(phase2_ckpt)
  todo_spec_ids <- setdiff(names(specs), names(cv_results))
  cat("Resuming:", length(cv_results), "specs done,", length(todo_spec_ids), "remaining\n\n")
} else {
  cv_results    <- list()
  todo_spec_ids <- names(specs)
}

batch_size   <- n_cores
todo_batches <- split(todo_spec_ids,
                      ceiling(seq_along(todo_spec_ids) / batch_size))

future::plan(future::multicore, workers = n_cores)

for (bi in seq_along(todo_batches)) {
  batch <- todo_batches[[bi]]
  cat(sprintf("Batch %d/%d: %s\n", bi, length(todo_batches), paste(batch, collapse = ", ")))
  t0 <- proc.time()[["elapsed"]]

  batch_results <- furrr::future_map(
    stats::setNames(batch, batch),
    function(spec_id) {
      spec <- specs[[spec_id]]

      fold_scores <- vector("list", length(test_seasons))
      fold_preds  <- vector("list", length(test_seasons))
      names(fold_scores) <- names(fold_preds) <- test_seasons

      for (test_s in test_seasons) {
        fc <- m1_cache[[test_s]]

        m2 <- tryCatch(
          nested_loso_m2_train(
            fold           = fc$fold,
            m1_train_preds = if (!is.null(fc$m1_train) && nrow(fc$m1_train) > 0) fc$m1_train else NULL,
            spec           = spec,
            verbose        = FALSE
          ),
          error = function(e) NULL
        )

        if (is.null(m2)) {
          fold_scores[[test_s]] <- tibble::tibble(
            season   = test_s, n = NA_integer_,
            mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_
          )
          fold_preds[[test_s]] <- tibble::tibble()
          next
        }

        eval_out <- tryCatch(
          nested_loso_m2_eval(
            allD          = allD,
            fold          = fc$fold,
            m2_fit        = m2,
            m1_test_preds = if (!is.null(fc$m1_test) && nrow(fc$m1_test) > 0) fc$m1_test else NULL,
            spec          = spec,
            eval_window   = 12L,
            k_deriv       = 10L,
            manual_labels = manual_labels,
            flag_args     = flag_args,
            verbose       = FALSE
          ),
          error = function(e) NULL
        )

        if (is.null(eval_out)) {
          fold_scores[[test_s]] <- tibble::tibble(
            season   = test_s, n = NA_integer_,
            mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_
          )
          fold_preds[[test_s]] <- tibble::tibble()
        } else {
          fold_scores[[test_s]] <- eval_out$scores
          fold_preds[[test_s]]  <- eval_out$predictions
        }
      }

      list(
        scores      = dplyr::bind_rows(fold_scores),
        predictions = dplyr::bind_rows(fold_preds)
      )
    },
    .options = furrr::furrr_options(seed = TRUE)
  )

  cv_results <- c(cv_results, batch_results)
  saveRDS(cv_results, phase2_ckpt)

  elapsed   <- round(proc.time()[["elapsed"]] - t0)
  batch_nlls <- sapply(batch_results, function(r) round(mean(r$scores$mean_nll, na.rm = TRUE), 4))
  cat(sprintf("  Done in %ds | mean_nll: %s\n\n",
              elapsed, paste(sprintf("%s=%.4f", names(batch_nlls), batch_nlls), collapse = ", ")))
}

future::plan(future::sequential)

# ============================================================
# Assemble final results
# ============================================================
cat("=== Assembling final results ===\n")

all_scores <- purrr::imap_dfr(cv_results, ~ dplyr::mutate(.x$scores, spec_id = .y))

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
best_spec <- specs[[best_id]]

results <- list(
  scores       = all_scores,
  summary      = summary_df,
  best_spec_id = best_id,
  best_spec    = best_spec,
  cv_results   = cv_results
)

saveRDS(results, "data/nested_loso_v3_production.rds")

cat("\n=== DONE ===\n")
cat("End:", format(Sys.time()), "\n")
cat("Best spec:", best_id, "\n")
cat("Best mean_nll:", round(summary_df$mean_nll[1], 4), "\n\n")
cat("Top 10:\n")
print(head(summary_df, 10))
