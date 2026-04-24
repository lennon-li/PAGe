#!/usr/bin/env Rscript
# Step 6 — Prospective Deployment (fresh run)
# Adapted from docs/prospective_deployment.qmd runtime section.
# Loads the fresh kit, snapshots live data, runs walk-forward pipeline.
#
# Reads:   data/fresh_ref_production.rds
#          data/fresh_m2_production.rds
# Output:  data/fresh_deploy_wf_cache.rds
#          data/fresh_currentD_snapshot.rds
# Compare: data/deploy_wf_cache.rds

source("scripts/fresh_run/00_shared.R")

# prospective_deployment.qmd sources two files from PAGe/R/ (not root R/)
for (f in c("PAGe/R/identifiability.R", "PAGe/R/m1_peak_flags.R")) {
  if (file.exists(f)) source(f) else
    message("Optional file not found (skipping): ", f)
}

cat("=== Step 6: Prospective Deployment (fresh run) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

# ---- Load fresh production kit ----
cat("Loading fresh production kit...\n")
fresh_kit <- load_prospective_kit(
  data_dir    = "data",
  ref_file    = "fresh_ref_production.rds",
  m2_file     = "fresh_m2_production.rds",
  stage1_file = "fresh_m0_tuning.rds"
)
cat("Kit loaded: spec_version =", fresh_kit$m2$spec_version, "\n\n")

# ---- Snapshot current season data ----
cat("Fetching current season data (2025-26)...\n")
currentD_full <- getCurrentD(startWeek = 27L)
currentD      <- dplyr::filter(currentD_full, season == "2025-26")
saveRDS(currentD, "data/fresh_currentD_snapshot.rds")
cat("Snapshot saved: data/fresh_currentD_snapshot.rds\n")
cat("Current season rows:", nrow(currentD), "| weeks:", range(currentD$weekF), "\n\n")

# ---- Run prospective pipeline ----
cat("Running prospective walk-forward pipeline (mode=frozen)...\n")
fresh_wf <- run_prospective_pipeline(
  kit             = fresh_kit,
  current_data    = currentD,
  walk_start      = 5L,
  manual_ign_week = NA_integer_,
  mode            = "frozen",
  verbose         = TRUE
)
attr(fresh_wf, "m2_mode") <- "frozen"
saveRDS(fresh_wf, "data/fresh_deploy_wf_cache.rds")
cat("\nSaved: data/fresh_deploy_wf_cache.rds\n")

# ---- Comparison ----
cat("\n=== Comparison vs gold (data/deploy_wf_cache.rds) ===\n")
# NOTE (D2): deploy_wf_cache.rds was built on 2026-04-16 with pre-B3 code in
# which estimate_season_re_online() silently returned 0 (predict() failed with
# "object 'season' not found" because obs_df lacked GAM columns).  The B3 fix
# populates missing columns so predict() now succeeds, yielding re_hat ≈ −2.03
# at eval_week=19 from pre-ignition observations.  This is the primary driver of
# Max|M2 forecast delta| ≈ 0.22; it is expected and correct — deploy_wf_cache is
# NOT a valid B3-corrected baseline.  See also the kf5-corrected comparison below.
gold_wf <- readRDS("data/deploy_wf_cache.rds")

# Only compare common eval weeks (live data may have grown)
common_weeks <- intersect(
  gold_wf$params_df$eval_week,
  fresh_wf$params_df$eval_week
)
cat("Common eval weeks:", length(common_weeks),
    "| range:", range(common_weeks), "\n")

# M0: ignition week
gold_ign  <- unique(na.omit(gold_wf$params_df$iWeek_hat))
fresh_ign <- unique(na.omit(fresh_wf$params_df$iWeek_hat))
cat("Gold ignition week:", gold_ign, "| Fresh:", fresh_ign, "\n")
if (!setequal(gold_ign, fresh_ign))
  warning("Ignition week mismatch between gold and fresh!")

# M1: tau alignment at common weeks
gold_tau  <- gold_wf$params_df  |>
  dplyr::filter(eval_week %in% common_weeks, !is.na(tau)) |>
  dplyr::select(eval_week, tau)
fresh_tau <- fresh_wf$params_df |>
  dplyr::filter(eval_week %in% common_weeks, !is.na(tau)) |>
  dplyr::select(eval_week, tau)
tau_cmp   <- dplyr::inner_join(gold_tau, fresh_tau, by = "eval_week", suffix = c(".gold", ".fresh")) |>
  dplyr::mutate(delta = tau.fresh - tau.gold)
if (nrow(tau_cmp) > 0)
  cat("Max |tau delta| (fresh - gold):", round(max(abs(tau_cmp$delta), na.rm = TRUE), 3), "\n")

# M2: forecasts at common weeks
if (!is.null(gold_wf$m2_preds) && !is.null(fresh_wf$m2_preds)) {
  gold_m2p  <- gold_wf$m2_preds  |> dplyr::filter(eval_week %in% common_weeks)
  fresh_m2p <- fresh_wf$m2_preds |> dplyr::filter(eval_week %in% common_weeks)
  m2_cmp    <- dplyr::inner_join(
    gold_m2p, fresh_m2p,
    by = c("eval_week", "h"), suffix = c(".gold", ".fresh")
  ) |> dplyr::mutate(delta = m2_p.fresh - m2_p.gold)
  cat("Max |M2 forecast delta|:", round(max(abs(m2_cmp$delta), na.rm = TRUE), 4),
      "(warn if > 0.005)\n")
}

# Holt EMA bias trajectory (dynamic post-hoc bias correction check)
ema_col <- intersect(c("ema_bias", "bias_state"), names(fresh_wf$params_df))
if (length(ema_col) > 0) {
  cat("\nHolt EMA bias trajectory (fresh):\n")
  bias_traj <- fresh_wf$params_df |>
    dplyr::filter(eval_week %in% common_weeks) |>
    dplyr::select(eval_week, bias = dplyr::all_of(ema_col[1]))
  print(bias_traj)

  if (ema_col[1] %in% names(gold_wf$params_df)) {
    gold_bias <- gold_wf$params_df |>
      dplyr::filter(eval_week %in% common_weeks) |>
      dplyr::select(eval_week, bias = dplyr::all_of(ema_col[1]))
    bias_cmp <- dplyr::inner_join(gold_bias, bias_traj, by = "eval_week",
                                  suffix = c(".gold", ".fresh"))
    same_sign <- mean(sign(bias_cmp$bias.gold) == sign(bias_cmp$bias.fresh), na.rm = TRUE)
    cat("Bias same-sign fraction (gold vs fresh):", round(same_sign, 3),
        "(should be ~1.0)\n")
  }
}

# ---- Fair comparison: kf5 spec + current (B3-fixed) code ----
cat("\n=== Fair comparison: kf5 backup kit + current code ===\n")
cat("(Same B3-fixed estimate_season_re_online as fresh; only spec/training differs)\n")
kit_kf5 <- load_prospective_kit(data_dir = "data")
m2_kf5_bk <- readRDS("data/m2_production_v15postfix_kf5_backup.rds")
kit_kf5$m2_production <- m2_kf5_bk
kit_kf5$best_spec     <- m2_kf5_bk$spec
kit_kf5$m2            <- m2_kf5_bk
wf_kf5 <- run_prospective_pipeline(
  kit = kit_kf5, current_data = currentD,
  walk_start = 5L, manual_ign_week = NA_integer_,
  mode = "frozen", verbose = FALSE
)
common_kf5 <- intersect(fresh_wf$params_df$eval_week, wf_kf5$params_df$eval_week)
if (!is.null(fresh_wf$m2_preds) && !is.null(wf_kf5$m2_preds)) {
  cmp_kf5 <- dplyr::inner_join(
    dplyr::filter(fresh_wf$m2_preds, eval_week %in% common_kf5),
    dplyr::filter(wf_kf5$m2_preds,   eval_week %in% common_kf5),
    by = c("eval_week", "h"), suffix = c(".fresh_kf6", ".kf5")
  ) |> dplyr::mutate(delta = m2_p.fresh_kf6 - m2_p.kf5)
  cat("kf5 (B3-corrected) vs fresh kf6 — Max |M2 delta|:",
      round(max(abs(cmp_kf5$delta), na.rm = TRUE), 4),
      "(warn if > 0.05 — indicates spec-driven shift)\n")
  peak_kf5   <- max(wf_kf5$m2_preds$m2_p,    na.rm = TRUE)
  peak_fresh <- max(fresh_wf$m2_preds$m2_p,   na.rm = TRUE)
  cat("Peak m2_p — kf5:", round(peak_kf5, 4), "| fresh kf6:", round(peak_fresh, 4), "\n")
}

cat("\nEnd:", format(Sys.time()), "\n")
