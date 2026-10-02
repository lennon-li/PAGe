#!/usr/bin/env Rscript

source("PAGe/R/m1_v2.R")
source("PAGe/R/m2_v2_research.R")

fit_path <- "artifacts/m2-v2-c2-research-v1/m2_v2_c2_research_fit.rds"
out_dir <- "artifacts/m2-v2-c2-research-runtime-shadow-v1"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
fit <- readRDS(fit_path)
validate_m2_v2_c2_research_fit(fit)

make_weekly <- function(season = "shadow-2026-27", b_epidemic = TRUE,
                        denominator_regime = "orvt_type_specific") {
  week <- 18:24
  N_A <- rep(1000, length(week))
  y_A <- c(35, 42, 48, 56, 65, 74, 82)
  N_B <- rep(400, length(week))
  y_B <- if (b_epidemic) c(10, 15, 20, 25, 30, 32, 35) else c(1, 1, 2, 2, 3, 3, 4)
  data.frame(
    season = season, weekF = week,
    y_A = y_A, N_A = N_A, p_A = y_A / N_A,
    y_B = y_B, N_B = N_B, p_B = y_B / N_B,
    denominator_regime = denominator_regime,
    stringsAsFactors = FALSE
  )
}

make_a_handoff <- function(season = "shadow-2026-27", origin = 24) {
  asof <- origin + 1
  out <- list(
    version = "m1-v2-to-m2-v1",
    m1_v2_artifact_id = "shadow-a-m1-v2-artifact",
    season = season,
    state = "active",
    origin_week = origin,
    asof_boundary = asof,
    activation_week = origin - 5,
    weeks_elapsed_since_activation = 6,
    weeks_to_calibrated_peak = 3,
    raw_peak_posterior = data.frame(
      peak_week_decimal = c(asof + 2, asof + 3, asof + 4),
      probability = c(.2, .6, .2)
    ),
    raw_peak_mean = asof + 3,
    calibrated_peak_mean = asof + 3,
    calibrated_mean_is_future = TRUE,
    raw_peak_q05 = asof + 2,
    raw_peak_q95 = asof + 4,
    calibrated_peak_q05 = asof + 2,
    calibrated_peak_q95 = asof + 4,
    peak_q05 = asof + 2,
    peak_q95 = asof + 4,
    interval_width_90 = 2,
    prob_peak_passed = .1,
    prob_peak_within_1w = .2,
    prob_peak_within_2w = .4,
    prob_peak_within_3w = .6,
    locked_peak_week = NA_real_,
    locked_at_origin = NA_real_,
    calibration_offset_week = 0
  )
  validate_m1_v2_handoff(out)
  out
}

collect_case <- function(name, result) {
  p <- result$predictions
  p$scenario <- name
  p$model_artifact_id_shadow <- result$model_artifact_id
  p$b_gate_active_shadow <- result$b_gate$active
  p$b_gate_status_shadow <- result$b_gate$status
  p
}

season <- "shadow-2026-27"
weekly_active <- make_weekly(season, TRUE)
a <- make_a_handoff(season, 24)
b <- new_m2_v2_b_soft_timing_handoff(
  season = season, origin_week = 24, peak_mean = 29,
  source_artifact_id = "shadow-b-soft-timing",
  interval_width_90 = 3, prob_peak_passed = .15
)
active <- run_m2_v2_c2_research_runtime(fit, weekly_active, 24, a, b)

weekly_inactive <- make_weekly(season, FALSE)
inactive <- run_m2_v2_c2_research_runtime(fit, weekly_inactive, 24, a, b)
missing <- run_m2_v2_c2_research_runtime(fit, weekly_active, 24, NULL, NULL)

b_wrong_origin <- new_m2_v2_b_soft_timing_handoff(
  season = season, origin_week = 23, peak_mean = 29,
  source_artifact_id = "shadow-b-soft-timing"
)
failed <- run_m2_v2_c2_research_runtime(fit, weekly_active, 24, a, b_wrong_origin)

pred <- do.call(rbind, list(
  collect_case("active_A_B", active),
  collect_case("inactive_B_gate", inactive),
  collect_case("missing_timing", missing),
  collect_case("B_origin_mismatch", failed)
))
rownames(pred) <- NULL
write.csv(pred, file.path(out_dir, "shadow_predictions.csv"), row.names = FALSE)

active_p <- active$predictions
inactive_p <- inactive$predictions
missing_p <- missing$predictions
failed_p <- failed$predictions
checks <- data.frame(
  check = c(
    "active_A_h1_applied", "active_A_h2_applied",
    "active_B_h1_exact_baseline", "active_B_h2_applied",
    "inactive_B_h2_exact_baseline", "missing_A_exact_baseline",
    "missing_B_exact_baseline", "failed_B_h2_exact_baseline",
    "cross_type_B_handoff_rejected", "training_season_rejected",
    "unknown_denominator_regime_rejected", "recent_week_gap_rejected"
  ),
  passed = FALSE,
  stringsAsFactors = FALSE
)
checks$passed[1] <- active_p$c2_applied[active_p$type == "A" & active_p$horizon == 1]
checks$passed[2] <- active_p$c2_applied[active_p$type == "A" & active_p$horizon == 2]
checks$passed[3] <- with(active_p[active_p$type == "B" & active_p$horizon == 1, ],
                         !c2_applied && identical(pred_selected, pred_baseline) &&
                           fallback_reason == "policy_b_h1_baseline")
checks$passed[4] <- active_p$c2_applied[active_p$type == "B" & active_p$horizon == 2]
checks$passed[5] <- with(inactive_p[inactive_p$type == "B" & inactive_p$horizon == 2, ],
                         !c2_applied && identical(pred_selected, pred_baseline) &&
                           fallback_reason == "b_timing_gate_inactive")
checks$passed[6] <- all(with(missing_p[missing_p$type == "A", ],
                             !c2_applied & pred_selected == pred_baseline &
                               fallback_reason == "type_timing_unavailable"))
checks$passed[7] <- all(with(missing_p[missing_p$type == "B", ],
                             !c2_applied & pred_selected == pred_baseline))
checks$passed[8] <- with(failed_p[failed_p$type == "B" & failed_p$horizon == 2, ],
                         !c2_applied && identical(pred_selected, pred_baseline) &&
                           fallback_reason == "type_timing_failed")

cross <- b
cross$type <- "A"
checks$passed[9] <- inherits(try(
  run_m2_v2_c2_research_runtime(fit, weekly_active, 24, a, cross), silent = TRUE
), "try-error")

leaked <- weekly_active
leaked$season <- fit$training_seasons[[length(fit$training_seasons)]]
checks$passed[10] <- inherits(try(
  run_m2_v2_c2_research_runtime(fit, leaked, 24, NULL, NULL), silent = TRUE
), "try-error")

unknown <- weekly_active
unknown$denominator_regime <- "unknown_future_regime"
checks$passed[11] <- inherits(try(
  run_m2_v2_c2_research_runtime(fit, unknown, 24, NULL, NULL), silent = TRUE
), "try-error")

gapped <- weekly_active[weekly_active$weekF != 23, ]
checks$passed[12] <- inherits(try(
  run_m2_v2_c2_research_runtime(fit, gapped, 24, NULL, NULL), silent = TRUE
), "try-error")

write.csv(checks, file.path(out_dir, "contract_checks.csv"), row.names = FALSE)
identity <- data.frame(
  key = c("model_artifact_id", "data_id", "shape_id", "training_seasons", "shadow_season", "performance_claim"),
  value = c(
    fit$artifact_id, fit$data_id, fit$shape_id,
    paste(fit$training_seasons, collapse = ";"), season,
    "none: synthetic future-season contract replay only"
  ), stringsAsFactors = FALSE
)
write.csv(identity, file.path(out_dir, "identity.csv"), row.names = FALSE)

if (!all(checks$passed)) {
  print(checks[!checks$passed, ], row.names = FALSE)
  stop("M2-v2 research runtime shadow contract replay failed.")
}
cat("M2-v2 research runtime shadow contract replay: 12/12 checks passed\n")
cat("model_artifact_id:", fit$artifact_id, "\n")
print(pred[, c("scenario", "type", "horizon", "c2_applied", "fallback_reason",
               "pred_baseline", "pred_selected", "b_gate_status")], row.names = FALSE)
