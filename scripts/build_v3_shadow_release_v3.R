#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)
source("scripts/v3_shadow_release_helpers_v1.R")
if (!requireNamespace("digest", quietly = TRUE)) stop("Package `digest` required.")

root <- "artifacts/v3-shadow-release-v3"
dir.create(root, recursive = TRUE, showWarnings = FALSE)
entries <- list()
add <- function(role, path) {
  entries[[length(entries) + 1L]] <<- data.frame(role = role, path = path)
}

for (pair in list(
  c("B_season_policy", "governance/v3_b_season_policy_v1.csv"),
  c("runtime_environment", "governance/v3_runtime_environment_v1.tsv"),
  c("component_inventory", "governance/v3_week12_component_inventory_v1.csv"),
  c("week12_support_summary", "governance/v3_week12_support_summary_v1.csv"),
  c("week12_decision", "docs/v3-week12-lower-bound-migration-2026-09-28.md"),
  c("artifact_storage_policy", "docs/artifact-storage.md"),
  c("M0_A_artifact", "artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/loso_result.rds"),
  c("M1_A_artifact", "artifacts/m1-v2-wmin12-raw3-se1-full-history-v1/m1_v2_stage.rds"),
  c("M2_A_artifact", "artifacts/m2-v2-c2-governed-v1/m2_v2_c2_governed_fit.rds"),
  c("B_detector", "artifacts/v3-b-activity-window12-40-v1/B_window12_40_detection.rds"),
  c("B_detector_manifest", "artifacts/v3-b-activity-window12-40-v1/source_manifest.csv"),
  c("timing_contract_v4", "artifacts/v3-joint-timing-contract-v4/timing_contract_v4.csv"),
  c("timing_eligibility_v4", "artifacts/v3-joint-timing-contract-v4/modeling_eligibility_v4.csv"),
  c("timing_manifest_v4", "artifacts/v3-joint-timing-contract-v4/source_manifest.csv"),
  c("timing_geometry_v4", "artifacts/v3-joint-timing-contract-v4/timing_geometry_v4.csv"),
  c("timing_regimes_v4", "artifacts/v3-joint-timing-contract-v4/season_observation_regimes.csv"),
  c("timing_metadata_v4", "artifacts/v3-joint-timing-contract-v4/contract_metadata.csv"),
  c("B_detector_metadata", "artifacts/v3-b-activity-window12-40-v1/metadata.csv"),
  c("B_detector_by_season", "artifacts/v3-b-activity-window12-40-v1/B_window12_40_by_season.csv"),
  c("M1_B_artifact", "artifacts/m1-b-v3-peak-v10/m1_b_v3_peak_artifact.rds"),
  c("M1_B_manifest", "artifacts/m1-b-v3-peak-v10/source_manifest.csv"),
  c("M2_B_artifact", "artifacts/m2-b-v3-shadow-v5/m2_b_v3_shadow_artifact.rds"),
  c("M2_B_manifest", "artifacts/m2-b-v3-shadow-v5/source_manifest.csv"),
  c("M2_A_week12_predictions", "artifacts/v3-m2-a-early-origin-support-v1/per_origin_predictions.csv"),
  c("M2_B_week12_predictions", "artifacts/v3-m2-b-early-origin-support-v1/per_origin_predictions.csv")
)) add(pair[[1]], pair[[2]])

for (pair in list(
  c("B_detector_builder", "scripts/v3_build_b_activity_window12_40_v1.R"),
  c("timing_contract_builder", "scripts/v3_build_timing_contract_v4.R"),
  c("M1_B_builder", "scripts/build_m1_b_v3_peak_artifact_v10.R"),
  c("M1_B_runtime_helper", "scripts/v3_m1_b_runtime_helpers_v9.R"),
  c("M2_B_builder", "scripts/build_m2_b_v3_shadow_artifact_v5.R"),
  c("M2_B_runtime_helper", "scripts/v3_m2_b_runtime_helpers_v5.R"),
  c("support_summary_builder", "scripts/v3_build_week12_support_summary_v1.R"),
  c("release_helper", "scripts/v3_shadow_release_helpers_v1.R"),
  c("release_builder", "scripts/build_v3_shadow_release_v3.R"),
  c("v2_runner", "2026/run_weekly_shadow_v2.R"),
  c("combined_v3_runner", "2026/run_weekly_shadow_v3_week12_v1.R"),
  c("standalone_M2_B_runner", "2026/run_weekly_m2_b_shadow_v5.R"),
  c("release_launcher", "2026/run_weekly_shadow_release_v5.R"),
  c("ops_helper", "scripts/v3_shadow_ops_helpers_v1.R")
)) add(pair[[1]], pair[[2]])

for (path in sort(list.files("PAGe/R", pattern = "[.]R$", full.names = TRUE))) {
  add("runtime_package_source", gsub("\\\\", "/", path))
}
for (path in c(
  "PAGe/tests/testthat/test-m1-b-v3-shadow-contract-v10.R",
  "PAGe/tests/testthat/test-m2-b-v3-shadow-contract-v5.R",
  "PAGe/tests/testthat/test-v3-week12-lower-bound-runner.R",
  "PAGe/tests/testthat/test-v3-week12-release-v3.R",
  "PAGe/tests/testthat/test-weekly-shadow-release-v5.R",
  "PAGe/tests/testthat/test-timing-contract-v3-governance.R",
  "PAGe/tests/testthat/test-weekly-shadow-v2-runner.R",
  "PAGe/tests/testthat/test-v3-shadow-release-governance.R"
)) add("acceptance_test", path)

spec <- do.call(rbind, entries)
manifest <- .v3_release_manifest_frame(spec$role, spec$path)
release_id <- .v3_release_id_from_manifest(manifest)
final_dir <- file.path(root, release_id)
if (dir.exists(final_dir)) {
  got <- .v3_release_validate(final_dir, expected_id = release_id)
  cat("Release already exists and validates: ", got$release_dir, "\n", sep = "")
  quit(status = 0L)
}
stage <- file.path(root, paste0(".pending-", Sys.getpid(), "-",
  substr(release_id, 1L, 12L)))
if (dir.exists(stage)) stop("Pending release directory already exists: ", stage)
dir.create(stage, recursive = TRUE, showWarnings = FALSE)
.v3_release_write_manifest(manifest, file.path(stage, "release_manifest.tsv"))
writeLines(release_id, file.path(stage, "release_id.txt"), useBytes = TRUE)
write.csv(manifest[manifest$role %in% c("runtime_package_source",
  "B_detector_builder", "timing_contract_builder", "M1_B_builder",
  "M1_B_runtime_helper", "M2_B_builder", "M2_B_runtime_helper",
  "release_builder", "ops_helper", "combined_v3_runner", "standalone_M2_B_runner",
  "release_launcher"), ], file.path(stage, "code_manifest.csv"), row.names = FALSE)
write.csv(data.frame(
  key = c("release_family", "release_id", "created_utc", "git_head",
    "identity_authority", "n_manifest_entries", "n_acceptance_tests"),
  value = c("v3-shadow-release-v3-week12", release_id,
    format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    system2("git", c("rev-parse", "HEAD"), stdout = TRUE),
    "content_addressed_release_manifest", nrow(manifest),
    sum(manifest$role == "acceptance_test"))
), file.path(stage, "release_metadata.csv"), row.names = FALSE)
write.csv(read.csv("governance/v3_week12_component_inventory_v1.csv",
  check.names = FALSE), file.path(stage, "canonical_component_inventory.csv"),
  row.names = FALSE)
.v3_release_validate(stage, expected_id = release_id)
if (!file.rename(stage, final_dir)) stop("Could not publish staged release.")
.v3_release_validate(final_dir, expected_id = release_id)
cat("Built content-addressed release: ", normalizePath(final_dir), "\n",
  "release_id: ", release_id, "\n", sep = "")
