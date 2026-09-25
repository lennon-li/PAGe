#!/usr/bin/env Rscript

source("PAGe/R/m1_v2.R")
source("PAGe/R/m2_v2_research.R")
source("PAGe/R/m2_v2_c2_governed.R")

artifact_dir <- "artifacts/m2-v2-c2-governed-v1"
out_dir <- "artifacts/m2-v2-c2-governed-shadow-v1"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
manifest <- jsonlite::fromJSON(file.path(artifact_dir, "m2_v2_c2_governed_v1.json"), simplifyVector = FALSE)
fit_path <- manifest$fitted_rds
if (!identical(digest::digest(file = fit_path, algo = "sha256"), manifest$fitted_rds_sha256)) {
  stop("Governed fit RDS hash does not match artifact manifest.")
}
artifact <- readRDS(fit_path)
validate_m2_v2_c2_governed_artifact(artifact)
if (!identical(artifact$artifact_id, manifest$artifact_id)) stop("Artifact ID mismatch.")

season <- "shadow-2026-27"
week <- 18:24
weekly <- data.frame(
  season = season, weekF = week,
  y_A = c(35, 42, 48, 56, 65, 74, 82), N_A = 1000,
  y_B = c(10, 15, 20, 25, 30, 32, 35), N_B = 400,
  denominator_regime = "orvt_type_specific"
)
weekly$p_A <- weekly$y_A / weekly$N_A
weekly$p_B <- weekly$y_B / weekly$N_B
a <- list(
  version = "m1-v2-to-m2-v1", m1_v2_artifact_id = "shadow-a-v1", season = season,
  state = "active", origin_week = 24, asof_boundary = 25,
  activation_week = 19, weeks_elapsed_since_activation = 6,
  weeks_to_calibrated_peak = 3,
  raw_peak_posterior = data.frame(peak_week_decimal = c(27, 28, 29), probability = c(.2, .6, .2)),
  raw_peak_mean = 28, calibrated_peak_mean = 28, calibrated_mean_is_future = TRUE,
  raw_peak_q05 = 27, raw_peak_q95 = 29, calibrated_peak_q05 = 27,
  calibrated_peak_q95 = 29, peak_q05 = 27, peak_q95 = 29,
  interval_width_90 = 2, prob_peak_passed = .1,
  prob_peak_within_1w = .2, prob_peak_within_2w = .4,
  prob_peak_within_3w = .6, locked_peak_week = NA_real_,
  locked_at_origin = NA_real_, calibration_offset_week = 0
)
validate_m1_v2_handoff(a)
b <- new_m2_v2_b_soft_timing_handoff(
  season, 24, 29,
  source_artifact_id = "shadow-b-v1",
  interval_width_90 = 3, prob_peak_passed = .15
)
review_path <- file.path(out_dir, "synthetic_review_decision.json")
jsonlite::write_json(list(
  status = "reviewed_open", decision = "open",
  policy_version = artifact$contract$b_gate_policy$version,
  review_id = "synthetic-review-token",
  note = "synthetic runtime contract fixture; not an actual governance approval"
), review_path, auto_unbox = TRUE, pretty = TRUE)
review <- new_m2_v2_b_gate_review(review_path)
closed <- run_m2_v2_c2_governed_runtime(artifact, weekly, 24, a, b)
opened <- run_m2_v2_c2_governed_runtime(artifact, weekly, 24, a, b, review)
missing <- run_m2_v2_c2_governed_runtime(artifact, weekly, 24)
failed_b <- new_m2_v2_b_soft_timing_handoff(
  season, 23, 29,
  source_artifact_id = "shadow-b-v1"
)
failed <- run_m2_v2_c2_governed_runtime(artifact, weekly, 24, a, failed_b, review)

pred <- rbind(
  transform(closed$predictions, scenario = "gate_closed"),
  transform(opened$predictions, scenario = "reviewed_gate_open"),
  transform(missing$predictions, scenario = "timing_missing"),
  transform(failed$predictions, scenario = "b_timing_failure")
)
write.csv(pred, file.path(out_dir, "predictions.csv"), row.names = FALSE)
pick <- function(x, type, h) x[x$type == type & x$horizon == h, , drop = FALSE]
checks <- data.frame(
  check = c(
    "A_h1_and_h2_use_C2_when_A_timing_available",
    "B_h1_is_exact_B1_when_gate_closed",
    "B_h2_is_exact_B1_until_reviewed_gate_opens",
    "B_h2_uses_C2_after_reviewed_gate_opens",
    "missing_A_timing_exact_baseline",
    "missing_B_timing_exact_baseline",
    "failed_B_timing_exact_baseline",
    "wrong_review_version_keeps_B2_baseline",
    "artifact_identity_matches_manifest",
    "output_contract_columns_present"
  ), passed = FALSE, stringsAsFactors = FALSE
)
checks$passed[1] <- all(vapply(1:2, function(h) pick(opened$predictions, "A", h)$c2_applied, logical(1)))
checks$passed[2] <- identical(
  pick(closed$predictions, "B", 1)$pred_selected,
  pick(closed$predictions, "B", 1)$pred_baseline
)
checks$passed[3] <- identical(
  pick(closed$predictions, "B", 2)$pred_selected,
  pick(closed$predictions, "B", 2)$pred_baseline
)
checks$passed[4] <- isTRUE(pick(opened$predictions, "B", 2)$c2_applied)
checks$passed[5] <- all(pick(missing$predictions, "A", 2)$pred_selected ==
  pick(missing$predictions, "A", 2)$pred_baseline)
checks$passed[6] <- all(pick(missing$predictions, "B", 2)$pred_selected ==
  pick(missing$predictions, "B", 2)$pred_baseline)
checks$passed[7] <- all(pick(failed$predictions, "B", 2)$pred_selected ==
  pick(failed$predictions, "B", 2)$pred_baseline)
wrong_path <- file.path(out_dir, "synthetic_wrong_review_decision.json")
jsonlite::write_json(
  list(
    status = "reviewed_open", decision = "open",
    policy_version = "wrong-version", review_id = "wrong-review"
  ),
  wrong_path,
  auto_unbox = TRUE
)
wrong_review <- tryCatch(new_m2_v2_b_gate_review(wrong_path), error = function(e) NULL)
wrong <- run_m2_v2_c2_governed_runtime(artifact, weekly, 24, a, b, wrong_review)
checks$passed[8] <- identical(
  pick(wrong$predictions, "B", 2)$pred_selected,
  pick(wrong$predictions, "B", 2)$pred_baseline
)
checks$passed[9] <- identical(opened$model_artifact_id, manifest$artifact_id)
checks$passed[10] <- all(artifact$contract$output_contract$required_columns %in% names(pred))
write.csv(checks, file.path(out_dir, "contract_checks.csv"), row.names = FALSE)
write.csv(data.frame(
  artifact_id = artifact$artifact_id,
  training_seasons = paste(artifact$training_seasons, collapse = ";"),
  replay_season = season,
  replay_kind = "synthetic contract replay; no performance claim",
  check_count = nrow(checks), passed_count = sum(checks$passed),
  stringsAsFactors = FALSE
), file.path(out_dir, "identity_and_metrics.csv"), row.names = FALSE)
if (!all(checks$passed)) {
  print(checks[!checks$passed, ], row.names = FALSE)
  stop("Governed M2-v2 C2 runtime replay failed.")
}
cat("Governed M2-v2 C2 shadow replay:", sum(checks$passed), "/", nrow(checks), "checks passed\n")
cat("artifact_id:", artifact$artifact_id, "\n")
