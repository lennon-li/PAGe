#!/usr/bin/env Rscript

source("PAGe/R/m2_ntrend_shadow.R")

panel_path <- "artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv"
out_dir <- "artifacts/m2-a-ntrend-shadow-v1"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

x <- read.csv(panel_path, stringsAsFactors = FALSE)
d <- data.frame(
  season = x$season,
  weekF = x$weekF,
  y = x$y_A,
  N = x$N_A,
  denominator_regime = x$denominator_regime,
  stringsAsFactors = FALSE
)

fit <- fit_m2_a_ntrend_shadow(
  d,
  windows = 0:4,
  min_origin_week = 13L,
  min_chronological_train_seasons = 3L,
  off_tolerance = 1e-4
)

saveRDS(fit, file.path(out_dir, "m2_a_ntrend_shadow_fit.rds"))
write.csv(fit$loso_summary$overall, file.path(out_dir, "loso_overall.csv"), row.names = FALSE)
write.csv(fit$loso_summary$by_horizon, file.path(out_dir, "loso_by_horizon.csv"), row.names = FALSE)
write.csv(fit$chronological_summary$overall, file.path(out_dir, "chronological_overall.csv"), row.names = FALSE)
write.csv(fit$chronological_summary$by_horizon, file.path(out_dir, "chronological_by_horizon.csv"), row.names = FALSE)
write.csv(fit$loso_scores, file.path(out_dir, "loso_scores.csv"), row.names = FALSE)
write.csv(fit$chronological_scores, file.path(out_dir, "chronological_scores.csv"), row.names = FALSE)
write.csv(fit$coefficient_stability, file.path(out_dir, "coefficient_stability.csv"), row.names = FALSE)
write.csv(fit$promotion_gate$checks, file.path(out_dir, "promotion_checks.csv"), row.names = FALSE)

sel <- fit$selected_window
ss <- aggregate(cbind(abs_error_pp, nll) ~ season + window, fit$loso_scores, mean)
off <- ss[ss$window == 0L, c("season", "abs_error_pp", "nll")]
names(off)[2:3] <- c("off_mae", "off_nll")
z <- merge(ss[ss$window == sel, c("season", "abs_error_pp", "nll")], off, by = "season")
names(z)[2:3] <- c("selected_mae", "selected_nll")
z$delta_mae_pp <- z$selected_mae - z$off_mae
z$delta_nll <- z$selected_nll - z$off_nll
write.csv(z, file.path(out_dir, "selected_vs_off_by_season.csv"), row.names = FALSE)

rs <- aggregate(cbind(abs_error_pp, nll) ~ denominator_regime + window, fit$loso_scores, mean)
write.csv(rs, file.path(out_dir, "loso_by_regime.csv"), row.names = FALSE)

summary <- data.frame(
  selected_window = fit$selected_window,
  promotion_eligible = fit$promotion_gate$eligible,
  loso_mae_relative_gain = fit$promotion_gate$loso_mae_relative_gain,
  chronological_mae_relative_gain = fit$promotion_gate$chronological_mae_relative_gain,
  chronological_nll_relative_gain = fit$promotion_gate$chronological_nll_relative_gain,
  modern_seasons = fit$promotion_gate$modern_seasons,
  stringsAsFactors = FALSE
)
write.csv(summary, file.path(out_dir, "audit_summary.csv"), row.names = FALSE)

cat("selected_window=", fit$selected_window, "\n", sep = "")
cat("promotion_eligible=", fit$promotion_gate$eligible, "\n", sep = "")
print(fit$loso_summary$overall, row.names = FALSE)
print(fit$chronological_summary$overall, row.names = FALSE)
print(fit$promotion_gate$checks, row.names = FALSE)
