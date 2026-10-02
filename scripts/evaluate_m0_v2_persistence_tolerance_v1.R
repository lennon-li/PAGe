#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)
source("PAGe/R/stage_contracts.R")
source("PAGe/R/m0_training.R")

baseline_path <- "artifacts/m0-v2-decimal-loso-baseline-r2/loso_result.rds"
campaign_path <- "artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds"
current_path <- "artifacts/m2-v2-live-shadow-2026-27-week11/typed_ab_weekly_revised.csv"
out_dir <- "artifacts/m0-v2-persistence-tolerance-v1"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

baseline <- readRDS(baseline_path)
campaign <- readRDS(campaign_path)
current <- read.csv(current_path, stringsAsFactors = FALSE)

# The SE tolerance only affects the mandatory raw-persistence Boolean. Compute all
# other causal M0-v2 signals once per held-out fold, then scan the persistence
# boundary vectorially. For raw_nondec_n=3, the current and previous standardized
# week-to-week changes must both be >= -tolerance.
signal_rows <- vector("list", nrow(baseline$compare))
for (i in seq_len(nrow(baseline$compare))) {
  season <- as.character(baseline$compare$season[i])
  params <- baseline$folds[[i]]$best_params
  params$use_cls <- FALSE
  params$w_min <- 12L
  params$raw_nondec_n <- 1L
  params$raw_drop_se_tol <- 0
  d <- campaign[campaign$season == season, , drop = FALSE]
  det <- detectIgnitionBySeason_M0v2(
    d, params, verbose = FALSE, iWeek = FALSE, validate_support = FALSE
  )
  z <- det$data
  z$raw_drop_z_prev <- c(NA_real_, head(z$raw_drop_z, -1L))
  z$raw3_min_z <- pmin(z$raw_drop_z, z$raw_drop_z_prev)
  z$base_candidate <- z$cond_win & z$n_hit >= params$N_req
  signal_rows[[i]] <- data.frame(
    season = season,
    weekF = z$weekF,
    baseline_iWeek = baseline$compare$iWeek_hat[i],
    base_candidate = z$base_candidate,
    raw3_min_z = z$raw3_min_z,
    stringsAsFactors = FALSE
  )
}
signals <- do.call(rbind, signal_rows)

tolerances <- seq(0, 3.5, by = 0.01)
scan_rows <- vector("list", length(tolerances))
detail_rows <- vector("list", length(tolerances))
for (ii in seq_along(tolerances)) {
  tol <- tolerances[ii]
  by_season <- do.call(rbind, lapply(split(signals, signals$season), function(z) {
    eligible <- z$base_candidate & is.finite(z$raw3_min_z) & z$raw3_min_z >= -tol
    candidate <- z$weekF[eligible]
    data.frame(
      tolerance_se = tol,
      season = z$season[1L],
      baseline_iWeek = z$baseline_iWeek[1L],
      candidate_iWeek = if (length(candidate)) min(candidate) else NA_real_,
      stringsAsFactors = FALSE
    )
  }))
  by_season$same <- by_season$baseline_iWeek == by_season$candidate_iWeek
  detail_rows[[ii]] <- by_season
  scan_rows[[ii]] <- data.frame(
    tolerance_se = tol,
    all_11_unchanged = all(by_season$same),
    n_unchanged = sum(by_season$same),
    ignition_2017_18 = by_season$candidate_iWeek[by_season$season == "2017-18"],
    stringsAsFactors = FALSE
  )
}
scan <- do.call(rbind, scan_rows)
detail <- do.call(rbind, detail_rows)
good <- scan$tolerance_se[scan$all_11_unchanged]

# Current weekF10 -> weekF11 standardized change and minimum tolerance needed to
# treat the observed decline as sampling-scale stability.
i <- which(current$weekF == 11L)
prev <- i - 1L
p0 <- current$p_A[prev]
p1 <- current$p_A[i]
N0 <- current$N_A[prev]
N1 <- current$N_A[i]
current_se <- sqrt(p0 * (1 - p0) / N0 + p1 * (1 - p1) / N1)
current_z <- (p1 - p0) / current_se
current_min_tol <- max(0, -current_z)

summary <- data.frame(
  safe_min_scanned_se = if (length(good)) min(good) else NA_real_,
  safe_max_scanned_se = if (length(good)) max(good) else NA_real_,
  current_week11_drop_z = current_z,
  current_min_tolerance_se = current_min_tol,
  promoted_tolerance_se = 1.0,
  promoted_inside_safe_interval = length(good) > 0 && 1.0 >= min(good) && 1.0 <= max(good),
  stringsAsFactors = FALSE
)

write.csv(signals, file.path(out_dir, "fold_signals.csv"), row.names = FALSE)
write.csv(scan, file.path(out_dir, "threshold_scan.csv"), row.names = FALSE)
write.csv(detail, file.path(out_dir, "per_season_scan.csv"), row.names = FALSE)
write.csv(summary, file.path(out_dir, "summary.csv"), row.names = FALSE)

print(summary, row.names = FALSE, digits = 8)
stopifnot(summary$promoted_inside_safe_interval)
