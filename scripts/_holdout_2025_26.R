#!/usr/bin/env Rscript
# ============================================================
# M1 Holdout Test — 2025-26 season
#
# 2025-26 is excluded from all LOSO folds (used in production training).
# This script uses it as a genuine out-of-sample test to check whether
# the slope_weight gains in v5/v6 generalize beyond the 10 LOSO seasons.
#
# True peak: week 51 (weekF=25), positivity=0.357 (already confirmed declining)
#
# For each candidate slope_weight, run alignment walk-forward on 2025-26
# (training on all 10 LOSO seasons), compute Weibull-weighted peak MAE.
# ============================================================

cat("=== M1 holdout test: 2025-26 ===\n")
cat("Start:", format(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(flualign)
  library(dplyr)
  library(furrr)
  library(MMWRweek)
})

for (f in c(
  "R/utils.R", "R/m0_retro.R", "R/flagIgnition.R",
  "R/m1_reference.R", "R/m1_reference_helpers.R",
  "R/m1_multi_template.R", "R/m1_loso.R", "R/m1_fit.R",
  "R/align_forecast_pipeline_dilate.R"
)) source(f)

n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
}

# ---- Data: ALL seasons including 2025-26 ----
allD <- read.csv("data/flu_testing_data.csv") |>
  dplyr::select(
    season, week, year, start_year = seasonstart,
    date = week_start_date, y = pos_flua, N = test_flu
  ) |>
  dplyr::mutate(
    neg     = N - y,
    date    = as.Date(date),
    nW_true = n_weeks_in_start_year(start_year),
    weekF   = ((week - 27L) %% nW_true) + 1L,
    p       = y / N
  ) |>
  dplyr::filter(!season %in% c("2011-12", "2020-21", "2021-22"))
# NOTE: 2025-26 is KEPT here (not filtered out)

params <- readRDS("data/stage1_tuning.rds")$best_params

manual_labels_orig <- c(
  "2012-13" = 24L, "2013-14" = 22L, "2014-15" = 17L,
  "2015-16" = 19L, "2016-17" = 21L, "2017-18" = 18L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L,
  "2025-26" = 23L  # approximate; will be overridden by ignition detection
)
manual_labels <- manual_labels_orig - 1L

# True peak for 2025-26
true_peak_2025 <- allD |>
  dplyr::filter(season == "2025-26", !is.na(p), N > 0) |>
  dplyr::slice_max(p, n = 1, with_ties = FALSE) |>
  dplyr::pull(weekF)
cat("True peak weekF for 2025-26:", true_peak_2025, "\n\n")

# ---- Test specs: key slope_weight values from v5/v6 ----
test_specs <- data.frame(
  slope_window = c(6L, 6L, 6L, 6L, 6L, 6L),
  slope_weight = c(0,   1.0, 2.0, 3.0, 5.0, 8.0),
  template_shift = 0L
)

score_holdout <- function(sw, wt, shift) {
  plan(multisession, workers = 10L)
  wf <- loso_walkforward(
    allD               = allD,
    params             = params,
    test_seasons       = "2025-26",
    k_ref              = 25L,
    multi_temperature  = 0.25,
    template_shift     = shift,
    align_rise_weight  = 1.0,
    manual_labels      = manual_labels,
    exclude_seasons    = "2015-16",
    n_weeks            = 52L,
    use_multi_template = TRUE,
    ref_method         = "fs",
    k_deriv            = 20L,
    buffer_weeks       = 5L,
    curvature_ratio    = 1.0,
    align_peak_decay   = 0.3,
    align_trough_weight = 0.1,
    peak_weight_boost  = 3,
    peak_weight_decay  = 0.3,
    slope_weight       = wt,
    slope_window       = sw,
    dynamic_temp       = FALSE,
    verbose            = FALSE
  )
  plan(sequential)

  score_df <- wf$params_df |>
    dplyr::filter(!is.na(t_peak), !is.na(iWeek_true)) |>
    dplyr::mutate(pred_peak_weekF = round(t_peak - anchorWeek + iWeek_hat)) |>
    dplyr::filter(!is.na(pred_peak_weekF), eval_week <= true_peak_2025) |>
    dplyr::mutate(
      error  = abs(pred_peak_weekF - true_peak_2025),
      t      = eval_week - iWeek_true,
      w_weib = exp(-(0.1 * t)^2)
    )

  if (nrow(score_df) == 0) return(NA_real_)
  sum(score_df$w_weib * score_df$error) / sum(score_df$w_weib)
}

cat("Running holdout for each slope_weight:\n")
results <- vector("list", nrow(test_specs))
for (i in seq_len(nrow(test_specs))) {
  sw  <- test_specs$slope_window[i]
  wt  <- test_specs$slope_weight[i]
  sh  <- test_specs$template_shift[i]
  mae <- score_holdout(sw, wt, sh)
  results[[i]] <- data.frame(slope_window = sw, slope_weight = wt,
                              template_shift = sh, mae_holdout = mae)
  cat(sprintf("  sw=%d, wt=%.1f, shift=%d  ->  MAE=%.4f\n", sw, wt, sh, mae))
}

out <- dplyr::bind_rows(results)
cat("\n=== 2025-26 Holdout Results ===\n")
print(out)

# Compare with LOSO MAE from v5/v6
loso_mae <- c(1.929, 1.829, 1.626, 1.525, 1.382, 1.275)
out$loso_mae <- loso_mae
out$generalization_gap <- out$mae_holdout - out$loso_mae
cat("\nGeneralization gap (holdout - LOSO):\n")
print(out[, c("slope_weight", "mae_holdout", "loso_mae", "generalization_gap")])

saveRDS(out, "data/m1_holdout_2025_26.rds")
cat("\nSaved: data/m1_holdout_2025_26.rds\n")
cat("End:", format(Sys.time()), "\n")
