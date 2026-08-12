# Helpers for the manual 2025-26 candidate-versus-incumbent acceptance gate.
# This file intentionally has no package side effects so tests can inject a
# replay seam and exercise all persistence paths with synthetic inputs.

.acceptance_or <- function(x, y) if (is.null(x)) y else x

acceptance_spec_identity <- function(m2) {
  for (field in c("best_spec_id", "spec_id")) {
    value <- m2[[field]]
    if (is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)) {
      return(value)
    }
  }
  required <- c(
    "delta", "Kr", "k_f", "k_e", "alpha_state", "k_r", "k_de", "k_sp",
    "bias_alpha", "bias_beta"
  )
  spec <- m2$spec
  if (!is.list(spec) || is.null(names(spec)) || !all(required %in% names(spec))) {
    return(NULL)
  }
  identity_spec <- spec[sort(required)]
  complete <- vapply(identity_spec, function(value) {
    is.atomic(value) && length(value) == 1L && !is.na(value) && is.finite(value)
  }, logical(1))
  if (!all(complete)) return(NULL)
  paste0("spec_sha256_", digest::digest(identity_spec, algo = "sha256"))
}

acceptance_kit_identity <- function(kit, label, season,
                                    compatibility = c("strict", "legacy_m2")) {
  resolver <- getFromNamespace(".resolve_kit_m2_identity", "PAGe")
  m2 <- resolver(kit, compatibility = compatibility, label = paste(label, "kit"))
  if (!is.list(m2)) stop("The ", label, " kit has no inspectable M2 identity.", call. = FALSE)
  if (is.null(m2$training_seasons)) {
    stop("The ", label, " kit is missing required `training_seasons`.", call. = FALSE)
  }
  training_seasons <- as.character(m2$training_seasons)
  if (!length(training_seasons) || anyNA(training_seasons) || any(!nzchar(training_seasons))) {
    stop("The ", label, " kit has invalid `training_seasons`.", call. = FALSE)
  }
  if (season %in% training_seasons) {
    stop("The ", label, " kit has holdout leakage: `", season, "` is in training_seasons.", call. = FALSE)
  }
  spec_id <- acceptance_spec_identity(m2)
  if (is.null(spec_id)) {
    stop("The ", label, " kit is missing a required `best_spec_id`/`spec_id` or complete stored spec.", call. = FALSE)
  }
  list(label = label, spec_id = spec_id, training_seasons = training_seasons)
}

acceptance_run_paths <- function(private_output_dir, audit_output_dir, run_id) {
  if (!is.character(run_id) || length(run_id) != 1L || !grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", run_id)) {
    stop("`run_id` must use only letters, numbers, dots, underscores, or hyphens.", call. = FALSE)
  }
  private_dir <- file.path(private_output_dir, run_id)
  audit_dir <- file.path(audit_output_dir, run_id)
  if (dir.exists(private_dir) || file.exists(private_dir) || dir.exists(audit_dir) || file.exists(audit_dir)) {
    stop("Acceptance output already exists for run ID `", run_id, "`; choose a new run ID.", call. = FALSE)
  }
  if (!dir.create(private_dir, recursive = TRUE, showWarnings = FALSE) ||
      !dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)) {
    stop("Could not create immutable acceptance output directories.", call. = FALSE)
  }
  list(
    private_dir = private_dir,
    audit_dir = audit_dir,
    candidate_replay = file.path(private_dir, "candidate_replay.rds"),
    incumbent_replay = file.path(private_dir, "incumbent_replay.rds"),
    private_bundle = file.path(private_dir, "decision_bundle.rds"),
    manifest = file.path(audit_dir, "result_manifest.json"),
    decision_markdown = file.path(audit_dir, "decision.md")
  )
}

acceptance_metric_csvs <- function(candidate_metrics, incumbent_metrics, gate, audit_dir) {
  metric_paths <- unlist(lapply(c("overall", "horizon", "phase"), function(scope) {
    candidate_path <- file.path(audit_dir, paste0("candidate_", scope, "_metrics.csv"))
    incumbent_path <- file.path(audit_dir, paste0("incumbent_", scope, "_metrics.csv"))
    utils::write.csv(candidate_metrics[[scope]], candidate_path, row.names = FALSE)
    utils::write.csv(incumbent_metrics[[scope]], incumbent_path, row.names = FALSE)
    c(candidate_path, incumbent_path)
  }), use.names = FALSE)
  gate_detail <- data.table::rbindlist(list(
    transform(gate$gates, detail_scope = "gate"),
    transform(gate$details$horizon, detail_scope = "horizon"),
    transform(gate$details$phase, detail_scope = "phase")
  ), fill = TRUE)
  gate_path <- file.path(audit_dir, "gate_details.csv")
  utils::write.csv(gate_detail, gate_path, row.names = FALSE)
  c(metric_paths, gate_path)
}

acceptance_diagnostic_csvs <- function(candidate_diagnostics, incumbent_diagnostics, audit_dir) {
  paths <- c()
  for (model in c("candidate", "incumbent")) {
    diagnostics <- if (identical(model, "candidate")) candidate_diagnostics else incumbent_diagnostics
    for (scope in c("overall", "horizon")) {
      path <- file.path(audit_dir, paste0(model, "_", scope, "_diagnostics.csv"))
      utils::write.csv(diagnostics[[scope]], path, row.names = FALSE)
      paths <- c(paths, path)
    }
  }
  paths
}

acceptance_input_fingerprint <- function(source_hashes) {
  digest::digest(paste(names(source_hashes), unname(source_hashes), collapse = "|"),
    algo = "sha256", serialize = FALSE)
}

acceptance_ignition_label <- function(replay) {
  status <- .acceptance_or(replay$ignition_status, "not_available")
  week <- .acceptance_or(replay$ignition_week, NA_real_)
  if (is.finite(week)) paste0(status, " at week ", format(week, trim = TRUE)) else as.character(status)
}

acceptance_write_decision_markdown <- function(paths, run_id, season, candidate, incumbent, gate,
                                               candidate_replay, incumbent_replay) {
  lines <- c(
    "# PAGe holdout acceptance decision", "",
    paste0("- run ID: `", run_id, "`"),
    paste0("- holdout season: `", season, "`"),
    paste0("- decision: **", if (isTRUE(gate$pass)) "PASS" else "FAIL", "**"),
    paste0("- candidate spec ID: `", candidate$spec_id, "`"),
    paste0("- incumbent spec ID: `", incumbent$spec_id, "`"),
    paste0("- candidate training seasons: ", paste(candidate$training_seasons, collapse = ", ")),
    paste0("- incumbent training seasons: ", paste(incumbent$training_seasons, collapse = ", ")),
    paste0("- candidate ignition: ", acceptance_ignition_label(candidate_replay)),
    paste0("- incumbent ignition: ", acceptance_ignition_label(incumbent_replay)),
    "", "## Locked promotion gates", "",
    capture.output(print(gate$gates, row.names = FALSE)), "", "## Reasons", "",
    if (length(gate$reasons)) paste0("- ", gate$reasons) else "- All locked promotion gates passed.",
    "", "No refit, promotion, or artifact copy was performed by this acceptance run."
  )
  writeLines(lines, paths$decision_markdown, useBytes = TRUE)
}

acceptance_read_manifest <- function(path) {
  manifest <- jsonlite::read_json(path, simplifyVector = FALSE)
  manifest$schema_version <- as.integer(manifest$schema_version)
  manifest$artifact <- lapply(manifest$artifact, unlist, use.names = FALSE)
  provenance <- manifest$provenance
  provenance$package_versions <- unlist(provenance$package_versions, use.names = TRUE)
  provenance$source_artifact_hashes <- unlist(provenance$source_artifact_hashes, use.names = TRUE)
  provenance$row_counts <- as.numeric(unlist(provenance$row_counts, use.names = TRUE))
  names(provenance$row_counts) <- names(unlist(manifest$provenance$row_counts, use.names = TRUE))
  for (field in c("code_commit", "run_timestamp", "r_version", "input_fingerprint", "seasons",
                  "exclusions", "spec_id", "training_seasons", "fold_ids", "evaluation_seasons")) {
    provenance[[field]] <- unlist(provenance[[field]], use.names = FALSE)
  }
  manifest$provenance <- provenance
  class(manifest) <- "page_result_manifest"
  manifest
}

run_acceptance_replay <- function(data_path,
                                  candidate_path,
                                  incumbent_path,
                                  private_output_dir,
                                  audit_output_dir,
                                  season = "2025-26",
                                  kit_compatibility = c("strict", "legacy_m2"),
                                  replay_fun = NULL,
                                  prepare_fun = PAGe::prepare_surveillance_data,
                                  code_commit = NULL,
                                  run_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                                  run_id = paste0("acceptance-", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), "-", Sys.getpid())) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("The `jsonlite` package is required for acceptance JSON output.", call. = FALSE)
  required_paths <- c(data_path = data_path, candidate_kit = candidate_path, incumbent_kit = incumbent_path)
  if (any(!file.exists(required_paths)) || any(dir.exists(required_paths))) {
    stop("Data and both kit paths must exist and be regular files.", call. = FALSE)
  }
  candidate_kit <- readRDS(candidate_path)
  incumbent_kit <- readRDS(incumbent_path)
  kit_compatibility <- match.arg(kit_compatibility)
  candidate <- acceptance_kit_identity(
    candidate_kit, "candidate", season, compatibility = "strict"
  )
  incumbent <- acceptance_kit_identity(
    incumbent_kit, "incumbent", season, compatibility = kit_compatibility
  )
  if (is.null(replay_fun)) {
    replay_fun <- function(kit, allD, season) {
      PAGe::replay_season_holdout(
        kit,
        allD,
        season = season,
        kit_compatibility = kit_compatibility
      )
    }
  }
  if (!is.function(replay_fun)) {
    stop("`replay_fun` must be NULL or a function.", call. = FALSE)
  }
  all_data <- if (grepl("[.]rds$", data_path, ignore.case = TRUE)) readRDS(data_path) else utils::read.csv(data_path)
  prepared_data <- prepare_fun(all_data)
  if (!is.data.frame(prepared_data)) stop("The prepared authorized data must be a data frame.", call. = FALSE)

  paths <- acceptance_run_paths(private_output_dir, audit_output_dir, run_id)
  source_hashes <- c(
    authorized_data = PAGe::hash_file_sha256(data_path),
    candidate = PAGe::hash_file_sha256(candidate_path),
    incumbent = PAGe::hash_file_sha256(incumbent_path)
  )
  candidate_replay <- replay_fun(candidate_kit, prepared_data, season)
  incumbent_replay <- replay_fun(incumbent_kit, prepared_data, season)
  if (!is.list(candidate_replay$metrics) || !is.list(incumbent_replay$metrics)) {
    stop("Both replays must return standardized metric summaries.", call. = FALSE)
  }
  gate <- PAGe::check_promotion(candidate_replay$metrics, incumbent_replay$metrics)
  candidate_diagnostics <- .acceptance_or(
    candidate_replay$diagnostics,
    PAGe::summarize_replay_diagnostics(candidate_replay$predictions)
  )
  incumbent_diagnostics <- .acceptance_or(
    incumbent_replay$diagnostics,
    PAGe::summarize_replay_diagnostics(incumbent_replay$predictions)
  )
  saveRDS(candidate_replay, paths$candidate_replay)
  saveRDS(incumbent_replay, paths$incumbent_replay)

  private_bundle <- structure(list(
    schema = "page_holdout_decision_bundle", schema_version = 1L,
    run_id = run_id, created_at = run_timestamp, holdout_season = season,
    report = gate, source_artifact_hashes = source_hashes
  ), class = "page_holdout_decision_bundle")
  saveRDS(private_bundle, paths$private_bundle)

  acceptance_metric_csvs(candidate_replay$metrics, incumbent_replay$metrics, gate, paths$audit_dir)
  acceptance_diagnostic_csvs(candidate_diagnostics, incumbent_diagnostics, paths$audit_dir)
  acceptance_write_decision_markdown(
    paths, run_id, season, candidate, incumbent, gate, candidate_replay, incumbent_replay
  )
  source_hashes <- c(source_hashes, promotion_bundle = PAGe::hash_file_sha256(paths$private_bundle))
  if (is.null(code_commit)) {
    code_commit <- tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE), error = function(e) "unknown")
    code_commit <- tolower(trimws(.acceptance_or(code_commit[[1L]], "unknown")))
  }
  if (!grepl("^[0-9a-f]{7,64}$", code_commit)) stop("A Git commit hash is required for the acceptance manifest.", call. = FALSE)
  manifest <- PAGe::new_result_manifest(
    artifact_role = "holdout_acceptance_decision", classification = "disclosure_safe",
    code_commit = code_commit, run_timestamp = run_timestamp,
    r_version = as.character(getRversion()),
    package_versions = c(PAGe = as.character(utils::packageVersion("PAGe")), jsonlite = as.character(utils::packageVersion("jsonlite"))),
    input_fingerprint = acceptance_input_fingerprint(source_hashes),
    seasons = season, exclusions = "none",
    row_counts = c(authorized_input = nrow(prepared_data), candidate_predictions = nrow(candidate_replay$predictions), incumbent_predictions = nrow(incumbent_replay$predictions)),
    spec_id = candidate$spec_id,
    training_seasons = unique(c(candidate$training_seasons, incumbent$training_seasons)),
    source_artifact_hashes = source_hashes,
    fold_ids = paste0("holdout_", season), evaluation_seasons = season
  )
  manifest_json <- unclass(manifest)
  manifest_json$provenance$package_versions <- as.list(manifest$provenance$package_versions)
  manifest_json$provenance$source_artifact_hashes <- as.list(manifest$provenance$source_artifact_hashes)
  manifest_json$provenance$row_counts <- as.list(manifest$provenance$row_counts)
  jsonlite::write_json(manifest_json, paths$manifest, auto_unbox = TRUE, pretty = TRUE)
  if (!PAGe::validate_result_manifest(acceptance_read_manifest(paths$manifest))) {
    stop("Written acceptance manifest did not validate.", call. = FALSE)
  }
  result <- list(paths = paths, gate = gate, manifest = manifest, run_id = run_id)
  if (!isTRUE(gate$pass)) stop("Promotion failed after acceptance evidence was saved for run ID `", run_id, "`.", call. = FALSE)
  result
}
