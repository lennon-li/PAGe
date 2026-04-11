#!/usr/bin/env Rscript
# Run this after _extended_tune_m1_v4.R completes.
# Checks results, updates defaults if improved, re-renders QMDs.

cat("=== M1 v4 finalization ===\n")
cat("Time:", format(Sys.time()), "\n\n")

# ---- 1. Check log ----
log_tail <- tryCatch(readLines("/tmp/m1_tune_v4.log"), error = function(e) character(0))
if (length(log_tail) > 0) {
  cat("--- Last 20 lines of tuning log ---\n")
  cat(tail(log_tail, 20), sep = "\n")
  cat("\n")
}

# ---- 2. Load v4 results ----
if (!file.exists("data/m1_alignment_tuning_v4.rds")) {
  cat("ERROR: data/m1_alignment_tuning_v4.rds not found.\n")
  cat("Still running? Check: ps aux | grep tune_m1_v4\n")
  quit(save = "no", status = 1)
}
v4  <- readRDS("data/m1_alignment_tuning_v4.rds")
v3b <- readRDS("data/m1_alignment_tuning_v3_baseline.rds")

cat("=== STEP 1: Pivot table (MAE Weibull) ===\n")
pivot <- v4$results |>
  dplyr::arrange(slope_window, slope_weight) |>
  dplyr::select(slope_window, slope_weight, mae_weibull) |>
  tidyr::pivot_wider(names_from = slope_weight, values_from = mae_weibull,
                     names_prefix = "wt=")
cat("Rows = slope_window, cols = slope_weight:\n")
print(pivot)

best    <- v4$results |> dplyr::arrange(mae_weibull) |> dplyr::slice(1)
base_v3 <- v3b$results |> dplyr::arrange(mae_weibull) |> dplyr::slice(1)

cat(sprintf("\nv3 baseline (sw=4, wt=0.5): MAE_weibull = %.4f\n", base_v3$mae_weibull))
cat(sprintf("v4 best (sw=%d, wt=%.1f):   MAE_weibull = %.4f\n",
            best$slope_window, best$slope_weight, best$mae_weibull))
cat(sprintf("Improvement: %.4f\n", best$mae_weibull - base_v3$mae_weibull))

best_sw <- as.integer(best$slope_window)
best_wt <- as.numeric(best$slope_weight)
improved <- best$mae_weibull < base_v3$mae_weibull - 0.001  # >0.001 improvement threshold

# ---- 3. Update defaults in m1_multi_template.R if improved ----
if (improved && (best_sw != 4L || abs(best_wt - 0.5) > 0.01)) {
  cat("\n=== STEP 2: Updating slope defaults in R/m1_multi_template.R ===\n")

  for (f in c("R/m1_multi_template.R", "flualign/R/m1_multi_template.R")) {
    txt <- readLines(f)
    # Update slope_window default
    txt <- gsub(
      "slope_window\\s*=\\s*[0-9]+L",
      sprintf("slope_window          = %dL", best_sw),
      txt
    )
    # Update slope_weight default
    txt <- gsub(
      "slope_weight\\s*=\\s*[0-9.]+",
      sprintf("slope_weight          = %.1f", best_wt),
      txt
    )
    writeLines(txt, f)
    cat("  Updated:", f, "\n")
  }

  # Update ref_production.rds walk-forward preds (they use slope defaults)
  cat("\nNOTE: ref_production.rds walk-forward preds use the old defaults.\n")
  cat("Run scripts/_rebuild_m2_production_v14.R after re-rendering.\n")
} else {
  cat("\n=== STEP 2: No update needed (best is current default or improvement < threshold) ===\n")
}

# ---- 4. Update loso_walkforward.qmd ----
cat("\n=== STEP 3: Updating docs/loso_walkforward.qmd ===\n")
qmd <- readLines("docs/loso_walkforward.qmd")

# Replace data file reference
qmd <- gsub(
  'readRDS\\("../data/m1_alignment_tuning_v3.rds"\\)',
  'readRDS("../data/m1_alignment_tuning_v4.rds")',
  qmd
)

# Extend top_results select() to include slope_window, slope_weight if present
qmd <- gsub(
  "select\\(k_ref, multi_temperature, template_shift,",
  "select(k_ref, multi_temperature, template_shift, slope_window, slope_weight,",
  qmd
)
qmd <- gsub(
  "mae_uniform, mae_exp, mae_weibull\\)",
  "mae_uniform, mae_exp, mae_weibull)",
  qmd
)

# Update cols_label to add new columns
if (!any(grepl("slope_window.*Slope", qmd))) {
  qmd <- gsub(
    "mae_weibull = \"MAE \\(Weibull\\) ★\"",
    paste0("slope_window = \"Win\",\n    slope_weight = \"Wt\",\n    ",
           "mae_weibull = \"MAE (Weibull) ★\""),
    qmd
  )
}

writeLines(qmd, "docs/loso_walkforward.qmd")
cat("  Updated: docs/loso_walkforward.qmd\n")

# ---- 5. Re-render both QMDs ----
cat("\n=== STEP 4: Re-rendering QMDs ===\n")

render_qmd <- function(path) {
  cat("  Rendering:", path, "...")
  ret <- system2("quarto", c("render", path), stdout = TRUE, stderr = TRUE)
  if (any(grepl("ERROR|error", ret, ignore.case = TRUE))) {
    cat(" FAILED\n")
    cat(tail(ret, 10), sep = "\n")
  } else {
    cat(" OK\n")
  }
}

render_qmd("docs/loso_walkforward.qmd")
render_qmd("docs/run.qmd")

cat("\n=== STEP 5: Per-season comparison ===\n")
v3_res <- v3b$results |> dplyr::arrange(mae_weibull) |> dplyr::slice(1)
cat("Baseline best spec: k_ref=", v3_res$k_ref,
    "temp=", v3_res$multi_temperature,
    "shift=", v3_res$template_shift, "\n")

best_sid  <- best$spec_id
ckpt_best <- tryCatch(
  readRDS(file.path("data/m1_tune_ckpt_v4", paste0("ckpt_", best_sid, ".rds"))),
  error = function(e) NULL
)
if (!is.null(ckpt_best) && !is.null(ckpt_best$params_df)) {
  suppressPackageStartupMessages(library(flualign))
  for (f in c("R/utils.R","R/m0_retro.R","R/flagIgnition.R")) source(f)
  library(MMWRweek)
  n_weeks_in_start_year <- function(sy)
    52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(sy,"-12-31")))$MMWRweek == 53L)

  allD <- read.csv("data/flu_testing_data.csv") |>
    dplyr::mutate(
      nW_true = n_weeks_in_start_year(seasonstart),
      weekF   = ((week - 27L) %% nW_true) + 1L,
      p = pos_flua / test_flu
    ) |>
    dplyr::filter(!season %in% c("2011-12","2015-16","2020-21","2021-22","2025-26"))

  true_peaks <- allD |>
    dplyr::filter(!is.na(p), test_flu > 0) |>
    dplyr::group_by(season) |>
    dplyr::slice_max(p, n=1L, with_ties=FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(season, true_peak_weekF = weekF)

  per_s <- ckpt_best$params_df |>
    dplyr::filter(!is.na(t_peak), !is.na(iWeek_true)) |>
    dplyr::mutate(pred_peak_weekF = round(t_peak - anchorWeek + iWeek_hat)) |>
    dplyr::left_join(true_peaks, by = "season") |>
    dplyr::filter(!is.na(true_peak_weekF), eval_week <= true_peak_weekF) |>
    dplyr::group_by(season) |>
    dplyr::summarise(
      mae_w = weighted.mean(abs(pred_peak_weekF - true_peak_weekF),
                            w = exp(-(0.1*(eval_week - iWeek_true))^2), na.rm=TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(mae_w))

  cat("\nPer-season Weibull MAE (v4 best, worst first):\n")
  print(per_s, n = 20)
}

cat("\n=== Done ===\n", format(Sys.time()), "\n")
