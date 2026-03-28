#!/usr/bin/env Rscript
# ============================================================
# Production nested LOSO grid search for M2 hyperparameter tuning
# Usage:  Rscript scripts/run_nested_loso_full.R
#
# Files needed on server (copy from repo root):
#   R/                        <- the whole R/ folder
#   data/forServer.RData      <- allD, params, manual_labels
#   scripts/run_nested_loso_full.R
#
# Output: data/nested_loso_production.rds
#         data/nested_loso_checkpoint.rds  (incremental, survives crashes)
# ============================================================

cat("=== Nested LOSO production grid search ===\n")
cat("Start:", format(Sys.time()), "\n\n")

# --- 1. Load packages (no flualign package install needed) ---
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(mgcv)
  library(MMWRweek)
  library(future)
  library(furrr)
  library(data.table)
  library(ggplot2)
  library(plotly)
})

# Source all required R files (order matters: dependencies first)
source("R/utils.R")
source("R/retro_estimation.R")
source("R/reference.R")
source("R/estimateRef.R")
source("R/hyperparams.R")
source("R/fit.R")
source("R/identifiability.R")
source("R/check_scale_identifiability.R")
source("R/prospective_alignment.R")
source("R/align_forecast_pipeline_dilate.R")
source("R/peak_status_from_align.R")
source("R/flagPeak.R")
source("R/peak.R")
source("R/ignitionTraining.R")
source("R/loso_alignment.R")
source("R/prospective_training.R")
source("R/prospective_running.R")
source("R/forecast_post_peak_gam.R")
source("R/module_training.R")
source("R/m1_m2_bridge.R")
source("R/nested_loso.R")

# --- 2. Load data ---
load("data/forServer.RData")  # allD, params, manual_labels
cat("Data loaded:", nrow(allD), "rows,", length(unique(allD$season)), "seasons\n")

# --- 3. Build production grid (~144 specs) ---
grid <- tidyr::crossing(
  delta       = c(-2L, -1L, 0L, 1L, 2L),
  K           = c(1L, 3L, 5L),
  T           = c("S", "O"),
  k_s         = c(0L, 4L),
  alpha_state = c(0.20, 0.25, 0.30),
  lambda_w    = c(0, 0.05)
)

# k_f only matters for T="S"; for T="O" fix at 6
grid_S <- grid |> dplyr::filter(T == "S") |>
  tidyr::crossing(k_f = c(4L, 6L, 8L))
grid_O <- grid |> dplyr::filter(T == "O") |>
  dplyr::mutate(k_f = 6L)
grid <- dplyr::bind_rows(grid_S, grid_O) |>
  dplyr::mutate(
    spec_id = dplyr::if_else(
      T == "S",
      sprintf("d%+d_K%d_S_kf%d_ks%d_a%.0f_lw%.0f",
              delta, K, k_f, k_s, alpha_state * 100, lambda_w * 100),
      sprintf("d%+d_K%d_O_ks%d_a%.0f_lw%.0f",
              delta, K, k_s, alpha_state * 100, lambda_w * 100)
    )
  )

prod_specs <- purrr::pmap(grid, function(delta, K, T, k_s, alpha_state,
                                          lambda_w, k_f, spec_id) {
  stage2_make_spec(
    delta = delta, K = K, T = T, k_f = k_f,
    k_e = 6L, k_1 = 4L, k_2 = 0L, k_w = 0L, k_s = k_s,
    alpha_state = alpha_state, lambda_w = lambda_w, w_floor = 0.05
  )
})
names(prod_specs) <- grid$spec_id

n_cores <- min(parallel::detectCores() - 1L, 8L)
cat("Grid:", length(prod_specs), "specs x 11 seasons x ~40 min/fold\n")
cat("Using", n_cores, "cores\n\n")

# --- 4. Run nested LOSO grid search ---
prod_results <- nested_loso_grid_search(
  allD            = allD,
  params          = params,
  specs           = prod_specs,
  checkpoint_file = "data/nested_loso_checkpoint.rds",  # resume on crash
  test_seasons    = NULL,          # all seasons
  skip_m1         = FALSE,         # full M1 walk-forward
  eval_window     = 12L,
  k_deriv         = 10L,
  k_ref           = 8L,
  n_weeks         = 52L,
  manual_labels   = manual_labels,
  n_cores         = n_cores,
  verbose         = TRUE
)

# --- 5. Save results ---
saveRDS(prod_results, "data/nested_loso_production.rds")

cat("\n=== DONE ===\n")
cat("End:", format(Sys.time()), "\n")
cat("Best spec:", prod_results$best_spec_id, "\n")
cat("Best mean_nll:", round(prod_results$summary$mean_nll[1], 4), "\n")
cat("\nTop 10 specs:\n")
print(head(prod_results$summary, 10))
