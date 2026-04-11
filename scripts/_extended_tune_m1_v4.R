#!/usr/bin/env Rscript
# ============================================================
# M1 Alignment Tuning — v4
#
# Motivation: 2024-25 and 2025-26 seasons show ~2-week alignment error,
# traced to a false-plateau during the rise phase. At weekF 27-28 the
# 4-week logit slope decelerates sharply, making the ensemble prefer
# near-peak templates when the season is still 4+ weeks from peak.
#
# Fix hypothesis: a longer slope_window (6 or 8 weeks) would capture the
# broader upward trend, reducing the false-plateau effect.
#
# This script ablates slope_window x slope_weight around the known-best
# hyperparams (k_ref=25, temperature=0.25, shift=0, rise_weight=1.0).
# Also includes the existing baseline (slope_window=4, slope_weight=0.5)
# so the result file is self-contained for benchmarking.
#
# Two-phase fix already in code (not tuned here):
#   - slope-similarity uses aligned positions u_hat = (t - tau) / (1+delta)
#   - per-template GAM SE propagated for CI coverage
#
# Output: data/m1_alignment_tuning_v4.rds
# ============================================================

cat("=== M1 alignment tuning v4 (slope_window x slope_weight ablation) ===\n")
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

params <- readRDS("data/stage1_tuning.rds")$best_params

manual_labels <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)

# ---- Grid ----
# Fix known-best params; ablate slope dimensions.
# Include slope_window=4, slope_weight=0.5 (current default) as baseline.
grid_v4 <- tidyr::crossing(
  k_ref             = 25L,
  multi_temperature = 0.25,
  template_shift    = 0L,
  align_rise_weight = 1.0,
  slope_window      = c(4L, 6L, 8L, 10L),
  slope_weight      = c(0.2, 0.3, 0.5, 0.7, 1.0)
)

cat("Grid: ", nrow(grid_v4), "specs (",
    length(unique(grid_v4$slope_window)), "slope_window x",
    length(unique(grid_v4$slope_weight)), "slope_weight)\n\n")

cat("Baseline spec: slope_window=4, slope_weight=0.5 (current defaults)\n\n")

# ---- Run tuning ----
tune_v4 <- tune_m1_alignment(
  allD              = allD,
  params            = params,
  grid              = grid_v4,
  manual_labels     = manual_labels,
  exclude_seasons   = "2015-16",
  n_weeks           = 52L,
  use_multi_template = TRUE,
  ref_method         = "fs",
  checkpoint_dir     = "data/m1_tune_ckpt_v4",
  n_cores            = n_cores,
  verbose            = TRUE,
  # Fixed non-grid params (names must match loso_walkforward formals exactly)
  k_deriv            = 20L,
  buffer_weeks       = 5L,
  curvature_ratio    = 1.0,
  dynamic_temp       = TRUE,
  dynamic_temp_pivot = 10L,
  align_peak_decay   = 0.3,
  align_trough_weight = 0.1
)

# ---- Results ----
cat("\n=== v4 Results: slope_window x slope_weight ===\n")

# Pivot table: slope_window rows, slope_weight cols
pivot <- tune_v4$results |>
  dplyr::arrange(mae_weibull) |>
  dplyr::select(slope_window, slope_weight, mae_weibull) |>
  tidyr::pivot_wider(names_from = slope_weight, values_from = mae_weibull,
                     names_prefix = "sw=")
cat("\nMAE (Weibull) — rows=slope_window, cols=slope_weight:\n")
print(pivot)

cat("\nTop 10 specs:\n")
print(
  tune_v4$results |>
    dplyr::arrange(mae_weibull) |>
    dplyr::select(slope_window, slope_weight, mae_uniform, mae_exp, mae_weibull) |>
    head(10)
)

best <- tune_v4$results |> dplyr::arrange(mae_weibull) |> dplyr::slice(1)
cat(sprintf(
  "\nBest: slope_window=%d, slope_weight=%.1f  ->  MAE_weibull=%.4f\n",
  best$slope_window, best$slope_weight, best$mae_weibull
))

baseline <- tune_v4$results |>
  dplyr::filter(slope_window == 4L, abs(slope_weight - 0.5) < 0.01)
cat(sprintf(
  "Baseline (sw=4, wt=0.5):     MAE_weibull=%.4f\n",
  baseline$mae_weibull
))
cat(sprintf(
  "Improvement: %.4f -> %.4f  (delta=%.4f)\n",
  baseline$mae_weibull, best$mae_weibull,
  best$mae_weibull - baseline$mae_weibull
))

# Compare per-season errors for best vs baseline
cat("\n=== Per-season MAE: best vs baseline ===\n")
v3_base <- readRDS("data/m1_alignment_tuning_v3_baseline.rds")

# Season-level errors from v4 best spec
best_sid <- tune_v4$results$spec_id[which.min(tune_v4$results$mae_weibull)]
ckpt_best <- readRDS(file.path("data/m1_tune_ckpt_v4", paste0("ckpt_", best_sid, ".rds")))

if (!is.null(ckpt_best) && !is.null(ckpt_best$params_df)) {
  true_peaks <- allD |>
    dplyr::filter(!is.na(p), N > 0) |>
    dplyr::group_by(season) |>
    dplyr::slice_max(p, n = 1L, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(season, true_peak_weekF = weekF)

  per_season <- ckpt_best$params_df |>
    dplyr::filter(!is.na(t_peak), !is.na(iWeek_true)) |>
    dplyr::mutate(pred_peak_weekF = round(t_peak - anchorWeek + iWeek_hat)) |>
    dplyr::left_join(true_peaks, by = "season") |>
    dplyr::filter(!is.na(true_peak_weekF), eval_week <= true_peak_weekF) |>
    dplyr::group_by(season) |>
    dplyr::summarise(
      mae_weibull_season = weighted.mean(
        abs(pred_peak_weekF - true_peak_weekF),
        w = exp(-(0.1 * (eval_week - iWeek_true))^2),
        na.rm = TRUE
      ),
      .groups = "drop"
    )
  cat("\nPer-season Weibull MAE (v4 best spec):\n")
  print(per_season |> dplyr::arrange(dplyr::desc(mae_weibull_season)))
}

# ---- Save ----
saveRDS(tune_v4, "data/m1_alignment_tuning_v4.rds")
cat("\nSaved: data/m1_alignment_tuning_v4.rds\n")
cat("End:", format(Sys.time()), "\n")
