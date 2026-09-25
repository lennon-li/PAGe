#!/usr/bin/env Rscript

# Build the governed RESEARCH-ONLY M2-v2 C2 artifact. This packages the fixed
# C2 family and prior-only chronological evidence without wiring production.

if (!requireNamespace("digest", quietly = TRUE) || !requireNamespace("jsonlite", quietly = TRUE)) {
  stop("The PAGe runtime dependencies digest and jsonlite are required.")
}
source("PAGe/R/m2_v2_research.R")

out_dir <- "artifacts/m2-v2-c2-research-v1"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
evidence_dir <- "artifacts/m2-v2-ab-curve-ratio-chronological-c123-v2"
geometry_dir <- "artifacts/m2-v2-flu-ab-geometry-v1"

required_evidence <- c(
  "candidate_independent_ledger.csv",
  "family_selection.csv",
  "fixed_c2_predictions.csv",
  "fixed_c2_summary.csv",
  "fixed_c2_active_summary.csv",
  "provenance.csv",
  "source_manifest.csv"
)
missing_evidence <- file.path(evidence_dir, required_evidence)
missing_evidence <- missing_evidence[!file.exists(missing_evidence)]
if (length(missing_evidence)) {
  stop("Chronological fixed-C2 evidence bundle is incomplete: ", paste(missing_evidence, collapse = ", "))
}

ledger_path <- file.path(evidence_dir, "candidate_independent_ledger.csv")
shape_path <- file.path(geometry_dir, "peak_aligned_normalized_shape_grid.csv")
if (!file.exists(shape_path)) stop("Missing peak-aligned shape grid.")
ledger <- read.csv(ledger_path, stringsAsFactors = FALSE)
shape <- read.csv(shape_path, stringsAsFactors = FALSE)
training_seasons <- sort(unique(as.character(ledger$season)))

review_path <- "docs/m2-v2-chronological-c123-v2-review-2026-09-25.md"
benchmark_path <- "docs/m2-v2-v1-metric-benchmark-2026-09-25.md"
matched_benchmark_path <- "docs/m2-v2-legacy-matched-a-benchmark-2026-09-25.md"
matched_benchmark_dir <- "artifacts/m2-v2-legacy-matched-a-v1"
matched_required <- c("summary.csv", "paired_season_summary.csv", "target_vintage_audit.csv", "provenance.csv")
if (!file.exists(review_path) || !file.exists(benchmark_path) || !file.exists(matched_benchmark_path) ||
    any(!file.exists(file.path(matched_benchmark_dir, matched_required)))) {
  stop("Current PASS review or matched legacy benchmark evidence is missing.")
}

source_files <- c(
  "PAGe/R/m2_v2_research.R",
  "PAGe/tests/testthat/test-m2-v2-c2-research.R",
  "PAGe/inst/schema/m2-v2-c2-research-v1.schema.json",
  "scripts/build_m2_v2_c2_research_artifact.R",
  "scripts/replay_m2_v2_c2_research_runtime_shadow_v1.R",
  "scripts/run_m2_ab_curve_ratio_chronological_c123_v2.R",
  "scripts/run_m2_b_baselines_v1.R",
  "docs/m2-v2-reviewed-design-2026-09-23.md",
  review_path,
  benchmark_path,
  matched_benchmark_path,
  "scripts/compare_m2_v2_legacy_matched_a_v1.R",
  file.path(matched_benchmark_dir, matched_required),
  "docs/m2-v2-b-timing-and-baselines-findings-2026-09-23.md",
  "docs/m2-v2-flu-ab-geometry-findings-2026-09-23.md",
  file.path(evidence_dir, required_evidence),
  file.path(geometry_dir, "flu_ab_weekly_v1.csv"),
  file.path(geometry_dir, "flu_ab_long_v1.csv"),
  shape_path,
  file.path(geometry_dir, "type_geometry_k8.csv")
)
missing <- source_files[!file.exists(source_files)]
if (length(missing)) stop("Missing provenance inputs: ", paste(missing, collapse = ", "))
hashes <- stats::setNames(lapply(source_files, function(f) digest::digest(file = f, algo = "sha256")), source_files)

fit <- m2_v2_c2_fit(
  training_ledger = ledger,
  shape_grid = shape,
  training_seasons = training_seasons,
  source_hashes = hashes
)
validate_m2_v2_c2_research_fit(fit)
fit_path <- file.path(out_dir, "m2_v2_c2_research_fit.rds")
saveRDS(fit, fit_path, version = 3)
fit_roundtrip <- readRDS(fit_path)
validate_m2_v2_c2_research_fit(fit_roundtrip)
if (!identical(fit_roundtrip$artifact_id, fit$artifact_id)) {
  stop("M2-v2 research artifact identity changed across RDS roundtrip.")
}
fit_rds_sha256 <- digest::digest(file = fit_path, algo = "sha256")

family <- read.csv(file.path(evidence_dir, "family_selection.csv"), stringsAsFactors = FALSE, na.strings = "NA")
selected <- family[!is.na(family$selected_family), , drop = FALSE]
selection_counts <- as.list(table(factor(selected$selected_family, levels = c("C1", "C2", "C3"))))
fixed_summary <- read.csv(file.path(evidence_dir, "fixed_c2_summary.csv"), stringsAsFactors = FALSE)
fixed_active <- read.csv(file.path(evidence_dir, "fixed_c2_active_summary.csv"), stringsAsFactors = FALSE)
pred <- read.csv(file.path(evidence_dir, "fixed_c2_predictions.csv"), stringsAsFactors = FALSE)
if (any(abs(pred$pred_fixed_c2[pred$type == "B" & pred$horizon == 1] -
            pred$pred_base[pred$type == "B" & pred$horizon == 1]) > 1e-12)) {
  stop("Fixed-C2 evidence violates B +1 exact-baseline identity.")
}
if (any(abs(pred$pred_fixed_c2[!pred$timing_available] -
            pred$pred_base[!pred$timing_available]) > 1e-12)) {
  stop("Fixed-C2 evidence violates timing-unavailable exact-baseline identity.")
}

legacy_path <- "../PAGe/results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/artifacts/m2_frozen.rds"
legacy <- if (file.exists(legacy_path)) readRDS(legacy_path) else NULL
legacy_id <- if (!is.null(legacy)) legacy$artifact_id else "m2_c1e467afffdadff25087be357fa42d231c3632d776e639bffafb9173ae1e3c54"
if (!identical(legacy_id, "m2_c1e467afffdadff25087be357fa42d231c3632d776e639bffafb9173ae1e3c54")) {
  stop("Frozen legacy M2 comparator identity does not match the benchmark contract.")
}

artifact <- m2_v2_c2_artifact_spec()
artifact$status <- "research_only_not_production_wired"
artifact$created_from <- "fixed_C2_plus_prior_only_chronological_evidence; no production wiring"
artifact$baseline_template$coefficients <- list(
  storage = "fit_identity.baseline_coefficients and fitted RDS",
  training = "quasibinomial GLM on the explicit 11 completed research seasons",
  offset = "logit_current",
  terms = c("horizon_f", "growth1", "growth2"),
  regime_term = FALSE,
  note = "denominator regime is retained as provenance; production observation likelihood is not finalized"
)
artifact$fit_identity <- list(
  artifact_id = fit$artifact_id,
  data_id = fit$data_id,
  shape_id = fit$shape_id,
  training_seasons = fit$training_seasons,
  fitted_rds = fit_path,
  fitted_rds_sha256 = fit_rds_sha256,
  baseline_coefficients = lapply(fit$baseline_coefficients, as.list),
  denominator_regime_metadata = fit$denominator_regime_metadata
)
artifact$provenance <- list(
  hash_algorithm = "sha256",
  source_hashes = hashes,
  review_disposition = "PASS_research_only",
  review_document = review_path
)
artifact$runtime_shadow_protocol <- list(
  script = "scripts/replay_m2_v2_c2_research_runtime_shadow_v1.R",
  output_dir = "artifacts/m2-v2-c2-research-runtime-shadow-v1",
  synthetic_future_season = TRUE,
  required_checks = 12L,
  performance_claim = FALSE,
  note = "derived shadow outputs are intentionally not part of model artifact identity to avoid circular provenance"
)
artifact$chronological_evidence <- list(
  source_artifact = evidence_dir,
  family_selection = list(
    evaluable_outer_folds = nrow(selected),
    selected_family_counts = selection_counts,
    c2_inner_selected_folds = if (is.null(selection_counts$C2)) 0L else unname(selection_counts$C2),
    fixed_research_family = "C2",
    runtime_selector = FALSE
  ),
  fixed_c2_metrics = fixed_summary,
  fixed_c2_active_metrics = fixed_active,
  fallback_invariants_in_saved_predictions = list(
    B_plus_1_equals_B1 = TRUE,
    timing_unavailable_equals_type_baseline = TRUE,
    source = "rechecked by builder from fixed_c2_predictions.csv"
  )
)
matched_summary <- read.csv(file.path(matched_benchmark_dir, "summary.csv"), stringsAsFactors = FALSE)
matched_paired <- read.csv(file.path(matched_benchmark_dir, "paired_season_summary.csv"), stringsAsFactors = FALSE)
artifact$legacy_comparator <- list(
  scope = "A_only_immutable_comparator",
  artifact_id = legacy_id,
  family = "offset_subset_v1",
  governed_spec = "h1:i0_kz0_ku0_kd0|h2:i0_kz0_ku0_kd0",
  benchmark_contract = benchmark_path,
  matched_benchmark = matched_benchmark_path,
  raw_metric_direct_comparison_allowed = FALSE,
  matched_target_ledger_comparison_available = TRUE,
  matched_target_ledger_metrics = matched_summary,
  matched_paired_season_summary = matched_paired,
  caveat = "target-ledger matched exchangeable comparison; training snapshots differ because 2025-26 was revised after the legacy final kit"
)
artifact$limitations <- c(
  "Research-only: run_prospective_pipeline() and legacy M2 runtime are unchanged.",
  "The B soft-timing contract and 5% activity gate remain provisional research contracts.",
  "The historical shared-denominator versus modern type-specific observation likelihood is not finalized for production.",
  "A +1 fixed-C2 performance is mixed across timing-active seasons and remains the primary robustness watchpoint.",
  "Raw legacy summary metrics remain non-comparable; the artifact now embeds a separate matched A-only target-ledger comparison with an explicit training-vintage caveat."
)

json_path <- file.path(out_dir, "m2_v2_c2_research_v1.json")
jsonlite::write_json(
  artifact, json_path, auto_unbox = TRUE, pretty = TRUE,
  null = "null", digits = 16
)
manifest <- data.frame(
  path = names(hashes),
  sha256 = unlist(hashes, use.names = FALSE),
  stringsAsFactors = FALSE
)
write.csv(manifest, file.path(out_dir, "source_manifest.csv"), row.names = FALSE)
json_sha256 <- digest::digest(file = json_path, algo = "sha256")
writeLines(paste(json_sha256, basename(json_path), sep = "  "), file.path(out_dir, "m2_v2_c2_research_v1.json.sha256"))
writeLines(paste(fit_rds_sha256, basename(fit_path), sep = "  "), file.path(out_dir, "m2_v2_c2_research_fit.rds.sha256"))

cat("Wrote research artifact JSON:", json_path, "\n")
cat("Wrote fitted research RDS:", fit_path, "\n")
cat("artifact_id:", fit$artifact_id, "\n")
cat("data_id:", fit$data_id, "\n")
cat("shape_id:", fit$shape_id, "\n")
cat("C2 inner-selected folds:", artifact$chronological_evidence$family_selection$c2_inner_selected_folds,
    "of", nrow(selected), "\n")
