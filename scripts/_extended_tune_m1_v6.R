#!/usr/bin/env Rscript
# ============================================================
# M1 Alignment Tuning — v6
#
# Motivation: v5 showed sw=6, wt=2.0 → 1.626 (best so far), with a clear
# monotone trend: higher slope_weight consistently reduces MAE. The optimum
# is not yet found. v6 extends:
#   1. slope_weight up to 8.0 (trend not plateaued at 2.0)
#   2. slope_window up to 12 (sw=6 > sw=4 at wt=2.0; explore wider)
#   3. template_shift ∈ {0,1} (Windows log showed shift=1 gave 1.474)
#
# Fixed: dynamic_temp=FALSE (confirmed no effect for wt > 0)
# Output: data/m1_alignment_tuning_v6.rds
# ============================================================

cat("=== M1 alignment tuning v6 (slope_weight extended + template_shift) ===\n")
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
manual_labels <- manual_labels_orig - 1L

# ---- Grid ----
# Focus on the region that's been best (sw=6, wt=2.0) and extend outward:
# - slope_weight: 2.0, 3.0, 5.0, 8.0  (high end; lower already known from v5)
# - slope_window: 6, 8, 10, 12         (sw=6 was best; explore larger)
# - template_shift: 0, 1               (Windows log showed shift=1 → ~1.474)
grid_v6 <- tidyr::crossing(
  k_ref             = 25L,
  multi_temperature = 0.25,
  template_shift    = c(0L, 1L),
  align_rise_weight = 1.0,
  slope_window      = c(6L, 8L, 10L, 12L),
  slope_weight      = c(2.0, 3.0, 5.0, 8.0)
)

cat("Grid:", nrow(grid_v6), "specs (",
    length(unique(grid_v6$slope_window)), "slope_window x",
    length(unique(grid_v6$slope_weight)), "slope_weight x",
    length(unique(grid_v6$template_shift)), "template_shift)\n\n")

# ---- Run tuning ----
tune_v6 <- tune_m1_alignment(
  allD               = allD,
  params             = params,
  grid               = grid_v6,
  manual_labels      = manual_labels,
  exclude_seasons    = "2015-16",
  n_weeks            = 52L,
  use_multi_template = TRUE,
  ref_method         = "fs",
  checkpoint_dir     = "data/m1_tune_ckpt_v6",
  n_cores            = n_cores,
  verbose            = TRUE,
  dynamic_temp       = FALSE,
  k_deriv            = 20L,
  buffer_weeks       = 5L,
  curvature_ratio    = 1.0,
  align_peak_decay   = 0.3,
  align_trough_weight = 0.1,
  peak_weight_boost  = 3,
  peak_weight_decay  = 0.3
)

# ---- Results ----
cat("\n=== v6 Results ===\n")

cat("\nBy template_shift:\n")
for (sh in sort(unique(tune_v6$results$template_shift))) {
  cat(sprintf("\n--- template_shift = %d ---\n", sh))
  pivot <- tune_v6$results |>
    dplyr::filter(template_shift == sh) |>
    dplyr::arrange(slope_window, slope_weight) |>
    dplyr::select(slope_window, slope_weight, mae_weibull) |>
    tidyr::pivot_wider(names_from = slope_weight, values_from = mae_weibull,
                       names_prefix = "wt=")
  print(pivot)
}

cat("\nTop 10 specs overall:\n")
print(
  tune_v6$results |>
    dplyr::arrange(mae_weibull) |>
    dplyr::select(template_shift, slope_window, slope_weight,
                  mae_uniform, mae_exp, mae_weibull) |>
    head(10)
)

best <- tune_v6$results |> dplyr::arrange(mae_weibull) |> dplyr::slice(1)
cat(sprintf(
  "\nBest: shift=%d, slope_window=%d, slope_weight=%.2f  ->  MAE_weibull=%.4f\n",
  best$template_shift, best$slope_window, best$slope_weight, best$mae_weibull
))
cat(sprintf("v5 best was 1.626 (sw=6, wt=2.0, shift=0); v6 delta = %.4f\n",
            best$mae_weibull - 1.626))

# ---- Save ----
saveRDS(tune_v6, "data/m1_alignment_tuning_v6.rds")
cat("\nSaved: data/m1_alignment_tuning_v6.rds\n")
cat("End:", format(Sys.time()), "\n")
