#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

source("PAGe/R/data_contract.R")
source("PAGe/R/stage_contracts.R")
source("PAGe/R/m0_training.R")
source("PAGe/R/timing_pipeline_v2.R")

if (!requireNamespace("digest", quietly = TRUE)) stop("Package `digest` required.")

panel_path <- "artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv"
params_path <- "artifacts/v3-a-rule-transfer-to-b-v1/A_aggregated_params.rds"
old_path <- "artifacts/v3-a-rule-transfer-to-b-v1/B_window8_40_detection.rds"
script_path <- "scripts/v3_build_b_activity_window12_40_v1.R"
out_dir <- "artifacts/v3-b-activity-window12-40-v1"
artifact_path <- file.path(out_dir, "B_window12_40_detection.rds")

required <- c(panel_path, params_path, old_path, script_path)
if (!all(file.exists(required))) stop("Missing B detector dependency.", call. = FALSE)
if (dir.exists(out_dir) && length(list.files(out_dir, all.files = TRUE,
  no.. = TRUE))) stop("Refusing non-empty ", out_dir, call. = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

sha256_file <- function(path) {
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

panel <- read.csv(panel_path, check.names = FALSE)
params <- readRDS(params_path)
params$w_min <- 12L
params$w_max <- 40L
b_panel <- data.frame(
  season = panel$season,
  weekF = panel$weekF,
  y = panel$y_B,
  N = panel$N_B,
  p = panel$p_B
)
detector <- detectIgnitionBySeason_M0v2_timing(
  b_panel,
  params = params,
  verbose = FALSE,
  iWeek = FALSE,
  keep_signals = TRUE
)
old <- readRDS(old_path)

old_by <- old$by_season[order(old$by_season$season), ]
new_by <- detector$by_season[order(detector$by_season$season), ]
if (!identical(old_by$season, new_by$season) ||
    !identical(old_by$detection_failed, new_by$detection_failed) ||
    !identical(old_by$iWeek_hat, new_by$iWeek_hat) ||
    !identical(is.na(old_by$iWeek_hatF), is.na(new_by$iWeek_hatF))) {
  stop("STOP: old/new B detector discrete or NA pattern differs.", call. = FALSE)
}
finite <- is.finite(old_by$iWeek_hatF)
if (any(abs(old_by$iWeek_hatF[finite] - new_by$iWeek_hatF[finite]) > 1e-12)) {
  stop("STOP: old/new B detector fractional activity dates differ.", call. = FALSE)
}
if (any(old_by$iWeek_hatF[finite] < 23.964 - 1e-12)) {
  stop("STOP: accepted B activity evidence violates expected lower bound.", call. = FALSE)
}

saveRDS(detector, artifact_path, version = 3)
write.csv(detector$by_season, file.path(out_dir, "B_window12_40_by_season.csv"),
  row.names = FALSE)
write.csv(detector$data, file.path(out_dir, "B_window12_40_signals.csv"),
  row.names = FALSE)
write.csv(as.data.frame(params), file.path(out_dir, "B_window12_40_params.csv"),
  row.names = FALSE)
write.csv(data.frame(
  key = c("detector_version", "activity_semantics", "w_min", "w_max",
    "old_new_equivalent", "fractional_tolerance", "artifact_sha256"),
  value = c("v3-b-activity-window12-40-v1", "A-derived transferred rule",
    12L, 40L, "TRUE", "1e-12", sha256_file(artifact_path))
), file.path(out_dir, "metadata.csv"), row.names = FALSE)
manifest <- data.frame(
  role = c("canonical_panel", "A_derived_params", "accepted_detector",
    "builder_script", "serialized_detector", "by_season", "signals"),
  path = c(panel_path, params_path, old_path, script_path, artifact_path,
    file.path(out_dir, "B_window12_40_by_season.csv"),
    file.path(out_dir, "B_window12_40_signals.csv"))
)
manifest$sha256 <- vapply(manifest$path, sha256_file, character(1))
write.csv(manifest, file.path(out_dir, "source_manifest.csv"), row.names = FALSE)

cat("Built ", artifact_path, "\n", sep = "")
cat("Old/new detector equivalence: TRUE (tolerance <= 1e-12)\n")
