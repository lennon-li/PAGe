.promotion_evidence_schema <- function() "page_verified_promotion_evidence"

.promotion_evidence_schema_version <- function() 1L

.promotion_candidate_config <- function(kit) {
  m2 <- kit$m2_production
  required <- c("m0_params", "M1_PARAMS", "best_spec", "manual_labels", "flag_args")
  if (!is.list(kit) || !all(required %in% names(kit)) ||
    !is.list(m2) || !is.list(m2$spec) ||
    !identical(kit$best_spec, m2$spec)) {
    .promotion_evidence_abort(
      "the candidate kit does not contain a canonical refresh configuration."
    )
  }
  spec_id <- .promotion_spec_identity(m2)
  if (is.null(spec_id)) {
    .promotion_evidence_abort("the candidate kit has no stable M2 spec identity.")
  }
  list(
    m0_params = kit$m0_params,
    m1_params = kit$M1_PARAMS,
    best_spec = kit$best_spec,
    best_spec_id = spec_id,
    training_seasons = as.character(m2$training_seasons),
    manual_labels = kit$manual_labels,
    flag_args = kit$flag_args
  )
}

.promotion_evidence_data_fingerprint <- function(allD) {
  digest::digest(prepare_surveillance_data(allD), algo = "sha256")
}

.read_promotion_data <- function(path) {
  raw <- if (grepl("[.]rds$", path, ignore.case = TRUE)) {
    readRDS(path)
  } else {
    utils::read.csv(path, check.names = FALSE)
  }
  prepare_surveillance_data(raw)
}

.read_promotion_kit <- function(path, label) {
  kit <- tryCatch(
    readRDS(path),
    error = function(error) {
      .promotion_evidence_abort(
        paste0("the ", label, " kit could not be read: ", conditionMessage(error))
      )
    }
  )
  if (!is.list(kit)) {
    .promotion_evidence_abort(paste0("the ", label, " kit must be an R list."))
  }
  kit
}

.promotion_spec_identity <- function(m2) {
  for (field in c("best_spec_id", "spec_id")) {
    value <- m2[[field]]
    if (is.character(value) && length(value) == 1L &&
      !is.na(value) && nzchar(value)) {
      return(value)
    }
  }
  required <- c(
    "delta", "Kr", "k_f", "k_e", "alpha_state", "k_r", "k_de", "k_sp",
    "bias_alpha", "bias_beta"
  )
  spec <- m2$spec
  if (!is.list(spec) || is.null(names(spec)) ||
    !all(required %in% names(spec))) {
    return(NULL)
  }
  identity_spec <- spec[sort(required)]
  complete <- vapply(identity_spec, function(value) {
    is.atomic(value) && length(value) == 1L &&
      !is.na(value) && is.finite(value)
  }, logical(1))
  if (!all(complete)) {
    return(NULL)
  }
  paste0("spec_sha256_", digest::digest(identity_spec, algo = "sha256"))
}

.verify_promotion_kit <- function(path, label, holdout_season,
                                  compatibility = "strict") {
  kit <- .read_promotion_kit(path, label)
  m2 <- .resolve_kit_m2_identity(
    kit,
    compatibility = compatibility,
    label = paste(label, "kit")
  )
  if (!is.list(m2) || is.null(m2$training_seasons)) {
    .promotion_evidence_abort(
      paste0("the ", label, " kit is missing required `training_seasons`.")
    )
  }
  training_seasons <- as.character(m2$training_seasons)
  if (!length(training_seasons) || anyNA(training_seasons) ||
    any(!nzchar(training_seasons))) {
    .promotion_evidence_abort(
      paste0("the ", label, " kit has invalid `training_seasons`.")
    )
  }
  if (holdout_season %in% training_seasons) {
    .promotion_evidence_abort(
      paste0("the ", label, " kit includes the holdout in `training_seasons`.")
    )
  }
  spec_id <- .promotion_spec_identity(m2)
  if (is.null(spec_id)) {
    .promotion_evidence_abort(
      paste0("the ", label, " kit has no stable M2 spec identity.")
    )
  }
  list(spec_id = spec_id, training_seasons = training_seasons)
}

.promotion_evidence_abort <- function(message) {
  stop("Invalid verified promotion evidence: ", message, call. = FALSE)
}

.is_verified_promotion_evidence <- function(evidence, allD = NULL, holdout_season = NULL) {
  expected_names <- c(
    "schema", "schema_version", "holdout_season", "report",
    "source_artifact_hashes", "data_fingerprint", "candidate_config",
    "candidate_config_hash"
  )
  if (!inherits(evidence, "page_verified_promotion_evidence") ||
    !is.list(evidence) ||
    !identical(names(evidence), expected_names) ||
    !identical(evidence$schema, .promotion_evidence_schema()) ||
    !identical(evidence$schema_version, .promotion_evidence_schema_version()) ||
    !is.character(evidence$holdout_season) ||
    length(evidence$holdout_season) != 1L ||
    is.na(evidence$holdout_season) ||
    !nzchar(evidence$holdout_season) ||
    !.is_canonical_promotion_report(evidence$report, require_locked = TRUE) ||
    !isTRUE(evidence$report$pass) ||
    !is.character(evidence$source_artifact_hashes) ||
    anyDuplicated(names(evidence$source_artifact_hashes)) ||
    !setequal(
      names(evidence$source_artifact_hashes),
      c("authorized_data", "candidate", "incumbent", "promotion_bundle")
    ) ||
    !all(vapply(evidence$source_artifact_hashes, .is_sha256, logical(1))) ||
    !.is_sha256(evidence$data_fingerprint) ||
    !is.list(evidence$candidate_config) ||
    !.is_sha256(evidence$candidate_config_hash) ||
    !identical(
      evidence$candidate_config_hash,
      digest::digest(evidence$candidate_config, algo = "sha256")
    )) {
    return(FALSE)
  }
  if (!is.null(holdout_season) &&
    !identical(evidence$holdout_season, holdout_season)) {
    return(FALSE)
  }
  if (!is.null(allD) &&
    !identical(
      evidence$data_fingerprint,
      .promotion_evidence_data_fingerprint(allD)
    )) {
    return(FALSE)
  }
  TRUE
}

#' Verify artifact-bound holdout promotion evidence
#'
#' Verifies a saved acceptance decision bundle and disclosure-safe manifest
#' against the authorized data, candidate kit, incumbent kit, and decision
#' bundle files that they bind by SHA-256. Only a passing promotion report
#' using PAGe's locked thresholds can produce release evidence.
#'
#' The returned S3 class is a transport marker, not a cryptographic capability:
#' R classes can be forged. The artifact reads and SHA-256 checks performed by
#' this function are the safety boundary. Governed workflows should construct
#' the object immediately before calling \code{train_pipeline()} and retain the
#' verified artifacts.
#'
#' @param bundle Saved \code{page_holdout_decision_bundle} object.
#' @param manifest Validated disclosure-safe acceptance result manifest.
#' @param data_path Path to the authorized surveillance data artifact.
#' @param candidate_path Path to the evaluated candidate kit artifact.
#' @param incumbent_path Path to the evaluated incumbent kit artifact.
#' @param bundle_path Path to the saved decision bundle artifact.
#' @param holdout_season Expected holdout season.
#' @param kit_compatibility Identity mode for the incumbent kit. The default
#'   \code{"strict"} requires \code{m2_production}; \code{"legacy_m2"}
#'   explicitly permits a legacy \code{m2} field with a warning. The candidate
#'   kit must always use the canonical identity.
#'
#' @return A \code{page_verified_promotion_evidence} object accepted by
#'   \code{train_pipeline()} for holdout release.
#' @export
verify_promotion_evidence <- function(bundle,
                                      manifest,
                                      data_path,
                                      candidate_path,
                                      incumbent_path,
                                      bundle_path,
                                      holdout_season = "2025-26",
                                      kit_compatibility = c("strict", "legacy_m2")) {
  if (!is.character(holdout_season) || length(holdout_season) != 1L ||
    is.na(holdout_season) || !nzchar(holdout_season)) {
    .promotion_evidence_abort("`holdout_season` must be one non-empty string.")
  }
  kit_compatibility <- match.arg(kit_compatibility)
  paths <- c(
    authorized_data = data_path,
    candidate = candidate_path,
    incumbent = incumbent_path,
    promotion_bundle = bundle_path
  )
  if (!is.character(paths) || anyNA(paths) || any(!nzchar(paths))) {
    .promotion_evidence_abort("all artifact paths must be non-empty strings.")
  }
  saved_bundle <- .read_promotion_kit(bundle_path, "decision")
  if (!identical(bundle, saved_bundle)) {
    .promotion_evidence_abort(
      "the supplied decision bundle does not match the saved decision bundle."
    )
  }
  bundle <- saved_bundle
  actual_hashes <- vapply(paths, hash_file_sha256, character(1))

  expected_bundle_names <- c(
    "schema", "schema_version", "run_id", "created_at", "holdout_season",
    "report", "source_artifact_hashes"
  )
  if (!is.list(bundle) ||
    !identical(names(bundle), expected_bundle_names) ||
    !identical(bundle$schema, "page_holdout_decision_bundle") ||
    !identical(bundle$schema_version, 1L) ||
    !identical(bundle$holdout_season, holdout_season)) {
    .promotion_evidence_abort("the decision bundle schema or holdout season is invalid.")
  }
  if (!.is_canonical_promotion_report(bundle$report, require_locked = TRUE) ||
    !isTRUE(bundle$report$pass)) {
    .promotion_evidence_abort(
      "the decision bundle must contain a passing locked-threshold promotion report."
    )
  }
  bundle_hashes <- bundle$source_artifact_hashes
  source_names <- c("authorized_data", "candidate", "incumbent")
  if (!is.character(bundle_hashes) ||
    anyDuplicated(names(bundle_hashes)) ||
    !setequal(names(bundle_hashes), source_names) ||
    !all(vapply(bundle_hashes, .is_sha256, logical(1)))) {
    .promotion_evidence_abort("the decision bundle source hashes are invalid.")
  }
  for (name in source_names) {
    if (!identical(unname(bundle_hashes[[name]]), unname(actual_hashes[[name]]))) {
      .promotion_evidence_abort(paste0(name, " SHA-256 does not match the decision bundle."))
    }
  }

  validate_result_manifest(manifest)
  manifest_hashes <- manifest$provenance$source_artifact_hashes
  expected_manifest_names <- c(source_names, "promotion_bundle")
  if (!identical(manifest$artifact$role, "holdout_acceptance_decision") ||
    !identical(manifest$artifact$classification, "disclosure_safe") ||
    !identical(as.character(manifest$provenance$evaluation_seasons), holdout_season) ||
    !is.character(manifest_hashes) ||
    anyDuplicated(names(manifest_hashes)) ||
    !setequal(names(manifest_hashes), expected_manifest_names)) {
    .promotion_evidence_abort(
      "the result manifest is not a canonical acceptance manifest for the holdout."
    )
  }
  for (name in expected_manifest_names) {
    if (!identical(unname(manifest_hashes[[name]]), unname(actual_hashes[[name]]))) {
      .promotion_evidence_abort(paste0(name, " SHA-256 does not match the result manifest."))
    }
  }

  candidate <- .verify_promotion_kit(
    candidate_path, "candidate", holdout_season,
    compatibility = "strict"
  )
  candidate_config <- .promotion_candidate_config(
    .read_promotion_kit(candidate_path, "candidate")
  )
  incumbent <- .verify_promotion_kit(
    incumbent_path, "incumbent", holdout_season,
    compatibility = kit_compatibility
  )
  if (!identical(manifest$provenance$spec_id, candidate$spec_id)) {
    .promotion_evidence_abort(
      "the candidate kit spec identity does not match the result manifest."
    )
  }
  expected_training_seasons <- unique(c(
    candidate$training_seasons,
    incumbent$training_seasons
  ))
  if (!setequal(
    as.character(manifest$provenance$training_seasons),
    expected_training_seasons
  ) || holdout_season %in% manifest$provenance$training_seasons ||
    !holdout_season %in% as.character(manifest$provenance$seasons)) {
    .promotion_evidence_abort(
      "the manifest training or evaluation seasons do not match the bound kits."
    )
  }

  prepared_data <- .read_promotion_data(data_path)
  if (!holdout_season %in% as.character(prepared_data$season)) {
    .promotion_evidence_abort(
      "the authorized data does not contain the expected holdout season."
    )
  }
  structure(
    list(
      schema = .promotion_evidence_schema(),
      schema_version = .promotion_evidence_schema_version(),
      holdout_season = holdout_season,
      report = bundle$report,
      source_artifact_hashes = actual_hashes,
      data_fingerprint = .promotion_evidence_data_fingerprint(prepared_data),
      candidate_config = candidate_config,
      candidate_config_hash = digest::digest(candidate_config, algo = "sha256")
    ),
    class = c("page_verified_promotion_evidence", "list")
  )
}
