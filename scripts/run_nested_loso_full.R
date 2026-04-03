#!/usr/bin/env Rscript
# ============================================================
# Nested LOSO grid search for M2 hyperparameter tuning
#
# Usage (from repo root):
#   Rscript scripts/run_nested_loso_full.R
#   -- or source() from an interactive R session --
#
# Output:
#   data/nested_loso_production.rds   (final results)
#   data/nested_loso_ckpt.rds         (incremental checkpoint — safe to crash)
#
# To resume after a crash: just re-run; completed specs are skipped.
# To start fresh: delete data/nested_loso_ckpt.rds before running.
# ============================================================

cat("=== Nested LOSO M2 grid search ===\n")
cat("Start:", format(Sys.time()), "\n\n")

# --- 1. Packages ---
suppressPackageStartupMessages({
  library(flualign)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(mgcv)
  library(MMWRweek)
  library(future)
  library(furrr)
  library(data.table)
})

# --- 2. Paths ---
wd <- here::here()   # repo root; works from any working directory
setwd(wd)
cat("Working dir:", wd, "\n")

# --- 3. Data ---
n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
}

startWeek <- 27L

allD <- read.csv("data/flu_testing_data.csv") |>
  dplyr::select(
    season, week, year,
    start_year = seasonstart,
    date       = week_start_date,
    y          = pos_flua,
    N          = test_flu
  ) |>
  dplyr::mutate(
    neg      = N - y,
    date     = as.Date(date),
    nW_true  = n_weeks_in_start_year(start_year),
    weekF    = ((week - startWeek) %% nW_true) + 1L,
    p        = y / N
  ) |>
  dplyr::filter(!season %in% c("2011-12", "2020-21", "2021-22", "2025-26"))

cat("Data: ", nrow(allD), "rows,", length(unique(allD$season)), "seasons\n")

# M0 ignition detection params (tuned)
params <- readRDS("data/stage1_tuning.rds")$best_params

# Manual ignition labels (weekF, shifted -1 from originals)
manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)

# 2015-16 excluded from LOSO folds (ignition outlier)
EXCLUDE_SEAS <- "2015-16"

# --- 4. M1 settings (fixed — already tuned) ---
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

# --- 5. M2 spec grid ---
# Targeted 32-spec grid informed by smoke test + leaky-LOSO results.
# Centre: delta=0, K=3, k_f=4, alpha=0.30 (smoke test winner).
# Expand: ±1 delta, K={3,5}, k_f={4,6}, k_s={0,4}, alpha={0.25,0.30}.
# lambda_w=0 (smoke test winner; expand to 0.05 in a follow-up if needed).

grid <- tidyr::crossing(
  delta       = c(-1L, 0L, 1L),
  K           = c(3L, 5L),
  k_f         = c(4L, 6L),
  k_s         = c(0L, 4L),
  alpha_state = c(0.25, 0.30),
  lambda_w    = 0
)

specs <- purrr::pmap(grid, function(delta, K, k_f, k_s, alpha_state, lambda_w) {
  stage2_make_spec(
    delta       = delta,
    Kr          = K,
    T           = "S",
    k_f         = k_f,
    k_e         = 6L,
    k_1         = 4L,
    k_2         = 0L,
    k_w         = 0L,
    k_s         = k_s,
    alpha_state = alpha_state,
    lambda_w    = lambda_w,
    w_floor     = 0.05
  )
})
names(specs) <- sprintf(
  "d%+d_K%d_kf%d_ks%d_a%.0f_lw%.0f",
  grid$delta, grid$K, grid$k_f, grid$k_s,
  grid$alpha_state * 100, grid$lambda_w * 100
)

cat("Grid:", length(specs), "specs\n\n")

# --- 6. Parallelism ---
# multicore (fork) is faster on Linux; each fold uses n_cores workers for M1.
n_cores <- min(parallel::detectCores() - 1L, 11L)
cat("Using", n_cores, "cores (multicore)\n\n")
future::plan(future::multicore, workers = n_cores)

# --- 7. Run ---
results <- nested_loso_grid_search(
  allD            = allD,
  params          = params,
  specs           = specs,
  checkpoint_file = "data/nested_loso_ckpt.rds",
  # M1 fixed params
  k_ref              = M1$k_ref,
  ref_method         = M1$ref_method,
  temperature        = M1$temperature,
  rise_weight        = M1$rise_weight,
  trough_weight      = M1$trough_weight,
  peak_decay         = M1$peak_decay,
  slope_weight       = M1$slope_weight,
  slope_window       = M1$slope_window,
  dynamic_temp       = M1$dynamic_temp,
  dynamic_temp_pivot = M1$dynamic_temp_pivot,
  # LOSO settings
  exclude_seasons = EXCLUDE_SEAS,
  manual_labels   = manual_labels,
  eval_window     = 12L,
  k_deriv         = 10L,
  n_weeks         = 52L,
  n_cores         = n_cores,
  verbose         = TRUE
)

# --- 8. Save ---
saveRDS(results, "data/nested_loso_production.rds")

cat("\n=== DONE ===\n")
cat("End:", format(Sys.time()), "\n")
cat("Best spec:", results$best_spec_id, "\n")
cat("Best mean_nll:", round(results$summary$mean_nll[1], 4), "\n\n")
cat("Top 10:\n")
print(head(results$summary, 10))
