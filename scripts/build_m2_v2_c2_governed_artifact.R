#!/usr/bin/env Rscript

# Builds the opt-in governed M2-v2 C2 artifact alongside legacy M2.
if (!requireNamespace("digest", quietly = TRUE) || !requireNamespace("jsonlite", quietly = TRUE)) {
  stop("The PAGe runtime dependencies digest and jsonlite are required.")
}
source("PAGe/R/m2_v2_research.R")
source("PAGe/R/m2_v2_c2_governed.R")

out_dir <- "artifacts/m2-v2-c2-governed-v1"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
evidence_dir <- "artifacts/m2-v2-ab-curve-ratio-chronological-c123-v2"
geometry_dir <- "artifacts/m2-v2-flu-ab-geometry-v1"
ledger_path <- file.path(evidence_dir, "candidate_independent_ledger.csv")
pred_path <- file.path(evidence_dir, "fixed_c2_predictions.csv")
shape_path <- file.path(geometry_dir, "peak_aligned_normalized_shape_grid.csv")
research_manifest_path <- "artifacts/m2-v2-c2-research-v1/m2_v2_c2_research_v1.json"
research_fit_path <- "artifacts/m2-v2-c2-research-v1/m2_v2_c2_research_fit.rds"
required <- c(
  ledger_path, pred_path, shape_path, research_manifest_path, research_fit_path,
  "docs/m2-v2-chronological-c123-v2-review-2026-09-25.md"
)
if (any(!file.exists(required))) {
  stop(
    "Missing governed C2 evidence: ",
    paste(required[!file.exists(required)], collapse = ", ")
  )
}

ledger <- read.csv(ledger_path, stringsAsFactors = FALSE)
shape <- read.csv(shape_path, stringsAsFactors = FALSE)
pred <- read.csv(pred_path, stringsAsFactors = FALSE)
training_seasons <- sort(unique(as.character(ledger$season)))
evidence <- unique(pred[c("season", "prior_seasons")])
for (i in seq_len(nrow(evidence))) {
  prior <- if (is.na(evidence$prior_seasons[i]) || !nzchar(evidence$prior_seasons[i])) {
    character()
  } else {
    strsplit(evidence$prior_seasons[i], ";", fixed = TRUE)[[1L]]
  }
  expected <- training_seasons[training_seasons < evidence$season[i]]
  if (!identical(sort(prior), sort(expected))) {
    stop("Cross-fit/season-exclusion audit failed for target season ", evidence$season[i], ".")
  }
}
source_files <- c(
  "PAGe/R/m2_v2_research.R", "PAGe/R/m2_v2_c2_governed.R",
  "PAGe/tests/testthat/test-m2-v2-c2-governed.R",
  "PAGe/inst/schema/m2-v2-c2-governed-v1.schema.json",
  "scripts/build_m2_v2_c2_governed_artifact.R",
  "scripts/replay_m2_v2_c2_governed_shadow_v1.R",
  "scripts/run_m2_ab_curve_ratio_chronological_c123_v2.R",
  "docs/m2-v2-chronological-c123-v2-review-2026-09-25.md",
  "docs/m2-v2-c2-governed-runtime-2026-09-25.md",
  research_manifest_path, research_fit_path, ledger_path, pred_path, shape_path
)
if (any(!file.exists(source_files))) {
  stop(
    "Missing source/provenance files: ",
    paste(source_files[!file.exists(source_files)], collapse = ", ")
  )
}
# Hash file bytes, not R object serialization.
hashes <- stats::setNames(lapply(source_files, function(f) digest::digest(file = f, algo = "sha256")), source_files)
research_manifest <- jsonlite::fromJSON(research_manifest_path, simplifyVector = FALSE)
if (!identical(digest::digest(file = research_fit_path, algo = "sha256"),
               research_manifest$fit_identity$fitted_rds_sha256)) {
  stop("Canonical research-fit RDS hash does not match its manifest.")
}
fit <- readRDS(research_fit_path)
validate_m2_v2_c2_research_fit(fit)
if (!identical(fit$artifact_id, research_manifest$fit_identity$artifact_id)) {
  stop("Canonical research-fit artifact ID does not match its manifest.")
}
if (!setequal(fit$training_seasons, training_seasons)) {
  stop("Canonical research-fit training seasons do not match governed evidence.")
}
shape_check <- shape[as.character(shape$season) %in% training_seasons, , drop = FALSE]
shape_check$season <- as.character(shape_check$season)
shape_check$type <- as.character(shape_check$type)
shape_check <- shape_check[is.finite(shape_check$tau) & is.finite(shape_check$p_norm), , drop = FALSE]
shape_check$p_norm <- pmin(pmax(shape_check$p_norm, 0.01), 1)
shape_check <- shape_check[order(shape_check$season, shape_check$type, shape_check$tau), , drop = FALSE]
rownames(shape_check) <- NULL
if (!identical(fit$data_id, .m2_v2_c2_training_data_id(ledger)) ||
    !identical(fit$shape_id, .m2_v2_c2_shape_id(shape_check))) {
  stop("Canonical research-fit data/shape identities do not match governed inputs.")
}
gov <- new_m2_v2_c2_governed_artifact(
  fit,
  provenance = list(
    hash_algorithm = "sha256", source_hashes = hashes,
    training_data_sha256 = hashes[[ledger_path]],
    shape_data_sha256 = hashes[[shape_path]],
    timing_evidence_sha256 = hashes[[pred_path]],
    review_document = required[6L],
    review_disposition = "PASS_research_only_runtime_shadow"
  ),
  training_evidence = evidence
)
fit_path <- file.path(out_dir, "m2_v2_c2_governed_fit.rds")
saveRDS(gov, fit_path, version = 3)
roundtrip <- readRDS(fit_path)
validate_m2_v2_c2_governed_artifact(roundtrip)
fit_hash <- digest::digest(file = fit_path, algo = "sha256")
artifact <- list(
  contract = gov$contract,
  artifact_id = gov$artifact_id,
  training_seasons = gov$training_seasons,
  training_evidence_id = gov$training_evidence_id,
  research_fit_artifact_id = fit$artifact_id,
  data_id = fit$data_id,
  shape_id = fit$shape_id,
  fitted_rds = fit_path,
  fitted_rds_sha256 = fit_hash,
  provenance = gov$provenance,
  evidence = list(
    c2_selected_outer_folds = 6L,
    selectable_outer_folds = 7L,
    b_plus_1_exact_baseline = TRUE,
    timing_failure_exact_baseline = TRUE,
    historical_timing_rows_cross_fitted = TRUE
  ),
  status = "governed_opt_in_shadow_not_legacy_runtime"
)
json_path <- file.path(out_dir, "m2_v2_c2_governed_v1.json")
jsonlite::write_json(artifact, json_path, auto_unbox = TRUE, pretty = TRUE, digits = 16)
write.csv(
  data.frame(
    path = names(hashes), sha256 = unlist(hashes),
    stringsAsFactors = FALSE
  ),
  file.path(out_dir, "source_manifest.csv"),
  row.names = FALSE
)
writeLines(
  paste(digest::digest(file = json_path, algo = "sha256"), basename(json_path), sep = "  "),
  paste0(json_path, ".sha256")
)
writeLines(paste(fit_hash, basename(fit_path), sep = "  "), paste0(fit_path, ".sha256"))
cat("artifact_id:", gov$artifact_id, "\n")
cat("training seasons:", length(training_seasons), "\n")
cat("cross-fit target seasons:", nrow(evidence), "\n")
cat("wrote:", json_path, "\n")
