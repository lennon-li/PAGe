#!/usr/bin/env Rscript
# Prototype ONLY -- exercises the real-time forecast path end to end using a
# SIMULATED post-ignition continuation. 2026-27 has not ignited yet (weekF 10,
# window opens at weekF 13), so the forecast-producing branch of the pipeline
# has never executed against real data. This splices the REAL observed
# 2026-27 prefix with a continuation derived from a historical season's
# week-over-week growth shape, so the curve is epidemiologically plausible
# rather than invented.
#
# NOTHING produced here is a forecast of the 2026-27 season. Every output is
# labelled simulated and is written under a clearly marked directory.

suppressPackageStartupMessages(library(PAGe))

kit_path <- Sys.getenv(
  "PAGE_KIT_PATH",
  "/home/yeli/repos/PAGe/results/final-kit-2026-27/20260917T220951Z-final-2026-27-asgard/final_kit.rds"
)
real_source <- Sys.getenv("PAGE_REAL_SOURCE", "/home/yeli/hist2026-09-16.RData")
shape_source <- Sys.getenv(
  "PAGE_SHAPE_SOURCE", "/home/yeli/FLU/flu_testing_data_orvt_20260916.csv"
)
shape_season <- Sys.getenv("PAGE_SHAPE_SEASON", "2024-25")
out_dir <- Sys.getenv(
  "PAGE_PROTOTYPE_OUT",
  "/home/yeli/repos/PAGe/results/SIMULATED-prototype-2026-27"
)

cat("== PROTOTYPE: simulated post-ignition 2026-27 ==\n")
cat("kit        :", kit_path, "\n")
cat("real prefix:", real_source, "\n")
cat("shape from :", shape_source, " season", shape_season, "\n\n")

kit <- readRDS(kit_path)
invisible(PAGe::validate_page_kit(kit, mode = "frozen"))

real <- PAGe::page_load_surveillance(real_source, season = "2026-27")
real_prov <- attr(real, "page_source")
real <- real[order(real$weekF), , drop = FALSE]
last_real_week <- max(as.integer(real$weekF))
cat("real observed weeks:", nrow(real), "through weekF", last_real_week,
  sprintf("(%.3f%% positivity)\n", 100 * real$y[nrow(real)] / real$N[nrow(real)])
)

# Historical growth shape, anchored at the same weekF the real data ends on.
shape_all <- PAGe::page_load_surveillance(shape_source, season = shape_season)
shape_all <- shape_all[order(shape_all$weekF), , drop = FALSE]
shape_all$p_obs <- shape_all$y / shape_all$N
anchor <- shape_all$p_obs[shape_all$weekF == last_real_week]
if (!length(anchor) || !is.finite(anchor) || anchor <= 0) {
  stop("Shape season has no usable anchor at weekF ", last_real_week, ".")
}
future <- shape_all[shape_all$weekF > last_real_week, , drop = FALSE]
if (!nrow(future)) stop("Shape season has no weeks after the anchor.")

# Use the historical season's ABSOLUTE weekly positivity for the continuation
# rather than growth ratios anchored on the real prefix: ratio scaling off a
# very low anchor week explodes to implausible peaks (a 60% peak against a
# real-world maximum nearer 35%), which would make the simulated forecast
# values meaningless even though the code path is exercised correctly. A
# small discontinuity at the join is the acceptable cost of a realistic curve.
sim_p <- future$p_obs
cat(sprintf(
  "join: real weekF %d at %.3f%% -> simulated weekF %d at %.3f%%\n",
  last_real_week, 100 * (real$y[nrow(real)] / real$N[nrow(real)]),
  min(future$weekF), 100 * sim_p[1L]
))
sim_N <- round(stats::median(tail(real$N, 5L)))
sim <- data.frame(
  season = "2026-27",
  weekF = as.integer(future$weekF),
  y = as.numeric(round(sim_p * sim_N)),
  N = as.numeric(sim_N),
  week_start_date = max(as.Date(real$week_start_date)) +
    7L * seq_len(nrow(future)),
  stringsAsFactors = FALSE
)
sim$week_end_date <- sim$week_start_date + 6L
sim$simulated <- TRUE

keep <- c("season", "weekF", "y", "N", "week_start_date", "week_end_date")
real_keep <- real[, keep, drop = FALSE]
real_keep$simulated <- FALSE
combined <- rbind(real_keep, sim[, c(keep, "simulated")])
combined <- combined[order(combined$weekF), , drop = FALSE]
rownames(combined) <- NULL

cat("simulated weeks appended:", nrow(sim), "-> weekF",
  min(sim$weekF), "to", max(sim$weekF), "\n"
)
cat("simulated peak positivity:", sprintf("%.2f%%\n\n", 100 * max(sim_p)))

res <- PAGe::page_forecast_now(
  kit,
  source = combined[, c(keep)], season = "2026-27",
  walk_start = 5L, timing_mode = "fractional", verbose = TRUE
)

cat("\n== RESULT (SIMULATED) ==\n")
cat("ignition locked week:", res$ignition$ign_week_locked, "\n")
cat("detection_failed    :", res$ignition$detection_failed, "\n")
preds <- as.data.frame(res$result$m2_preds)
cat("total forecast rows :", nrow(preds), "\n")
if (nrow(preds)) {
  show_cols <- intersect(
    c("eval_week", "h", "target_weekF", "m1_p", "m2_p", "m2_lo", "m2_hi", "forecast_action"),
    names(preds)
  )
  cat("\n-- first forecasts produced --\n")
  print(utils::head(preds[, show_cols], 6), row.names = FALSE)
  cat("\n-- latest origin --\n")
  print(res$forecast[, show_cols], row.names = FALSE)
  # keep_m1 kits freeze the exact all-off M2, which must reproduce M1 exactly.
  delta <- suppressWarnings(max(abs(preds$m2_p - preds$m1_p), na.rm = TRUE))
  cat("\nmax |m2_p - m1_p| =", format(delta, scientific = TRUE),
    "(all-off kit must reproduce M1 bit-for-bit)\n"
  )
}

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(combined, file.path(out_dir, "SIMULATED_input_series.csv"), row.names = FALSE)
if (nrow(preds)) {
  utils::write.csv(preds, file.path(out_dir, "SIMULATED_forecasts.csv"), row.names = FALSE)
}
saveRDS(
  list(
    note = "SIMULATED post-ignition continuation. NOT a 2026-27 forecast.",
    real_prefix_provenance = real_prov,
    shape_season = shape_season, shape_source = shape_source,
    last_real_weekF = last_real_week,
    ignition = res$ignition, source = res$source
  ),
  file.path(out_dir, "SIMULATED_manifest.rds")
)
cat("\nwrote:", out_dir, "\n")
