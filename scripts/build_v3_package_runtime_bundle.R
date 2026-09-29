#!/usr/bin/env Rscript

# Deterministically project canonical PAGe v3 model artifacts into a package-safe
# runtime bundle. The projection removes raw historical outcome/test-count frames
# that are unnecessary for inference while retaining source artifact identity.

release_id <- "5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b"
out_dir <- file.path("PAGe", "inst", "models", "v3-week12")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

source_paths <- c(
  m0_a = "artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/loso_result.rds",
  m1_a = "artifacts/m1-v2-wmin12-raw3-se1-full-history-v1/m1_v2_stage.rds",
  m2_a = "artifacts/m2-v2-c2-governed-v1/m2_v2_c2_governed_fit.rds",
  m1_b = "artifacts/m1-b-v3-peak-v10/m1_b_v3_peak_artifact.rds",
  m2_b = "artifacts/m2-b-v3-shadow-v5/m2_b_v3_shadow_artifact.rds"
)

sha256 <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)
runtime_sha <- function(x) digest::digest(x, algo = "sha256")

source_sha <- vapply(source_paths, sha256, character(1L))

# M0/M1 artifacts already contain model-selection/posterior summaries rather than
# raw surveillance count frames, so preserve their exact canonical bytes.
file.copy(source_paths[["m0_a"]], file.path(out_dir, "m0_a.rds"), overwrite = TRUE)
file.copy(source_paths[["m1_a"]], file.path(out_dir, "m1_a.rds"), overwrite = TRUE)
file.copy(source_paths[["m1_b"]], file.path(out_dir, "m1_b.rds"), overwrite = TRUE)

m2a_src <- readRDS(source_paths[["m2_a"]])
m2a_runtime <- structure(list(
  version = "page-v3-m2a-runtime-v1",
  source_version = m2a_src$contract$model_version,
  source_artifact_id = m2a_src$artifact_id,
  source_sha256 = source_sha[["m2_a"]],
  training_seasons = as.character(m2a_src$training_seasons),
  baseline_coefficients_A = unclass(m2a_src$fit$baseline_coefficients$A),
  denominator_regimes = as.character(m2a_src$contract$denominator_regime_metadata$levels),
  runtime_contract = list(
    min_origin_week = 12L,
    horizons = 1:2,
    route = "exact_A1_state",
    stabilized_probability = "(y+0.5)/(N+1)",
    growth_features = c("growth1", "growth2")
  )
), class = "page_v3_m2a_runtime")
m2a_runtime$runtime_projection_id <- runtime_sha(m2a_runtime)
saveRDS(m2a_runtime, file.path(out_dir, "m2_a.rds"), version = 3)

m2b_src <- readRDS(source_paths[["m2_b"]])
m2b_runtime <- structure(list(
  version = "page-v3-m2b-runtime-v1",
  source_version = m2b_src$version,
  source_artifact_id = m2b_src$artifact_id,
  source_sha256 = source_sha[["m2_b"]],
  status = m2b_src$status,
  production_eligible = m2b_src$production_eligible,
  season_policy = m2b_src$season_policy,
  state = list(
    coefficients = unclass(stats::coef(m2b_src$state$model)),
    training_seasons = as.character(m2b_src$state$training_seasons),
    ledger_sha256 = as.character(m2b_src$state$ledger_sha256)
  ),
  m1_b = list(
    version = as.character(m2b_src$m1_b$version),
    artifact_sha256 = as.character(m2b_src$m1_b$artifact_sha256),
    library_hash = as.character(m2b_src$m1_b$library_hash),
    artifact_id = as.character(m2b_src$m1_b$artifact_id)
  ),
  activity = list(
    semantics = as.character(m2b_src$activity$semantics),
    params = m2b_src$activity$params,
    source_sha256 = as.character(m2b_src$activity$source_sha256),
    detector_sha256 = as.character(m2b_src$activity$detector_sha256)
  ),
  shape = list(
    grid = m2b_src$shape$grid[, c("season", "type", "tau", "p_norm"), drop = FALSE],
    tau_grid = as.numeric(m2b_src$shape$tau_grid),
    A_seasons = as.character(m2b_src$shape$A_seasons),
    B_seasons = as.character(m2b_src$shape$B_seasons),
    pooled_weight = as.numeric(m2b_src$shape$pooled_weight),
    B_weight = as.numeric(m2b_src$shape$B_weight),
    eta = as.numeric(m2b_src$shape$eta)
  ),
  runtime_contract = m2b_src$runtime_contract,
  provenance = list(
    timing_contract_sha256 = as.character(m2b_src$provenance$timing_contract_sha256),
    modeling_eligibility_sha256 = as.character(m2b_src$provenance$modeling_eligibility_sha256)
  )
), class = "page_v3_m2b_runtime")
m2b_runtime$runtime_projection_id <- runtime_sha(m2b_runtime)
saveRDS(m2b_runtime, file.path(out_dir, "m2_b.rds"), version = 3)

files <- c(m0_a = "m0_a.rds", m1_a = "m1_a.rds", m2_a = "m2_a.rds", m1_b = "m1_b.rds", m2_b = "m2_b.rds")
runtime_file_sha <- vapply(file.path(out_dir, files), sha256, character(1L))

m1a <- readRDS(source_paths[["m1_a"]])
m1b <- readRDS(source_paths[["m1_b"]])
manifest <- data.frame(
  release_id = release_id,
  model = names(files),
  file = unname(files),
  runtime_sha256 = unname(runtime_file_sha),
  source_sha256 = unname(source_sha[names(files)]),
  projection = c("exact_bytes", "exact_bytes", "runtime_projection_v1", "exact_bytes", "runtime_projection_v1"),
  source_version = c("page_m0_loso_result", m1a$version, m2a_src$contract$model_version, m1b$version, m2b_src$version),
  source_artifact_id = c("", m1a$artifact_id, m2a_src$artifact_id, m1b$artifact_id, m2b_src$artifact_id),
  runtime_projection_id = c("", "", m2a_runtime$runtime_projection_id, "", m2b_runtime$runtime_projection_id),
  library_hash = c("", m1a$library$provenance$library_hash, "", m1b$library$provenance$library_hash, ""),
  stringsAsFactors = FALSE
)
utils::write.csv(manifest, file.path(out_dir, "manifest.csv"), row.names = FALSE, quote = TRUE)

cat("Wrote package runtime bundle to", out_dir, "\n")
print(manifest, row.names = FALSE)
