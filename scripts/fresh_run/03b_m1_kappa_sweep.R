#!/usr/bin/env Rscript
# Step 3b — M1 Peak-Prior Kappa Sweep
#
# Evaluates peak_prior_kappa in {Inf, 3.0, 2.0, 1.5} at the locked spec
# (k_ref=25, slope_w=8, temp=0.25, slope_window=6, dynamic_temp=FALSE).
# All other spec dimensions are fixed.
#
# Reads:   data/fresh_m0_tuning.rds
# Writes:  data/fresh_m1_kappa_sweep.rds

source("scripts/fresh_run/00_shared.R")
cat("=== Step 3b: M1 Peak-Prior Kappa Sweep ===\n")
cat("Start:", format(Sys.time()), "\n\n")

allD   <- load_allD(exclude = EXCLUDE_PERM)
fresh_m0 <- readRDS("data/fresh_m0_tuning.rds")
params   <- fresh_m0$best_params

grid <- tibble::tibble(
  k_ref             = 25L,
  multi_temperature = 0.25,
  template_shift    = 0L,
  align_rise_weight = 1.0,
  slope_window      = 6L,
  slope_weight      = 8.0,
  peak_prior_kappa  = c(Inf, 3.0, 2.0, 1.5)
)
cat("Grid:", nrow(grid), "specs (kappa sweep only)\n")
cat("Fixed: k_ref=25, slope_w=8, temp=0.25, slope_window=6, dynamic_temp=FALSE\n\n")

dir.create("data/fresh_m1_kappa_ckpt", showWarnings = FALSE)

tune_res <- tune_m1_alignment(
  allD               = allD,
  params             = params,
  grid               = grid,
  manual_labels      = manual_labels,
  exclude_seasons    = "2015-16",
  n_weeks            = 52L,
  use_multi_template = TRUE,
  ref_method         = "fs",
  checkpoint_dir     = "data/fresh_m1_kappa_ckpt",
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

scores <- readRDS("data/fresh_m1_kappa_ckpt/tune_m1_results.rds")
res    <- dplyr::left_join(grid, scores, by = "spec_id")

cat("\n=== Kappa sweep results ===\n")
print(res |> dplyr::select(peak_prior_kappa, mae_uniform, mae_weibull) |>
      dplyr::arrange(mae_weibull))

saveRDS(list(results = res, grid = grid), "data/fresh_m1_kappa_sweep.rds")
cat("\nSaved: data/fresh_m1_kappa_sweep.rds\n")
cat("End:", format(Sys.time()), "\n")
