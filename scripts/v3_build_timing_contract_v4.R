#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)
if (!requireNamespace("digest", quietly = TRUE)) stop("Package `digest` required.")

old_dir <- "artifacts/v3-joint-timing-contract-v3"
detector_path <- "artifacts/v3-b-activity-window12-40-v1/B_window12_40_detection.rds"
builder_path <- "scripts/v3_build_timing_contract_v4.R"
out_dir <- "artifacts/v3-joint-timing-contract-v4"
required <- c(file.path(old_dir, "timing_contract_v3.csv"),
  file.path(old_dir, "modeling_eligibility_v3.csv"), detector_path, builder_path)
if (!all(file.exists(required))) stop("Missing timing-contract v4 dependency.")
if (dir.exists(out_dir) && length(list.files(out_dir, all.files = TRUE,
  no.. = TRUE))) stop("Refusing non-empty ", out_dir, call. = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

sha256_file <- function(path) digest::digest(file = path, algo = "sha256",
  serialize = FALSE)
old_truth <- read.csv(file.path(old_dir, "timing_contract_v3.csv"),
  check.names = FALSE)
old_elig <- read.csv(file.path(old_dir, "modeling_eligibility_v3.csv"),
  check.names = FALSE)
det <- readRDS(detector_path)$by_season
det <- det[match(old_truth$season, det$season), ]
if (!identical(is.na(old_truth$B_activity_weekF), is.na(det$iWeek_hatF)) ||
    any(abs(old_truth$B_activity_weekF[is.finite(old_truth$B_activity_weekF)] -
      det$iWeek_hatF[is.finite(old_truth$B_activity_weekF)]) > 1e-12)) {
  stop("STOP: timing v4 detector values differ from reviewed v3 truth.")
}

truth <- old_truth
truth$B_activity_source <- "A_rule_transfer_w12_40"
elig <- old_elig
numeric_cols <- names(old_truth)[vapply(old_truth, is.numeric, logical(1))]
for (name in numeric_cols) {
  if (!isTRUE(all.equal(truth[[name]], old_truth[[name]], tolerance = 1e-12,
    check.attributes = TRUE))) stop("STOP: timing numeric truth changed: ", name)
}
if (!identical(elig, old_elig)) stop("STOP: timing eligibility changed.")
if (!identical(truth$B_activity_status[truth$season == "2018-19"],
    "no_meaningful_activity")) stop("2018-19 no-event policy changed.")
if (elig$M2_B_state_eligible[elig$season == "2019-20"] ||
    elig$M1_B_training_eligible[elig$season == "2019-20"]) {
  stop("2019-20 pandemic exclusion changed.")
}

timing_path <- file.path(out_dir, "timing_contract_v4.csv")
elig_path <- file.path(out_dir, "modeling_eligibility_v4.csv")
geometry_path <- file.path(out_dir, "timing_geometry_v4.csv")
regimes_path <- file.path(out_dir, "season_observation_regimes.csv")
write.csv(truth, timing_path, row.names = FALSE)
write.csv(elig, elig_path, row.names = FALSE)
geometry <- read.csv(file.path(old_dir, "timing_geometry_v3.csv"), check.names = FALSE)
write.csv(geometry, geometry_path, row.names = FALSE)
file.copy(file.path(old_dir, "season_observation_regimes.csv"), regimes_path)
write.csv(data.frame(
  key = c("contract_version", "B_activity_semantics", "A_window", "B_window",
    "reviewed_truth_equal_v3", "eligibility_equal_v3", "timing_contract_sha256",
    "modeling_eligibility_sha256"),
  value = c("v3-timing-contract-v4", "A_rule_transfer_w12_40", "12-26",
    "12-40", "TRUE", "TRUE", sha256_file(timing_path), sha256_file(elig_path))
), file.path(out_dir, "contract_metadata.csv"), row.names = FALSE)
manifest <- data.frame(
  role = c("accepted_timing_v3", "accepted_eligibility_v3", "B_activity_detector",
    "builder_script", "timing_contract_v4", "modeling_eligibility_v4",
    "timing_geometry_v4", "season_observation_regimes"),
  path = c(required, timing_path, elig_path, geometry_path, regimes_path)
)
manifest$sha256 <- vapply(manifest$path, sha256_file, character(1))
write.csv(manifest, file.path(out_dir, "source_manifest.csv"), row.names = FALSE)
cat("Built timing contract v4; truth and eligibility equal v3.\n")
