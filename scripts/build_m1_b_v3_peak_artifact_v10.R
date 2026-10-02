#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)
if (!requireNamespace("digest", quietly = TRUE)) stop("Package `digest` required.")
source("scripts/v3_m1_b_runtime_helpers_v9.R")

base_path <- "artifacts/m1-b-v3-peak-v9/m1_b_v3_peak_artifact.rds"
timing_path <- "artifacts/v3-joint-timing-contract-v4/timing_contract_v4.csv"
elig_path <- "artifacts/v3-joint-timing-contract-v4/modeling_eligibility_v4.csv"
detector_path <- "artifacts/v3-b-activity-window12-40-v1/B_window12_40_detection.rds"
helper_path <- "scripts/v3_m1_b_runtime_helpers_v9.R"
builder_path <- "scripts/build_m1_b_v3_peak_artifact_v10.R"
out_dir <- "artifacts/m1-b-v3-peak-v10"
artifact_path <- file.path(out_dir, "m1_b_v3_peak_artifact.rds")
required <- c(base_path, timing_path, elig_path, detector_path, helper_path,
  builder_path)
if (!all(file.exists(required))) stop("Missing M1-B v10 dependency.")
if (dir.exists(out_dir) && length(list.files(out_dir, all.files = TRUE,
  no.. = TRUE))) stop("Refusing non-empty ", out_dir, call. = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
sha256_file <- function(path) digest::digest(file = path, algo = "sha256",
  serialize = FALSE)

base <- readRDS(base_path)
artifact <- base
artifact$version <- "m1-b-v3-peak-v10"
artifact$activity_marker$window <- c(12L, 40L)
artifact$activity_marker$params$w_min <- 12L
artifact$activity_marker$params$w_max <- 40L
artifact$activity_marker$detector_artifact <- detector_path
artifact$activity_marker$detector_artifact_sha256 <- sha256_file(detector_path)
artifact$timing_contract_sha256 <- sha256_file(timing_path)
artifact$season_policy$eligibility_sha256 <- sha256_file(elig_path)
artifact$runtime_contract$required_helper <- helper_path
artifact$provenance$runtime_helper_sha256 <- sha256_file(helper_path)
artifact$provenance$timing_contract_sha256 <- sha256_file(timing_path)
artifact$artifact_id <- compute_m1_b_v3_artifact_id(artifact)

if (!identical(artifact$library, base$library) ||
    !identical(artifact$library$provenance$library_hash,
      base$library$provenance$library_hash)) {
  stop("STOP: M1-B v9 fitted library changed.", call. = FALSE)
}
saveRDS(artifact, artifact_path, version = 3)
validate_m1_b_v3_artifact(readRDS(artifact_path))
write.csv(data.frame(
  key = c("version", "status", "production_eligible", "artifact_id",
    "artifact_sha256", "v9_library_hash", "v10_library_hash", "activity_window"),
  value = c(artifact$version, artifact$status, "FALSE", artifact$artifact_id,
    sha256_file(artifact_path), base$library$provenance$library_hash,
    artifact$library$provenance$library_hash, "12-40")
), file.path(out_dir, "metadata.csv"), row.names = FALSE)
write.csv(data.frame(season = artifact$training_seasons),
  file.path(out_dir, "training_seasons.csv"), row.names = FALSE)
manifest <- data.frame(
  role = c("behavioral_source_v9", "timing_contract_v4",
    "modeling_eligibility_v4", "B_activity_detector", "runtime_helper_v9",
    "builder_script", "serialized_artifact"),
  path = c(required, artifact_path)
)
manifest$sha256 <- vapply(manifest$path, sha256_file, character(1))
write.csv(manifest, file.path(out_dir, "source_manifest.csv"), row.names = FALSE)
cat("Built ", artifact_path, "\nArtifact ID: ", artifact$artifact_id, "\n",
  sep = "")
