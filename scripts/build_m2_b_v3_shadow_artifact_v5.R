#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)
if (!requireNamespace("digest", quietly = TRUE)) stop("Package `digest` required.")
source("scripts/v3_m2_b_runtime_helpers_v5.R")

base_path <- "artifacts/m2-b-v3-shadow-v4/m2_b_v3_shadow_artifact.rds"
m1_path <- "artifacts/m1-b-v3-peak-v10/m1_b_v3_peak_artifact.rds"
timing_path <- "artifacts/v3-joint-timing-contract-v4/timing_contract_v4.csv"
elig_path <- "artifacts/v3-joint-timing-contract-v4/modeling_eligibility_v4.csv"
policy_path <- "governance/v3_b_season_policy_v1.csv"
detector_path <- "artifacts/v3-b-activity-window12-40-v1/B_window12_40_detection.rds"
helper_path <- "scripts/v3_m2_b_runtime_helpers_v5.R"
m1_helper_path <- "scripts/v3_m1_b_runtime_helpers_v9.R"
builder_path <- "scripts/build_m2_b_v3_shadow_artifact_v5.R"
contract_path <- "docs/v3-week12-lower-bound-migration-2026-09-28.md"
out_dir <- "artifacts/m2-b-v3-shadow-v5"
artifact_path <- file.path(out_dir, "m2_b_v3_shadow_artifact.rds")
required <- c(base_path, m1_path, timing_path, elig_path, policy_path,
  detector_path, helper_path, m1_helper_path, builder_path, contract_path)
if (!all(file.exists(required))) stop("Missing M2-B v5 dependency.")
existing <- if (dir.exists(out_dir)) list.files(out_dir, all.files = TRUE,
  no.. = TRUE) else character()
if (length(setdiff(existing, "m2_b_v3_shadow_artifact.rds"))) {
  stop("Refusing non-empty ", out_dir, call. = FALSE)
}
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
sha256_file <- function(path) digest::digest(file = path, algo = "sha256",
  serialize = FALSE)

base <- readRDS(base_path)
m1 <- readRDS(m1_path)
artifact <- base
artifact$version <- .M2_B_V3_VERSION
artifact$status <- .M2_B_V3_STATUS
artifact$production_eligible <- FALSE
artifact$m1_b$path <- m1_path
artifact$m1_b$version <- m1$version
artifact$m1_b$artifact_id <- m1$artifact_id
artifact$m1_b$artifact_sha256 <- sha256_file(m1_path)
artifact$m1_b$library_hash <- m1$library$provenance$library_hash
artifact$activity$params$w_min <- 12L
artifact$activity$params$w_max <- 40L
artifact$activity$detector_path <- detector_path
artifact$activity$detector_sha256 <- sha256_file(detector_path)
artifact$runtime_contract$min_origin_week <- .M2_B_V3_MIN_ORIGIN
artifact$runtime_contract$min_history_observations <-
  .M2_B_V3_MIN_HISTORY_OBSERVATIONS
artifact$runtime_contract$support_rule <- .M2_B_V3_SUPPORT_RULE
artifact$runtime_contract$required_helper <- helper_path
artifact$runtime_contract$required_m1_helper <- m1_helper_path
artifact$provenance$m1_b_artifact_sha256 <- sha256_file(m1_path)
artifact$provenance$timing_contract_sha256 <- sha256_file(timing_path)
artifact$provenance$modeling_eligibility_sha256 <- sha256_file(elig_path)
artifact$provenance$B_season_policy_sha256 <- sha256_file(policy_path)
artifact$provenance$runtime_helper_sha256 <- sha256_file(helper_path)
artifact$provenance$m1_runtime_helper_sha256 <- sha256_file(m1_helper_path)
artifact$provenance$runtime_contract_sha256 <- sha256_file(contract_path)
artifact$provenance$behavioral_source_sha256 <- sha256_file(base_path)
artifact$artifact_id <- digest::digest(.m2b_v3_core(artifact), algo = "sha256")

if (!identical(artifact$state, base$state) ||
    !identical(artifact$shape, base$shape)) {
  stop("STOP: accepted M2-B behavioral payload changed.", call. = FALSE)
}
saveRDS(artifact, artifact_path, version = 3)
validate_m2_b_v3_shadow_artifact(readRDS(artifact_path))
write.csv(data.frame(
  key = c("version", "status", "production_eligible", "artifact_id",
    "artifact_sha256", "behavioral_source_sha256", "min_origin_week",
    "min_history_observations", "support_rule", "activity_window"),
  value = c(artifact$version, artifact$status, "FALSE", artifact$artifact_id,
    sha256_file(artifact_path), sha256_file(base_path), 12L, 3L,
    .M2_B_V3_SUPPORT_RULE, "12-40")
), file.path(out_dir, "metadata.csv"), row.names = FALSE)
manifest <- data.frame(
  role = c("behavioral_source_shadow_v4", "m1_b_v10", "timing_contract_v4",
    "modeling_eligibility_v4", "B_season_policy", "B_activity_detector",
    "runtime_helper_v5", "m1_runtime_helper_v9", "builder_script",
    "week12_contract", "serialized_artifact"),
  path = c(required, artifact_path)
)
manifest$sha256 <- vapply(manifest$path, sha256_file, character(1))
write.csv(manifest, file.path(out_dir, "source_manifest.csv"), row.names = FALSE)
cat("Built ", artifact_path, "\nArtifact ID: ", artifact$artifact_id, "\n",
  sep = "")
