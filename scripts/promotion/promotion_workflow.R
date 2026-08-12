# Immutable post-refit promotion workflow.
#
# This file has no top-level side effects. Tests inject manifest I/O while the
# command-line entry point uses PAGe's canonical manifest readers and writers.

promotion_abort <- function(message) {
  stop(message, call. = FALSE)
}

promotion_is_nonempty_scalar <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
}

promotion_require_files <- function(paths) {
  invalid <- !vapply(paths, function(path) {
    promotion_is_nonempty_scalar(path) && file.exists(path) && !dir.exists(path)
  }, logical(1))
  if (any(invalid)) {
    promotion_abort(
      paste0(
        "Required promotion input is missing or is not a regular file: `",
        names(paths)[which(invalid)[1L]], "`."
      )
    )
  }
  invisible(TRUE)
}

promotion_validate_authorized_data <- function(path, holdout_season) {
  data <- if (grepl("[.]rds$", path, ignore.case = TRUE)) {
    readRDS(path)
  } else if (grepl("[.]csv$", path, ignore.case = TRUE)) {
    utils::read.csv(path)
  } else {
    promotion_abort("Authorized data must be an RDS or CSV file.")
  }
  if (!is.data.frame(data) || !"season" %in% names(data) ||
    !holdout_season %in% as.character(data$season)) {
    promotion_abort(
      paste0(
        "Authorized data must contain holdout season `",
        holdout_season, "`."
      )
    )
  }
  invisible(TRUE)
}

promotion_validate_id <- function(deployment_id) {
  if (!promotion_is_nonempty_scalar(deployment_id) ||
    !grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", deployment_id)) {
    promotion_abort(
      "`deployment_id` must use only letters, numbers, dots, underscores, or hyphens."
    )
  }
  deployment_id
}

promotion_m2 <- function(kit, label, compatibility = "strict") {
  resolver <- getFromNamespace(".resolve_kit_m2_identity", "PAGe")
  m2 <- resolver(
    kit,
    compatibility = compatibility,
    label = paste(label, "kit")
  )
  if (!is.list(m2)) {
    promotion_abort(paste0("The ", label, " kit has no inspectable M2 component."))
  }
  m2
}

promotion_kit_identity <- function(kit, label, holdout_season,
                                   require_holdout_in_training,
                                   compatibility = "strict") {
  m2 <- promotion_m2(kit, label, compatibility = compatibility)
  spec_id <- m2$best_spec_id
  if (!promotion_is_nonempty_scalar(spec_id)) {
    spec_id <- m2$spec_id
  }
  if (!promotion_is_nonempty_scalar(spec_id) || !is.list(m2$spec)) {
    promotion_abort(
      paste0(
        "The ", label,
        " kit must contain a spec, `best_spec_id`/`spec_id`, and training seasons."
      )
    )
  }
  training_seasons <- as.character(m2$training_seasons)
  if (!length(training_seasons) || anyNA(training_seasons) ||
    any(!nzchar(training_seasons))) {
    promotion_abort(paste0("The ", label, " kit has invalid training seasons."))
  }
  contains_holdout <- holdout_season %in% training_seasons
  if (!identical(contains_holdout, require_holdout_in_training)) {
    expectation <- if (require_holdout_in_training) "include" else "exclude"
    promotion_abort(
      paste0(
        "The ", label, " kit must ", expectation, " holdout season `",
        holdout_season, "` in its training seasons."
      )
    )
  }
  list(
    spec_id = spec_id,
    spec = m2$spec,
    training_seasons = training_seasons
  )
}

promotion_candidate_fixed_config <- function(candidate_kit, candidate) {
  required <- c(
    "best_spec", "m0_params", "M1_PARAMS", "manual_labels", "flag_args",
    "m2_production"
  )
  missing <- setdiff(required, names(candidate_kit))
  if (!is.list(candidate_kit) || length(missing) ||
    !is.list(candidate_kit$best_spec) ||
    !is.list(candidate_kit$m0_params) ||
    !is.list(candidate_kit$M1_PARAMS) ||
    is.null(candidate_kit$manual_labels) ||
    !is.list(candidate_kit$flag_args) ||
    !is.list(candidate_kit$m2_production) ||
    !identical(candidate_kit$best_spec, candidate$spec) ||
    !identical(candidate_kit$m2_production$spec, candidate$spec)) {
    promotion_abort(
      "Accepted candidate lacks fixed M0, M1, M2, and runtime parameters."
    )
  }
  list(
    best_spec = candidate_kit$best_spec,
    m0_params = candidate_kit$m0_params,
    m1_params = candidate_kit$M1_PARAMS,
    manual_labels = candidate_kit$manual_labels,
    flag_args = candidate_kit$flag_args
  )
}

promotion_validate_manifest <- function(manifest, role, label) {
  if (!isTRUE(PAGe::validate_result_manifest(manifest))) {
    promotion_abort(paste0("The ", label, " manifest is invalid."))
  }
  if (!identical(manifest$artifact$role, role) ||
    !identical(manifest$artifact$classification, "disclosure_safe")) {
    promotion_abort(
      paste0(
        "The ", label, " manifest must have role `", role,
        "` and classification `disclosure_safe`."
      )
    )
  }
  manifest
}

promotion_expect_hashes <- function(actual, expected, label) {
  if (!is.character(actual) || anyDuplicated(names(actual)) ||
    !setequal(names(actual), names(expected)) ||
    !identical(actual[names(expected)], expected)) {
    promotion_abort(paste0("The ", label, " manifest source hashes do not match."))
  }
  invisible(TRUE)
}

promotion_validate_acceptance <- function(
  data_path,
  acceptance_bundle_path,
  acceptance_manifest_path,
  candidate_path,
  incumbent_path,
  acceptance_bundle,
  acceptance_manifest,
  candidate_kit,
  incumbent_kit,
  holdout_season,
  kit_compatibility = "strict",
  canonical_report = function(report) {
    validator <- getFromNamespace(".is_canonical_promotion_report", "PAGe")
    validator(report, require_locked = TRUE)
  }
) {
  expected_bundle_names <- c(
    "schema", "schema_version", "run_id", "created_at", "holdout_season",
    "report", "source_artifact_hashes"
  )
  if (!is.list(acceptance_bundle) ||
    !identical(names(acceptance_bundle), expected_bundle_names) ||
    !identical(acceptance_bundle$schema, "page_holdout_decision_bundle") ||
    !identical(acceptance_bundle$schema_version, 1L) ||
    !promotion_is_nonempty_scalar(acceptance_bundle$run_id) ||
    !promotion_is_nonempty_scalar(acceptance_bundle$created_at) ||
    is.na(as.POSIXct(acceptance_bundle$created_at, tz = "UTC")) ||
    !identical(acceptance_bundle$holdout_season, holdout_season)) {
    promotion_abort(
      "Acceptance bundle must use the canonical 2025-26 decision-bundle schema."
    )
  }
  if (!isTRUE(canonical_report(acceptance_bundle$report)) ||
    !isTRUE(acceptance_bundle$report$pass)) {
    promotion_abort(
      "Acceptance report must be a passing canonical report with locked thresholds."
    )
  }

  bundle_hashes <- c(
    authorized_data = PAGe::hash_file_sha256(data_path),
    candidate = PAGe::hash_file_sha256(candidate_path),
    incumbent = PAGe::hash_file_sha256(incumbent_path)
  )
  if (!identical(
    acceptance_bundle$source_artifact_hashes[names(bundle_hashes)],
    bundle_hashes
  ) || !setequal(
    names(acceptance_bundle$source_artifact_hashes),
    names(bundle_hashes)
  )) {
    if (!identical(
      acceptance_bundle$source_artifact_hashes[["candidate"]],
      bundle_hashes[["candidate"]]
    )) {
      promotion_abort("Candidate kit SHA-256 does not match acceptance evidence.")
    }
    if (!identical(
      acceptance_bundle$source_artifact_hashes[["incumbent"]],
      bundle_hashes[["incumbent"]]
    )) {
      promotion_abort("Incumbent kit SHA-256 does not match acceptance evidence.")
    }
    promotion_abort("Authorized data SHA-256 does not match acceptance evidence.")
  }
  candidate <- promotion_kit_identity(
    candidate_kit, "accepted candidate", holdout_season, FALSE
  )
  candidate_config <- promotion_candidate_fixed_config(
    candidate_kit, candidate
  )
  incumbent <- promotion_kit_identity(
    incumbent_kit, "accepted incumbent", holdout_season, FALSE,
    compatibility = kit_compatibility
  )

  acceptance_manifest <- promotion_validate_manifest(
    acceptance_manifest, "holdout_acceptance_decision", "acceptance"
  )
  acceptance_hashes <- c(
    bundle_hashes,
    promotion_bundle = PAGe::hash_file_sha256(acceptance_bundle_path)
  )
  promotion_expect_hashes(
    acceptance_manifest$provenance$source_artifact_hashes,
    acceptance_hashes,
    "acceptance"
  )
  if (!identical(acceptance_manifest$provenance$spec_id, candidate$spec_id) ||
    !holdout_season %in%
      as.character(acceptance_manifest$provenance$evaluation_seasons)) {
    promotion_abort(
      "Acceptance manifest does not identify the accepted candidate and holdout season."
    )
  }
  list(
    candidate = candidate,
    candidate_config = candidate_config,
    incumbent = incumbent,
    bundle_hashes = bundle_hashes,
    acceptance_hashes = acceptance_hashes,
    acceptance_manifest_hash =
      PAGe::hash_file_sha256(acceptance_manifest_path)
  )
}

promotion_validate_refit <- function(
  refit_artifact_path,
  refit_manifest_path,
  refit_result,
  refit_manifest,
  acceptance,
  holdout_season
) {
  refit_manifest <- promotion_validate_manifest(
    refit_manifest, "post_promotion_refit", "post-promotion refit"
  )
  expected_refit_hashes <- c(
    authorized_data = acceptance$bundle_hashes[["authorized_data"]],
    candidate = acceptance$bundle_hashes[["candidate"]],
    promotion_bundle = acceptance$acceptance_hashes[["promotion_bundle"]],
    promotion_manifest = acceptance$acceptance_manifest_hash,
    refit_artifact = PAGe::hash_file_sha256(refit_artifact_path)
  )
  actual_refit_hash <-
    refit_manifest$provenance$source_artifact_hashes[["refit_artifact"]]
  if (!identical(
    actual_refit_hash,
    expected_refit_hashes[["refit_artifact"]]
  )) {
    promotion_abort("Refit artifact SHA-256 does not match its manifest.")
  }
  promotion_expect_hashes(
    refit_manifest$provenance$source_artifact_hashes,
    expected_refit_hashes,
    "post-promotion refit"
  )
  if (!is.list(refit_result) || !is.list(refit_result$kit) ||
    !is.list(refit_result$holdout) ||
    !identical(refit_result$holdout$status, "released")) {
    promotion_abort(
      "Refit artifact must contain a released holdout and a final kit."
    )
  }
  promoted <- promotion_kit_identity(
    refit_result$kit, "post-promotion refit", holdout_season, TRUE
  )
  accepted <- acceptance$candidate
  if (!identical(promoted$spec_id, accepted$spec_id) ||
    !identical(promoted$spec, accepted$spec) ||
    !identical(refit_manifest$provenance$spec_id, accepted$spec_id)) {
    promotion_abort(
      "Post-promotion refit does not use the exact accepted candidate spec."
    )
  }
  config <- acceptance$candidate_config
  components <- refit_result$components
  fixed_config_matches <- is.list(components) &&
    is.list(components$m0) &&
    is.list(components$m1) &&
    identical(refit_result$kit$best_spec, config$best_spec) &&
    identical(refit_result$kit$m2_production$spec, config$best_spec) &&
    identical(components$m0$best_params, config$m0_params) &&
    identical(components$m0$manual_labels, config$manual_labels) &&
    identical(components$m0$flag_args, config$flag_args) &&
    identical(components$m1$m1_params, config$m1_params)
  if (!isTRUE(fixed_config_matches)) {
    promotion_abort(
      "Post-promotion refit changed the fixed M0, M1, and runtime configuration."
    )
  }
  manifest_training <- as.character(
    refit_manifest$provenance$training_seasons
  )
  if (!identical(manifest_training, promoted$training_seasons) ||
    !holdout_season %in% manifest_training) {
    promotion_abort(
      "Refit manifest training seasons do not match the released final kit."
    )
  }
  list(
    kit = refit_result$kit,
    identity = promoted,
    source_hashes = expected_refit_hashes,
    refit_manifest_hash = PAGe::hash_file_sha256(refit_manifest_path)
  )
}

promotion_output_paths <- function(registry_dir, audit_dir, deployment_id) {
  registry_deployment_dir <- file.path(registry_dir, deployment_id)
  audit_deployment_dir <- file.path(audit_dir, deployment_id)
  list(
    registry_deployment_dir = registry_deployment_dir,
    audit_deployment_dir = audit_deployment_dir,
    promoted_kit_path = file.path(
      registry_deployment_dir, "promoted_kit.rds"
    ),
    manifest_json_path = file.path(
      audit_deployment_dir, "deployment_manifest.json"
    ),
    manifest_markdown_path = file.path(
      audit_deployment_dir, "deployment_manifest.md"
    )
  )
}

promotion_assert_no_collision <- function(paths, deployment_id) {
  destinations <- unlist(paths[c(
    "registry_deployment_dir", "audit_deployment_dir"
  )], use.names = FALSE)
  if (any(file.exists(destinations) | dir.exists(destinations))) {
    promotion_abort(
      paste0(
        "Immutable promotion output already exists for deployment ID `",
        deployment_id, "`."
      )
    )
  }
  invisible(TRUE)
}

promotion_input_fingerprint <- function(hashes) {
  digest::digest(
    paste(names(hashes), unname(hashes), collapse = "|"),
    algo = "sha256",
    serialize = FALSE
  )
}

promotion_build_manifest <- function(
  refit,
  upstream_hashes,
  code_commit,
  run_timestamp
) {
  PAGe::new_result_manifest(
    artifact_role = "promoted_deployment_kit",
    classification = "disclosure_safe",
    code_commit = code_commit,
    run_timestamp = run_timestamp,
    r_version = as.character(getRversion()),
    package_versions = c(
      PAGe = as.character(utils::packageVersion("PAGe"))
    ),
    input_fingerprint = promotion_input_fingerprint(upstream_hashes),
    seasons = refit$identity$training_seasons,
    exclusions = "none",
    row_counts = c(
      training_seasons = length(refit$identity$training_seasons)
    ),
    spec_id = refit$identity$spec_id,
    training_seasons = refit$identity$training_seasons,
    source_artifact_hashes = upstream_hashes,
    fold_ids = "none",
    evaluation_seasons = "none"
  )
}

promotion_manifest_markdown <- function(manifest, deployment_id) {
  provenance <- manifest$provenance
  c(
    "# PAGe immutable deployment manifest",
    "",
    paste0("- Deployment ID: `", deployment_id, "`"),
    paste0("- Spec ID: `", provenance$spec_id, "`"),
    paste0(
      "- Training seasons: ",
      paste(provenance$training_seasons, collapse = ", ")
    ),
    "- Artifact role: `promoted_deployment_kit`",
    "- Source SHA-256 hashes:",
    vapply(
      names(provenance$source_artifact_hashes),
      function(name) {
        paste0(
          "  - ", name, ": `",
          provenance$source_artifact_hashes[[name]], "`"
        )
      },
      character(1)
    ),
    "",
    "This manifest contains aggregate provenance only. No mutable current alias was created."
  )
}

promote_post_refit <- function(
  data_path,
  acceptance_bundle_path,
  acceptance_manifest_path,
  candidate_path,
  incumbent_path,
  refit_artifact_path,
  refit_manifest_path,
  registry_dir,
  audit_dir,
  deployment_id = NULL,
  holdout_season = "2025-26",
  kit_compatibility = c("strict", "legacy_m2"),
  preflight_only = FALSE,
  read_manifest = function(path) PAGe::read_result_manifest(path),
  write_manifest = function(manifest, path, overwrite = FALSE) {
    PAGe::write_result_manifest(manifest, path, overwrite = overwrite)
  },
  save_rds = saveRDS,
  write_lines = writeLines,
  create_dir = function(path, recursive = FALSE, showWarnings = FALSE) {
    dir.create(
      path,
      recursive = recursive,
      showWarnings = showWarnings
    )
  },
  rename_path = file.rename,
  code_commit = NULL,
  run_timestamp = format(
    Sys.time(), "%Y-%m-%dT%H:%M:%SZ",
    tz = "UTC"
  )
) {
  kit_compatibility <- match.arg(kit_compatibility)
  inputs <- c(
    authorized_data = data_path,
    acceptance_bundle = acceptance_bundle_path,
    acceptance_manifest = acceptance_manifest_path,
    candidate_kit = candidate_path,
    incumbent_kit = incumbent_path,
    refit_artifact = refit_artifact_path,
    refit_manifest = refit_manifest_path
  )
  promotion_require_files(inputs)
  promotion_validate_authorized_data(data_path, holdout_season)
  if (!promotion_is_nonempty_scalar(registry_dir) ||
    !promotion_is_nonempty_scalar(audit_dir) ||
    identical(
      normalizePath(registry_dir, mustWork = FALSE),
      normalizePath(audit_dir, mustWork = FALSE)
    )) {
    promotion_abort("Private registry and disclosure-safe audit directories must differ.")
  }
  if (!is.logical(preflight_only) || length(preflight_only) != 1L ||
    is.na(preflight_only)) {
    promotion_abort("`preflight_only` must be TRUE or FALSE.")
  }
  if (!promotion_is_nonempty_scalar(code_commit) ||
    !grepl("^[0-9a-f]{7,64}$", code_commit)) {
    promotion_abort(
      "A 7-64 character lowercase Git commit hash is required for promotion."
    )
  }

  acceptance_bundle <- readRDS(acceptance_bundle_path)
  acceptance_manifest <- read_manifest(acceptance_manifest_path)
  candidate_kit <- readRDS(candidate_path)
  incumbent_kit <- readRDS(incumbent_path)
  refit_result <- readRDS(refit_artifact_path)
  refit_manifest <- read_manifest(refit_manifest_path)
  acceptance <- promotion_validate_acceptance(
    data_path = data_path,
    acceptance_bundle_path = acceptance_bundle_path,
    acceptance_manifest_path = acceptance_manifest_path,
    candidate_path = candidate_path,
    incumbent_path = incumbent_path,
    acceptance_bundle = acceptance_bundle,
    acceptance_manifest = acceptance_manifest,
    candidate_kit = candidate_kit,
    incumbent_kit = incumbent_kit,
    holdout_season = holdout_season,
    kit_compatibility = kit_compatibility
  )
  refit <- promotion_validate_refit(
    refit_artifact_path = refit_artifact_path,
    refit_manifest_path = refit_manifest_path,
    refit_result = refit_result,
    refit_manifest = refit_manifest,
    acceptance = acceptance,
    holdout_season = holdout_season
  )

  if (is.null(deployment_id)) {
    deployment_id <- paste0(
      "deployment-",
      format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"),
      "-",
      substr(refit$refit_manifest_hash, 1L, 12L)
    )
  }
  deployment_id <- promotion_validate_id(deployment_id)
  final_paths <- promotion_output_paths(
    registry_dir, audit_dir, deployment_id
  )
  promotion_assert_no_collision(final_paths, deployment_id)
  if (isTRUE(preflight_only)) {
    return(list(
      preflight = TRUE,
      deployment_id = deployment_id,
      spec_id = refit$identity$spec_id,
      training_seasons = refit$identity$training_seasons,
      paths = final_paths
    ))
  }

  create_dir(registry_dir, recursive = TRUE, showWarnings = FALSE)
  create_dir(audit_dir, recursive = TRUE, showWarnings = FALSE)
  registry_stage <- tempfile(
    paste0(".promotion-", deployment_id, "-"),
    tmpdir = registry_dir
  )
  audit_stage <- tempfile(
    paste0(".promotion-", deployment_id, "-"),
    tmpdir = audit_dir
  )
  on.exit(
    {
      if (dir.exists(registry_stage)) {
        unlink(registry_stage, recursive = TRUE, force = TRUE)
      }
      if (dir.exists(audit_stage)) {
        unlink(audit_stage, recursive = TRUE, force = TRUE)
      }
    },
    add = TRUE
  )
  if (!create_dir(registry_stage, showWarnings = FALSE) ||
    !create_dir(audit_stage, showWarnings = FALSE)) {
    promotion_abort("Could not create private promotion staging directories.")
  }

  staged_kit <- file.path(registry_stage, "promoted_kit.rds")
  staged_json <- file.path(audit_stage, "deployment_manifest.json")
  staged_markdown <- file.path(audit_stage, "deployment_manifest.md")
  save_rds(refit$kit, staged_kit)
  upstream_hashes <- c(
    authorized_data = acceptance$bundle_hashes[["authorized_data"]],
    candidate = acceptance$bundle_hashes[["candidate"]],
    incumbent = acceptance$bundle_hashes[["incumbent"]],
    acceptance_bundle =
      acceptance$acceptance_hashes[["promotion_bundle"]],
    acceptance_manifest = acceptance$acceptance_manifest_hash,
    refit_artifact = refit$source_hashes[["refit_artifact"]],
    refit_manifest = refit$refit_manifest_hash,
    promoted_kit = PAGe::hash_file_sha256(staged_kit)
  )
  manifest <- promotion_build_manifest(
    refit = refit,
    upstream_hashes = upstream_hashes,
    code_commit = code_commit,
    run_timestamp = run_timestamp
  )
  PAGe::validate_result_manifest(manifest)
  write_manifest(manifest, staged_json, overwrite = FALSE)
  write_lines(
    promotion_manifest_markdown(manifest, deployment_id),
    staged_markdown,
    useBytes = TRUE
  )
  written_manifest <- read_manifest(staged_json)
  promotion_validate_manifest(
    written_manifest, "promoted_deployment_kit", "written deployment"
  )
  if (!identical(
    written_manifest$provenance$source_artifact_hashes,
    manifest$provenance$source_artifact_hashes
  )) {
    promotion_abort("Written deployment manifest did not preserve source hashes.")
  }

  promotion_assert_no_collision(final_paths, deployment_id)
  if (!rename_path(
    registry_stage,
    final_paths$registry_deployment_dir
  )) {
    promotion_abort("Could not publish the immutable private deployment directory.")
  }
  if (!identical(
    PAGe::hash_file_sha256(final_paths$promoted_kit_path),
    upstream_hashes[["promoted_kit"]]
  )) {
    unlink(
      final_paths$registry_deployment_dir,
      recursive = TRUE,
      force = TRUE
    )
    promotion_abort("Published kit SHA-256 changed during promotion.")
  }
  if (file.exists(final_paths$audit_deployment_dir) ||
    dir.exists(final_paths$audit_deployment_dir) ||
    !rename_path(audit_stage, final_paths$audit_deployment_dir)) {
    unlink(
      final_paths$registry_deployment_dir,
      recursive = TRUE,
      force = TRUE
    )
    promotion_abort(
      "Could not publish the immutable deployment audit directory."
    )
  }
  c(
    list(
      preflight = FALSE,
      deployment_id = deployment_id,
      manifest = manifest
    ),
    final_paths[c(
      "promoted_kit_path", "manifest_json_path", "manifest_markdown_path"
    )]
  )
}
