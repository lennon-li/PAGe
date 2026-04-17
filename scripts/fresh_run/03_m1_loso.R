#!/usr/bin/env Rscript
# Step 3 — M1 Alignment LOSO Tuning (fresh run)
# Adapted from scripts/_extended_tune_m1_v7.R
# Key change: output to data/fresh_* paths; reads fresh M0 params.
#
# IMPORTANT: manual_labels here use a -1L offset vs canonical labels.
# This is intentional — _extended_tune_m1_v7.R defines manual_labels_orig
# (different weekF coordinate system) and subtracts 1L. Reproduced exactly.
#
# Reads:   data/fresh_m0_tuning.rds
# Output:  data/fresh_m1_alignment_tuning_v7.rds
#          data/fresh_m1_tune_ckpt_v7/ (resumable checkpoints)
# Compare: data/m1_tune_ckpt_v7/tune_m1_results.rds

source("scripts/fresh_run/00_shared.R")
cat("=== Step 3: M1 Alignment LOSO Tuning v7 (fresh run) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

# ---- M1-specific manual_labels (−1L offset from canonical) ----
manual_labels_orig_v7 <- c(
  "2012-13" = 24L, "2013-14" = 22L, "2014-15" = 17L,
  "2015-16" = 19L, "2016-17" = 21L, "2017-18" = 18L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)
manual_labels_v7 <- manual_labels_orig_v7 - 1L

# ---- Data ----
allD <- load_allD(exclude = EXCLUDE_PERM)
cat("allD:", nrow(allD), "rows |", length(unique(allD$season)), "seasons\n\n")

# ---- M0 params (fresh) ----
fresh_m0 <- readRDS("data/fresh_m0_tuning.rds")
params    <- fresh_m0$best_params
cat("Using fresh M0 best_params:\n"); print(params)
cat("\n")

# ---- Grid ----
grid_v7 <- tidyr::crossing(
  k_ref             = c(25L, 30L, 40L, 50L),
  multi_temperature = 0.25,
  template_shift    = 0L,
  align_rise_weight = 1.0,
  slope_window      = 6L,
  slope_weight      = c(8.0, 12.0, 16.0, 20.0, 30.0)
)
cat("Grid:", nrow(grid_v7), "specs (", length(unique(grid_v7$k_ref)),
    "k_ref x", length(unique(grid_v7$slope_weight)), "slope_weight)\n")
cat("Locked: slope_window=6, template_shift=0, dynamic_temp=FALSE\n\n")

# ---- Run tuning ----
dir.create("data/fresh_m1_tune_ckpt_v7", showWarnings = FALSE)

tune_v7 <- tune_m1_alignment(
  allD               = allD,
  params             = params,
  grid               = grid_v7,
  manual_labels      = manual_labels_v7,
  exclude_seasons    = "2015-16",
  n_weeks            = 52L,
  use_multi_template = TRUE,
  ref_method         = "fs",
  checkpoint_dir     = "data/fresh_m1_tune_ckpt_v7",
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

# ---- Assemble results ----
scores      <- readRDS("data/fresh_m1_tune_ckpt_v7/tune_m1_results.rds")
grid_v7$spec_id <- sprintf("s%03d", seq_len(nrow(grid_v7)))
res         <- dplyr::left_join(grid_v7, scores, by = "spec_id")
saveRDS(list(results = res, grid = grid_v7), "data/fresh_m1_alignment_tuning_v7.rds")
cat("\nSaved: data/fresh_m1_alignment_tuning_v7.rds\n")

# ---- Report ----
piv <- res |>
  dplyr::select(k_ref, slope_weight, mae_weibull) |>
  tidyr::pivot_wider(names_from = slope_weight, values_from = mae_weibull, names_prefix = "wt=")
cat("\nMAE pivot (rows=k_ref, cols=slope_weight):\n")
print(piv)

best <- res[which.min(res$mae_weibull), ]
cat(sprintf("\nFresh best: k_ref=%d, slope_weight=%.0f -> MAE=%.4f\n",
            best$k_ref, best$slope_weight, best$mae_weibull))

# ---- Comparison ----
cat("\n=== Comparison vs gold (data/m1_tune_ckpt_v7/tune_m1_results.rds) ===\n")
gold_ckpt_path <- "data/m1_tune_ckpt_v7/tune_m1_results.rds"
if (file.exists(gold_ckpt_path)) {
  gold_scores <- readRDS(gold_ckpt_path)
  mae_cmp <- dplyr::inner_join(
    gold_scores  |> dplyr::rename(mae_gold  = mae_weibull),
    scores       |> dplyr::rename(mae_fresh = mae_weibull),
    by = "spec_id"
  ) |> dplyr::mutate(delta = mae_fresh - mae_gold)
  cat("Max |MAE delta| (fresh - gold):", round(max(abs(mae_cmp$delta), na.rm = TRUE), 4),
      "(warn if > 0.02)\n")
  gold_best_id  <- mae_cmp$spec_id[which.min(mae_cmp$mae_gold)]
  fresh_best_id <- mae_cmp$spec_id[which.min(mae_cmp$mae_fresh)]
  cat("Gold best spec_id:", gold_best_id,
      "MAE:", round(min(mae_cmp$mae_gold, na.rm = TRUE), 4), "\n")
  cat("Fresh best spec_id:", fresh_best_id,
      "MAE:", round(min(mae_cmp$mae_fresh, na.rm = TRUE), 4), "\n")
  if (gold_best_id != fresh_best_id)
    warning("Best spec_id differs between gold and fresh runs!")
} else {
  cat("Gold checkpoint not found at", gold_ckpt_path, "— skipping comparison\n")
}

cat("\nBoundary check:\n")
cat(sprintf("  k_ref: best=%d, max tested=%d — %s\n",
            best$k_ref, max(res$k_ref, na.rm = TRUE),
            if (best$k_ref == max(res$k_ref, na.rm = TRUE)) "STILL AT BOUNDARY" else "interior"))
cat(sprintf("  slope_weight: best=%.0f, max tested=%.0f — %s\n",
            best$slope_weight, max(res$slope_weight, na.rm = TRUE),
            if (best$slope_weight == max(res$slope_weight, na.rm = TRUE)) "STILL AT BOUNDARY" else "interior"))

cat("\nEnd:", format(Sys.time()), "\n")
