#!/usr/bin/env Rscript

legacy_dir <- "../PAGe/results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/artifacts"
v2_path <- "artifacts/m2-v2-ab-curve-ratio-c123-v1/outer_loso_predictions.csv"
out_dir <- "artifacts/m2-v2-legacy-matched-a-v1"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

legacy_fit <- readRDS(file.path(legacy_dir, "m2_frozen.rds"))
legacy_tuning <- readRDS(file.path(legacy_dir, "m2_tuning_settled.rds"))
expected_legacy_id <- "m2_c1e467afffdadff25087be357fa42d231c3632d776e639bffafb9173ae1e3c54"
if (!identical(legacy_fit$artifact_id, expected_legacy_id)) stop("Legacy M2 artifact identity mismatch.")
if (!identical(legacy_fit$fit$h1$type, "all_off") || !identical(legacy_fit$fit$h2$type, "all_off")) {
  stop("Frozen legacy M2 is not the governed all-off specification.")
}
if (!identical(legacy_tuning$evaluation_label, "cross-fitted")) stop("Legacy M2 evaluation is not cross-fitted.")

legacy <- legacy_fit$m1_train_preds
legacy <- legacy[legacy$forecast_available, c("season", "eval_weekF", "target_weekF", "h", "m1_p_hat")]
names(legacy) <- c("season", "origin_week", "target_week", "horizon", "legacy_m2_pred")
if (anyDuplicated(legacy[c("season", "origin_week", "target_week", "horizon")])) {
  stop("Legacy prediction keys are duplicated.")
}

v2 <- read.csv(v2_path, stringsAsFactors = FALSE)
v2 <- v2[v2$type == "A", c(
  "season", "origin_week", "target_week", "horizon", "p_target", "y_target", "N_target",
  "pred_base", "pred_C2", "timing_available"
)]
if (anyDuplicated(v2[c("season", "origin_week", "target_week", "horizon")])) {
  stop("M2-v2 prediction keys are duplicated.")
}

matched <- merge(legacy, v2, by = c("season", "origin_week", "target_week", "horizon"), all = FALSE)
if (!nrow(matched)) stop("No matched legacy/M2-v2 rows.")

# Verify target-data vintage against the legacy scored rows. The first 10
# seasons are identical; 2025-26 is a known later ORVT/campaign data revision.
legacy_truth <- legacy_tuning$training_rows[, c("season", "eval_weekF", "target_weekF", "h", "y_lead", "N_lead")]
names(legacy_truth) <- c("season", "origin_week", "target_week", "horizon", "legacy_y_target", "legacy_N_target")
matched <- merge(matched, legacy_truth, by = c("season", "origin_week", "target_week", "horizon"), all.x = TRUE)
if (anyNA(matched$legacy_y_target) || anyNA(matched$legacy_N_target)) stop("Legacy truth rows are missing after matched merge.")
matched$target_y_diff <- matched$legacy_y_target - matched$y_target
matched$target_N_diff <- matched$legacy_N_target - matched$N_target
matched$target_vintage_identical <- matched$target_y_diff == 0 & matched$target_N_diff == 0

# Frozen legacy M2 all-off prediction is the supplied M1 probability bit-for-bit.
matched$v2_base_pred <- matched$pred_base
matched$v2_c2_pred <- matched$pred_C2

nll <- function(p, y, N) {
  p <- pmin(pmax(p, 1e-8), 1 - 1e-8)
  -(y * log(p) + (N - y) * log(1 - p)) / N
}
for (m in c("legacy_m2", "v2_base", "v2_c2")) {
  p <- matched[[paste0(m, "_pred")]]
  matched[[paste0(m, "_err")]] <- p - matched$p_target
  matched[[paste0(m, "_abs")]] <- abs(matched[[paste0(m, "_err")]])
  matched[[paste0(m, "_sq")]] <- matched[[paste0(m, "_err")]]^2
  matched[[paste0(m, "_nll")]] <- nll(p, matched$y_target, matched$N_target)
}
write.csv(matched, file.path(out_dir, "matched_predictions.csv"), row.names = FALSE)

metric_per_season <- function(dat, label) {
  do.call(rbind, lapply(split(dat, list(dat$season, dat$horizon), drop = TRUE), function(z) {
    data.frame(
      scope = label,
      season = z$season[1], horizon = z$horizon[1], n = nrow(z),
      legacy_mae_pp = 100 * mean(z$legacy_m2_abs),
      v2_base_mae_pp = 100 * mean(z$v2_base_abs),
      v2_c2_mae_pp = 100 * mean(z$v2_c2_abs),
      legacy_rmse_pp = 100 * sqrt(mean(z$legacy_m2_sq)),
      v2_base_rmse_pp = 100 * sqrt(mean(z$v2_base_sq)),
      v2_c2_rmse_pp = 100 * sqrt(mean(z$v2_c2_sq)),
      legacy_bias_pp = 100 * mean(z$legacy_m2_err),
      v2_base_bias_pp = 100 * mean(z$v2_base_err),
      v2_c2_bias_pp = 100 * mean(z$v2_c2_err),
      legacy_nll = mean(z$legacy_m2_nll),
      v2_base_nll = mean(z$v2_base_nll),
      v2_c2_nll = mean(z$v2_c2_nll),
      timing_availability = mean(z$timing_available),
      stringsAsFactors = FALSE
    )
  }))
}

primary <- matched[matched$season != "2025-26" & matched$target_vintage_identical, ]
if (length(unique(primary$season)) != 10L) stop("Primary identical-vintage comparison does not contain exactly 10 seasons.")
per_primary <- metric_per_season(primary, "historical_10_identical_target_vintage")
per_all <- metric_per_season(matched, "all_11_scored_on_current_target_vintage")
per <- rbind(per_primary, per_all)
write.csv(per, file.path(out_dir, "per_season_metrics.csv"), row.names = FALSE)

summarize <- function(per_dat) {
  do.call(rbind, lapply(split(per_dat, per_dat$horizon), function(z) {
    data.frame(
      scope = z$scope[1], horizon = z$horizon[1], n_seasons = nrow(z), n_rows = sum(z$n),
      legacy_mae_pp = mean(z$legacy_mae_pp),
      v2_base_mae_pp = mean(z$v2_base_mae_pp),
      v2_c2_mae_pp = mean(z$v2_c2_mae_pp),
      c2_vs_legacy_relative_mae_gain = 1 - mean(z$v2_c2_mae_pp) / mean(z$legacy_mae_pp),
      c2_vs_v2_base_relative_mae_gain = 1 - mean(z$v2_c2_mae_pp) / mean(z$v2_base_mae_pp),
      legacy_rmse_pp = mean(z$legacy_rmse_pp),
      v2_base_rmse_pp = mean(z$v2_base_rmse_pp),
      v2_c2_rmse_pp = mean(z$v2_c2_rmse_pp),
      legacy_bias_pp = mean(z$legacy_bias_pp),
      v2_base_bias_pp = mean(z$v2_base_bias_pp),
      v2_c2_bias_pp = mean(z$v2_c2_bias_pp),
      legacy_nll = mean(z$legacy_nll),
      v2_base_nll = mean(z$v2_base_nll),
      v2_c2_nll = mean(z$v2_c2_nll),
      seasons_c2_better_than_legacy_mae = sum(z$v2_c2_mae_pp < z$legacy_mae_pp),
      seasons_c2_worse_than_legacy_mae = sum(z$v2_c2_mae_pp > z$legacy_mae_pp),
      stringsAsFactors = FALSE
    )
  }))
}
summary <- rbind(
  summarize(per_primary),
  summarize(per_all)
)
write.csv(summary, file.path(out_dir, "summary.csv"), row.names = FALSE)

paired <- do.call(rbind, lapply(split(per, list(per$scope, per$horizon), drop = TRUE), function(z) {
  d <- z$v2_c2_mae_pp - z$legacy_mae_pp
  nz <- d[d != 0]
  data.frame(
    scope = z$scope[1], horizon = z$horizon[1], n_seasons = length(d),
    mean_c2_minus_legacy_mae_pp = mean(d),
    median_c2_minus_legacy_mae_pp = median(d),
    seasons_c2_better = sum(d < 0),
    seasons_c2_worse = sum(d > 0),
    exact_sign_test_p = if (length(nz)) stats::binom.test(sum(nz < 0), length(nz), p = 0.5)$p.value else NA_real_,
    worst_c2_minus_legacy_mae_pp = max(d),
    best_c2_minus_legacy_mae_pp = min(d),
    stringsAsFactors = FALSE
  )
}))
rownames(paired) <- NULL
write.csv(paired, file.path(out_dir, "paired_season_summary.csv"), row.names = FALSE)

vintage <- do.call(rbind, lapply(split(matched, matched$season), function(z) data.frame(
  season = z$season[1], n = nrow(z),
  y_mismatch_rows = sum(z$target_y_diff != 0),
  N_mismatch_rows = sum(z$target_N_diff != 0),
  sum_abs_y_diff = sum(abs(z$target_y_diff)),
  sum_abs_N_diff = sum(abs(z$target_N_diff)),
  stringsAsFactors = FALSE
)))
write.csv(vintage, file.path(out_dir, "target_vintage_audit.csv"), row.names = FALSE)

provenance <- data.frame(
  key = c(
    "legacy_artifact_id", "legacy_family", "legacy_governed_spec", "legacy_evaluation_label",
    "legacy_prediction_identity", "v2_prediction_source", "primary_scope", "sensitivity_scope"
  ),
  value = c(
    legacy_fit$artifact_id, legacy_fit$family,
    "h1:i0_kz0_ku0_kd0|h2:i0_kz0_ku0_kd0", legacy_tuning$evaluation_label,
    "frozen all-off M2 == saved cross-fitted m1_p_hat bit-for-bit",
    v2_path,
    "10 historical seasons with identical legacy/current target counts; exact matched keys; equal season weighting; exchangeable training snapshots still differ because 2025-26 was revised after the legacy final kit",
    "all 11 seasons scored on current M2-v2 target counts; 2025-26 target-data vintage differs from legacy final kit"
  ), stringsAsFactors = FALSE
)
write.csv(provenance, file.path(out_dir, "provenance.csv"), row.names = FALSE)

cat("MATCHED A-ONLY LEGACY VS M2-V2\n")
print(summary, row.names = FALSE, digits = 6)
cat("\nPAIRED SEASON SUMMARY\n")
print(paired, row.names = FALSE, digits = 6)
cat("\nTARGET VINTAGE AUDIT\n")
print(vintage, row.names = FALSE)
