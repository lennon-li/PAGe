#!/usr/bin/env Rscript
# ============================================================
# M1 Alignment Tuning — v7
#
# v6 findings (locked in):
#   - sw=6 clearly optimal (sw=8,10,12 all worse)
#   - template_shift=0 wins at high slope_weight
#   - slope_weight=8 still monotone (optimum not found)
#   - k_ref=25 at grid boundary (never tested higher)
#
# v7 explores:
#   - slope_weight ∈ {8, 12, 16, 20, 30}   (extend past current best)
#   - k_ref        ∈ {25, 30, 40, 50}       (fix upper boundary)
#   - slope_window = 6, template_shift = 0  (locked from v6)
#
# Grid: 5 × 4 = 20 specs
# Output: data/m1_alignment_tuning_v7.rds
# ============================================================

cat("=== M1 alignment tuning v7 (slope_weight + k_ref expansion) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(flualign)
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

manual_labels_orig <- c(
  "2012-13" = 24L, "2013-14" = 22L, "2014-15" = 17L,
  "2015-16" = 19L, "2016-17" = 21L, "2017-18" = 18L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)
manual_labels <- manual_labels_orig - 1L

# ---- Grid ----
# sw=6, shift=0 locked; vary k_ref and slope_weight
grid_v7 <- tidyr::crossing(
  k_ref             = c(25L, 30L, 40L, 50L),
  multi_temperature = 0.25,
  template_shift    = 0L,
  align_rise_weight = 1.0,
  slope_window      = 6L,
  slope_weight      = c(8.0, 12.0, 16.0, 20.0, 30.0)
)

cat("Grid:", nrow(grid_v7), "specs (",
    length(unique(grid_v7$k_ref)), "k_ref x",
    length(unique(grid_v7$slope_weight)), "slope_weight)\n")
cat("Locked: sw=6, shift=0, dynamic_temp=FALSE\n\n")

# ---- Run tuning ----
tune_v7 <- tune_m1_alignment(
  allD               = allD,
  params             = readRDS("data/stage1_tuning.rds")$best_params,
  grid               = grid_v7,
  manual_labels      = manual_labels,
  exclude_seasons    = "2015-16",
  n_weeks            = 52L,
  use_multi_template = TRUE,
  ref_method         = "fs",
  checkpoint_dir     = "data/m1_tune_ckpt_v7",
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
cat("\n=== v7 Results: k_ref x slope_weight ===\n")

scores <- readRDS("data/m1_tune_ckpt_v7/tune_m1_results.rds")
grid_v7$spec_id <- sprintf("s%03d", seq_len(nrow(grid_v7)))
res <- dplyr::left_join(grid_v7, scores, by = "spec_id")
saveRDS(list(results = res, grid = grid_v7), "data/m1_alignment_tuning_v7.rds")

cat("\nMAE pivot (rows=k_ref, cols=slope_weight):\n")
piv <- res |>
  dplyr::select(k_ref, slope_weight, mae_weibull) |>
  tidyr::pivot_wider(names_from = slope_weight, values_from = mae_weibull,
                     names_prefix = "wt=")
print(piv)

best <- res[which.min(res$mae_weibull), ]
cat(sprintf(
  "\nBest: k_ref=%d, slope_weight=%.0f -> MAE=%.4f\n",
  best$k_ref, best$slope_weight, best$mae_weibull
))
cat(sprintf("v6 best was 1.2750 (k_ref=25, wt=8); delta=%.4f\n",
            best$mae_weibull - 1.2750))

# Boundary check
cat("\nBoundary check:\n")
cat(sprintf("  k_ref boundary: best k_ref=%d (max tested=%d) — %s\n",
            best$k_ref, max(res$k_ref),
            if (best$k_ref == max(res$k_ref)) "STILL AT BOUNDARY" else "interior"))
cat(sprintf("  slope_weight boundary: best wt=%.0f (max tested=%.0f) — %s\n",
            best$slope_weight, max(res$slope_weight),
            if (best$slope_weight == max(res$slope_weight)) "STILL AT BOUNDARY" else "interior"))

cat("\nEnd:", format(Sys.time()), "\n")
