#!/usr/bin/env Rscript
# ============================================================
# M1 Alignment Tuning — v5
#
# Motivation: dynamic_temp=TRUE (inflates softmax temperature when n_obs < 10)
# is the root cause of the v3→v4 MAE regression (1.169 → 1.884).
# Disabling it should restore the baseline; slope similarity may then improve further.
#
# Key fix: dynamic_temp=FALSE
# Grid: slope_window × slope_weight (including slope_weight=0 = pure NLL baseline)
#
# Expected: slope_weight=0 → ~1.169; tuned slope → potentially lower.
#
# Output: data/m1_alignment_tuning_v5.rds
# ============================================================

cat("=== M1 alignment tuning v5 (dynamic_temp=FALSE, slope grid) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(PAGe)
  library(dplyr)
  library(tidyr)
  library(MMWRweek)
})

for (f in c(
  "R/utils.R", "R/m0_retro.R", "R/flagIgnition.R",
  "R/m1_reference.R", "R/m1_reference_helpers.R",
  "R/m1_multi_template.R", "R/m1_loso.R", "R/m1_fit.R",
  "R/align_forecast_pipeline_dilate.R"
)) source(f)

n_cores <- max(1L, parallel::detectCores() - 1L)
cat("Cores:", n_cores, "\n\n")

# ---- Data ----
n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)
}

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
  dplyr::filter(!season %in% c("2011-12", "2020-21", "2021-22", "2025-26"))

params <- readRDS("data/stage1_tuning.rds")$best_params

manual_labels_orig <- c(
  "2012-13" = 24L, "2013-14" = 22L, "2014-15" = 17L,
  "2015-16" = 19L, "2016-17" = 21L, "2017-18" = 18L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)
manual_labels <- manual_labels_orig - 1L  # matches v3 baseline

# ---- Grid ----
# slope_weight=0 is the pure NLL baseline (should recover ~1.169)
# slope_weight > 0 may improve further
grid_v5 <- tidyr::crossing(
  k_ref             = 25L,
  multi_temperature = 0.25,
  template_shift    = 0L,
  align_rise_weight = 1.0,
  slope_window      = c(4L, 6L, 8L),
  slope_weight      = c(0, 0.2, 0.5, 1.0, 2.0)
)

cat("Grid:", nrow(grid_v5), "specs (",
    length(unique(grid_v5$slope_window)), "slope_window x",
    length(unique(grid_v5$slope_weight)), "slope_weight)\n")
cat("KEY FIX: dynamic_temp=FALSE\n\n")

# ---- Run tuning ----
tune_v5 <- tune_m1_alignment(
  allD               = allD,
  params             = params,
  grid               = grid_v5,
  manual_labels      = manual_labels,
  exclude_seasons    = "2015-16",
  n_weeks            = 52L,
  use_multi_template = TRUE,
  ref_method         = "fs",
  checkpoint_dir     = "data/m1_tune_ckpt_v5",
  n_cores            = n_cores,
  verbose            = TRUE,
  # KEY FIX: disable dynamic temperature inflation
  dynamic_temp       = FALSE,
  # Other fixed non-grid params
  k_deriv            = 20L,
  buffer_weeks       = 5L,
  curvature_ratio    = 1.0,
  align_peak_decay   = 0.3,
  align_trough_weight = 0.1,
  peak_weight_boost  = 3,
  peak_weight_decay  = 0.3
)

# ---- Results ----
cat("\n=== v5 Results: slope_window x slope_weight (dynamic_temp=FALSE) ===\n")

pivot <- tune_v5$results |>
  dplyr::arrange(slope_window, slope_weight) |>
  dplyr::select(slope_window, slope_weight, mae_weibull) |>
  tidyr::pivot_wider(names_from = slope_weight, values_from = mae_weibull,
                     names_prefix = "wt=")
cat("\nMAE (Weibull) — rows=slope_window, cols=slope_weight:\n")
print(pivot)

cat("\nTop 10 specs:\n")
print(
  tune_v5$results |>
    dplyr::arrange(mae_weibull) |>
    dplyr::select(slope_window, slope_weight, mae_uniform, mae_exp, mae_weibull) |>
    head(10)
)

best <- tune_v5$results |> dplyr::arrange(mae_weibull) |> dplyr::slice(1)
cat(sprintf(
  "\nBest: slope_window=%d, slope_weight=%.2f  ->  MAE_weibull=%.4f\n",
  best$slope_window, best$slope_weight, best$mae_weibull
))

baseline_v5 <- tune_v5$results |>
  dplyr::filter(slope_window == 4L, slope_weight == 0)
if (nrow(baseline_v5) > 0) {
  cat(sprintf(
    "Pure NLL baseline (sw=4, wt=0):  MAE_weibull=%.4f  (v3 target: 1.169)\n",
    baseline_v5$mae_weibull
  ))
  cat(sprintf(
    "Best vs v3 target: %.4f vs 1.169  (delta=%.4f)\n",
    best$mae_weibull, best$mae_weibull - 1.169
  ))
}

# ---- Save ----
saveRDS(tune_v5, "data/m1_alignment_tuning_v5.rds")
cat("\nSaved: data/m1_alignment_tuning_v5.rds\n")
cat("End:", format(Sys.time()), "\n")
