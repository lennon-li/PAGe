# Helpers for the opt-in post-promotion refit.  They live outside the package
# because they govern private artifacts and are intentionally not part of the
# public runtime API.

page_refit_abort <- function(message) {
  stop(message, call. = FALSE)
}

page_validate_promotion_bundle <- function(bundle, holdout_season = "2025-26", data_path = NULL) {
  expected_names <- c(
    "schema", "schema_version", "run_id", "created_at", "holdout_season",
    "report", "source_artifact_hashes"
  )
  if (!is.list(bundle) || !identical(names(bundle), expected_names) ||
      !identical(bundle$schema, "page_holdout_decision_bundle") ||
      !identical(bundle$schema_version, 1L) ||
      !is.character(bundle$run_id) || length(bundle$run_id) != 1L || !nzchar(bundle$run_id) ||
      !is.character(bundle$created_at) || length(bundle$created_at) != 1L ||
      is.na(as.POSIXct(bundle$created_at, tz = "UTC")) ||
      !identical(bundle$holdout_season, holdout_season)) {
    page_refit_abort("Promotion bundle must use the canonical 2025-26 decision-bundle schema.")
  }
  hashes <- bundle$source_artifact_hashes
  required_hashes <- c("authorized_data", "candidate", "incumbent")
  if (!is.character(hashes) || anyDuplicated(names(hashes)) ||
      !setequal(names(hashes), required_hashes) ||
      any(!grepl("^[0-9a-f]{64}$", hashes))) {
    page_refit_abort("Promotion bundle must contain named candidate, incumbent, and authorized-data SHA-256 hashes.")
  }
  if (!is.null(data_path) && !identical(PAGe::hash_file_sha256(data_path), hashes[["authorized_data"]])) {
    page_refit_abort("Authorized data SHA-256 does not match the promotion decision bundle.")
  }
  report <- bundle$report
  # This is deliberately the package's strict validator rather than a
  # reimplementation of the promotion gates.  It should become public if this
  # workflow is promoted beyond this private script.
  canonical <- getFromNamespace(".is_canonical_promotion_report", "PAGe")
  if (!isTRUE(canonical(report, require_locked = TRUE))) {
    page_refit_abort(
      "Promotion report is not a canonical locked-threshold check_promotion() report."
    )
  }
  if (!isTRUE(report$pass)) {
    page_refit_abort("Promotion report did not pass; the prospective holdout remains locked.")
  }
  report
}

page_validate_promotion_manifest <- function(manifest, bundle, bundle_path,
                                             holdout_season = "2025-26") {
  if (!isTRUE(PAGe::validate_result_manifest(manifest))) {
    page_refit_abort("Promotion manifest is not a valid disclosure-safe result manifest.")
  }
  hashes <- manifest$provenance$source_artifact_hashes
  expected <- c("authorized_data", "candidate", "incumbent", "promotion_bundle")
  if (!is.character(hashes) || anyDuplicated(names(hashes)) ||
      !setequal(names(hashes), expected) ||
      !identical(hashes[expected[1:3]], bundle$source_artifact_hashes[expected[1:3]]) ||
      !identical(hashes[["promotion_bundle"]], PAGe::hash_file_sha256(bundle_path))) {
    page_refit_abort("Promotion manifest source hashes do not bind the promotion bundle.")
  }
  if (!identical(manifest$artifact$role, "holdout_acceptance_decision") ||
      !identical(manifest$artifact$classification, "disclosure_safe") ||
      !identical(as.character(manifest$provenance$evaluation_seasons), holdout_season) ||
      !holdout_season %in% as.character(manifest$provenance$seasons) ||
      !is.character(manifest$provenance$spec_id) || !nzchar(manifest$provenance$spec_id)) {
    page_refit_abort("Promotion manifest is not consistent with the 2025-26 holdout and selected spec.")
  }
  invisible(TRUE)
}

page_read_promotion_manifest <- function(path) {
  if (grepl("[.]rds$", path, ignore.case = TRUE)) return(readRDS(path))
  if (!grepl("[.]json$", path, ignore.case = TRUE) || !requireNamespace("jsonlite", quietly = TRUE)) {
    page_refit_abort("Promotion manifest must be an RDS or JSON file; JSON requires jsonlite.")
  }
  manifest <- jsonlite::read_json(path, simplifyVector = FALSE)
  manifest$schema_version <- as.integer(manifest$schema_version)
  manifest$artifact <- lapply(manifest$artifact, unlist, use.names = FALSE)
  provenance <- manifest$provenance
  provenance$package_versions <- unlist(provenance$package_versions, use.names = TRUE)
  provenance$source_artifact_hashes <- unlist(provenance$source_artifact_hashes, use.names = TRUE)
  provenance$row_counts <- unlist(provenance$row_counts, use.names = TRUE)
  provenance$row_counts <- as.numeric(provenance$row_counts)
  names(provenance$row_counts) <- names(unlist(manifest$provenance$row_counts, use.names = TRUE))
  for (field in c("code_commit", "run_timestamp", "r_version", "input_fingerprint", "seasons",
                  "exclusions", "spec_id", "training_seasons", "fold_ids", "evaluation_seasons")) {
    provenance[[field]] <- unlist(provenance[[field]], use.names = FALSE)
  }
  manifest$provenance <- provenance
  class(manifest) <- "page_result_manifest"
  manifest
}

page_candidate_refit_config <- function(candidate_kit, candidate_path, bundle, manifest) {
  candidate_hash <- PAGe::hash_file_sha256(candidate_path)
  if (!identical(candidate_hash, bundle$source_artifact_hashes[["candidate"]]) ||
      !identical(candidate_hash, manifest$provenance$source_artifact_hashes[["candidate"]])) {
    page_refit_abort("Candidate kit SHA-256 does not match the acceptance evidence.")
  }
  required <- c("best_spec", "m0_params", "M1_PARAMS", "manual_labels", "flag_args", "m2_production")
  if (!is.list(candidate_kit) || length(missing <- setdiff(required, names(candidate_kit))) ||
      !is.list(candidate_kit$best_spec) || !is.list(candidate_kit$m2_production) ||
      !identical(candidate_kit$best_spec, candidate_kit$m2_production$spec) ||
      !is.list(candidate_kit$m0_params) || !is.list(candidate_kit$M1_PARAMS) ||
      !is.list(candidate_kit$flag_args)) {
    page_refit_abort("Candidate kit lacks fixed M0, M1, M2, and runtime parameters required for refit.")
  }
  spec_id <- candidate_kit$m2_production$best_spec_id
  if (!is.character(spec_id) || length(spec_id) != 1L || !nzchar(spec_id) ||
      !identical(spec_id, manifest$provenance$spec_id)) {
    page_refit_abort("Candidate kit spec identity does not match the promotion manifest.")
  }
  list(
    best_spec = candidate_kit$best_spec, spec_id = spec_id,
    m0_params = candidate_kit$m0_params, m1_params = candidate_kit$M1_PARAMS,
    manual_labels = candidate_kit$manual_labels, flag_args = candidate_kit$flag_args
  )
}

page_assert_refit_postconditions <- function(retuned, candidate, holdout_season = "2025-26") {
  if (!identical(retuned$holdout$status, "released")) {
    page_refit_abort("Postcondition failed: prospective holdout was not released.")
  }
  training_seasons <- as.character(retuned$kit$m2_production$training_seasons)
  if (!holdout_season %in% training_seasons) {
    page_refit_abort(
      "Postcondition failed: `", holdout_season,
      "` is absent from the final M2 training seasons."
    )
  }
  spec_id <- retuned$kit$m2_production$best_spec_id
  if (!identical(spec_id, candidate$spec_id) ||
      !identical(retuned$kit$best_spec, candidate$best_spec) ||
      !identical(retuned$kit$m2_production$spec, candidate$best_spec) ||
      !identical(retuned$components$m0$best_params, candidate$m0_params) ||
      !identical(retuned$components$m0$manual_labels, candidate$manual_labels) ||
      !identical(retuned$components$m0$flag_args, candidate$flag_args) ||
      !identical(retuned$components$m1$m1_params, candidate$m1_params)) {
    page_refit_abort("Postcondition failed: refit components do not match the promoted candidate.")
  }
  list(training_seasons = sort(unique(training_seasons)), spec_id = spec_id)
}

page_refit_filename <- function(spec_id, data_hash, promotion_hash) {
  safe_spec <- gsub("[^A-Za-z0-9._-]+", "-", spec_id)
  paste0(
    "post_promotion_refit_", safe_spec, "_data-", substr(data_hash, 1L, 12L),
    "_promotion-", substr(promotion_hash, 1L, 12L), ".rds"
  )
}

page_refit_manifest <- function(postconditions, allD, data_path, candidate_path,
                                promotion_bundle_path, promotion_manifest_path,
                                artifact_path, code_commit) {
  source_hashes <- c(
    authorized_data = PAGe::hash_file_sha256(data_path),
    candidate = PAGe::hash_file_sha256(candidate_path),
    promotion_bundle = PAGe::hash_file_sha256(promotion_bundle_path),
    promotion_manifest = PAGe::hash_file_sha256(promotion_manifest_path),
    refit_artifact = PAGe::hash_file_sha256(artifact_path)
  )
  PAGe::new_result_manifest(
    artifact_role = "post_promotion_refit",
    classification = "disclosure_safe",
    code_commit = code_commit,
    run_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    r_version = as.character(getRversion()),
    package_versions = c(PAGe = as.character(utils::packageVersion("PAGe"))),
    input_fingerprint = unname(source_hashes[["authorized_data"]]),
    seasons = postconditions$training_seasons,
    exclusions = "none",
    row_counts = c(training = as.integer(sum(as.character(allD$season) %in% postconditions$training_seasons))),
    spec_id = postconditions$spec_id,
    training_seasons = postconditions$training_seasons,
    source_artifact_hashes = source_hashes,
    fold_ids = "none",
    evaluation_seasons = "none"
  )
}

page_manifest_markdown <- function(manifest) {
  provenance <- manifest$provenance
  paste(
    "# PAGe post-promotion refit manifest",
    "",
    paste0("- Spec ID: `", provenance$spec_id, "`"),
    paste0("- Training seasons: ", paste(provenance$training_seasons, collapse = ", ")),
    "- Source SHA-256 hashes:",
    vapply(
      names(provenance$source_artifact_hashes),
      function(name) paste0("  - ", name, ": `", provenance$source_artifact_hashes[[name]], "`"),
      character(1)
    ),
    sep = "\n"
  )
}

page_run_post_promotion_refit <- function(allD, promotion_bundle, promotion_manifest,
                                          candidate_kit, candidate_path, incumbent_path,
                                          data_path,
                                          promotion_bundle_path, promotion_manifest_path,
                                          output_dir, manifest_dir,
                                          kit_compatibility = c("strict", "legacy_m2"),
                                          train_fn = PAGe::train_pipeline,
                                          save_rds = saveRDS,
                                          write_manifest = saveRDS,
                                          write_lines = writeLines,
                                          code_commit = NULL,
                                          ...) {
  kit_compatibility <- match.arg(kit_compatibility)
  promotion_report <- page_validate_promotion_bundle(promotion_bundle, data_path = data_path)
  page_validate_promotion_manifest(promotion_manifest, promotion_bundle, promotion_bundle_path)
  candidate <- page_candidate_refit_config(candidate_kit, candidate_path, promotion_bundle, promotion_manifest)
  promotion_evidence <- PAGe::verify_promotion_evidence(
    bundle = promotion_bundle,
    manifest = promotion_manifest,
    data_path = data_path,
    candidate_path = candidate_path,
    incumbent_path = incumbent_path,
    bundle_path = promotion_bundle_path,
    kit_compatibility = kit_compatibility
  )
  if (!is.character(code_commit) || length(code_commit) != 1L ||
      !grepl("^[0-9a-f]{7,64}$", code_commit)) {
    page_refit_abort("A 7-64 character lowercase Git commit hash is required.")
  }
  data_hash <- PAGe::hash_file_sha256(data_path)
  promotion_hash <- PAGe::hash_file_sha256(promotion_bundle_path)
  if (identical(normalizePath(output_dir, mustWork = FALSE),
                normalizePath(manifest_dir, mustWork = FALSE))) {
    page_refit_abort("`output_dir` and `manifest_dir` must be separate locations.")
  }
  artifact_name <- page_refit_filename(candidate$spec_id, data_hash, promotion_hash)
  artifact_path <- file.path(output_dir, artifact_name)
  manifest_path <- file.path(manifest_dir, sub("[.]rds$", "_manifest.rds", artifact_name))
  manifest_markdown_path <- sub("[.]rds$", ".md", manifest_path)
  if (file.exists(artifact_path) || file.exists(manifest_path) || file.exists(manifest_markdown_path)) {
    page_refit_abort("Refit artifact or manifest already exists; refusing to overwrite output.")
  }

  retuned <- train_fn(
    allD, mode = "refresh", previous_results = list(best_spec = candidate$best_spec),
    prospective_holdout = "2025-26", promotion = promotion_evidence,
    m0_params = candidate$m0_params, m1_params = candidate$m1_params,
    manual_labels = candidate$manual_labels, flag_args = candidate$flag_args,
    m2_spec_id = candidate$spec_id, ...
  )
  postconditions <- page_assert_refit_postconditions(retuned, candidate)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(manifest_dir, recursive = TRUE, showWarnings = FALSE)
  save_rds(retuned, artifact_path)
  manifest <- page_refit_manifest(
    postconditions, allD, data_path, candidate_path, promotion_bundle_path,
    promotion_manifest_path, artifact_path, code_commit
  )
  PAGe::validate_result_manifest(manifest)
  write_manifest(manifest, manifest_path)
  write_lines(page_manifest_markdown(manifest), manifest_markdown_path)
  list(
    artifact_path = artifact_path, manifest_path = manifest_path,
    manifest_markdown_path = manifest_markdown_path, manifest = manifest
  )
}
