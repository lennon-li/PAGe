#' Read a PAGe result manifest
#'
#' Reads a canonical disclosure-safe result manifest from JSON or RDS and
#' validates its schema before returning it.
#'
#' @param path Path to a manifest with a \code{.json} or \code{.rds} extension.
#'
#' @return A validated \code{page_result_manifest} object.
#' @export
read_result_manifest <- function(path) {
  extension <- .result_manifest_extension(path)
  if (!file.exists(path) || dir.exists(path)) {
    stop("Result manifest does not exist or is not a regular file: `", path, "`.",
      call. = FALSE
    )
  }

  manifest <- tryCatch(
    switch(extension,
      json = {
        .require_jsonlite()
        .coerce_json_result_manifest(
          jsonlite::fromJSON(path, simplifyVector = TRUE)
        )
      },
      rds = readRDS(path)
    ),
    error = function(error) {
      stop(
        "Could not read result manifest `", path, "`: ",
        conditionMessage(error),
        call. = FALSE
      )
    }
  )
  if (!inherits(manifest, "page_result_manifest")) {
    class(manifest) <- c("page_result_manifest", setdiff(class(manifest), "page_result_manifest"))
  }
  validate_result_manifest(manifest)
  manifest
}

#' Write a PAGe result manifest
#'
#' Validates and writes a canonical result manifest as JSON or RDS. Existing
#' files are immutable by default and are never replaced unless
#' \code{overwrite = TRUE} is explicit.
#'
#' @param manifest A manifest created by [new_result_manifest()].
#' @param path Destination path with a \code{.json} or \code{.rds} extension.
#' @param overwrite Whether to replace an existing file. Defaults to
#'   \code{FALSE}.
#'
#' @return Invisibly, the normalized path to the written manifest.
#' @export
write_result_manifest <- function(manifest, path, overwrite = FALSE) {
  validate_result_manifest(manifest)
  extension <- .result_manifest_extension(path)
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE.", call. = FALSE)
  }
  parent <- dirname(path)
  if (!dir.exists(parent)) {
    stop("Manifest parent directory does not exist: `", parent, "`.", call. = FALSE)
  }
  if (dir.exists(path)) {
    stop("Manifest path is a directory: `", path, "`.", call. = FALSE)
  }
  if (file.exists(path) && !overwrite) {
    stop("Result manifest already exists and will not be overwritten: `", path, "`.",
      call. = FALSE
    )
  }

  temporary <- tempfile(
    pattern = ".page-result-manifest-",
    tmpdir = parent,
    fileext = paste0(".", extension)
  )
  on.exit(unlink(temporary), add = TRUE)
  switch(extension,
    json = {
      .require_jsonlite()
      jsonlite::write_json(
        .result_manifest_json_payload(manifest),
        path = temporary,
        auto_unbox = TRUE,
        pretty = TRUE,
        null = "null"
      )
    },
    rds = saveRDS(manifest, temporary)
  )
  read_result_manifest(temporary)

  if (!overwrite && file.exists(path)) {
    stop("Result manifest appeared during write and will not be overwritten: `", path, "`.",
      call. = FALSE
    )
  }
  installed <- file.copy(temporary, path, overwrite = overwrite)
  if (!isTRUE(installed)) {
    stop("Could not install result manifest at `", path, "`.", call. = FALSE)
  }
  read_result_manifest(path)
  invisible(normalizePath(path, mustWork = TRUE))
}

#' Load a promoted PAGe deployment kit
#'
#' Loads a deployment kit only after its disclosure-safe promotion manifest,
#' artifact fingerprint, selected specification, training seasons, and runtime
#' structure have all been verified.
#'
#' @param kit_path Path to an RDS file containing a PAGe kit or a
#'   \code{page_training_result} with a \code{kit} field.
#' @param deployment_manifest_path Path to the corresponding canonical result
#'   manifest.
#'
#' @return A kit validated by [validate_page_kit()] in frozen mode.
#' @export
load_promoted_kit <- function(kit_path, deployment_manifest_path) {
  manifest <- read_result_manifest(deployment_manifest_path)
  if (!identical(manifest$artifact$classification, "disclosure_safe")) {
    stop(
      "Deployment manifest classification must be `disclosure_safe`.",
      call. = FALSE
    )
  }
  if (!identical(manifest$artifact$role, "promoted_deployment_kit")) {
    stop(
      "Deployment manifest role must be `promoted_deployment_kit`; found `",
      manifest$artifact$role, "`.",
      call. = FALSE
    )
  }
  hashes <- manifest$provenance$source_artifact_hashes
  if (sum(names(hashes) == "promoted_kit") != 1L) {
    stop(
      "Deployment manifest source_artifact_hashes must contain `promoted_kit`.",
      call. = FALSE
    )
  }
  promoted_hash <- hashes[["promoted_kit"]]
  actual_hash <- hash_file_sha256(kit_path)
  if (!identical(unname(promoted_hash), actual_hash)) {
    stop("Promoted kit SHA-256 does not match the deployment manifest.",
      call. = FALSE
    )
  }

  artifact <- tryCatch(
    readRDS(kit_path),
    error = function(error) {
      stop(
        "Could not read promoted kit `", kit_path, "`: ",
        conditionMessage(error),
        call. = FALSE
      )
    }
  )
  if (!identical(hash_file_sha256(kit_path), actual_hash)) {
    stop("Promoted kit changed while it was being loaded.", call. = FALSE)
  }
  kit <- if (inherits(artifact, "page_training_result")) artifact$kit else artifact
  if (inherits(artifact, "page_training_result") && is.null(kit)) {
    stop("Promoted page_training_result artifact has no `kit` field.", call. = FALSE)
  }
  if (!is.list(kit)) {
    stop("Promoted artifact does not contain a PAGe kit list.", call. = FALSE)
  }
  if (!is.list(kit$m2_production$spec) ||
    !identical(kit$best_spec, kit$m2_production$spec)) {
    stop(
      "Promoted kit `best_spec` must exactly match `m2_production$spec`.",
      call. = FALSE
    )
  }

  kit_spec_id <- kit$m2_production$best_spec_id
  if (!is.character(kit_spec_id) || length(kit_spec_id) != 1L ||
    is.na(kit_spec_id) || !nzchar(kit_spec_id)) {
    stop("Promoted kit must record one `m2_production$best_spec_id`.", call. = FALSE)
  }
  if (!identical(manifest$provenance$spec_id, kit_spec_id)) {
    stop("Deployment manifest `spec_id` does not match the promoted kit.",
      call. = FALSE
    )
  }

  kit_training_seasons <- kit$m2_production$training_seasons
  if (!is.character(kit_training_seasons) || !length(kit_training_seasons) ||
    anyNA(kit_training_seasons) || any(!nzchar(kit_training_seasons))) {
    stop(
      "Promoted kit must record non-empty `m2_production$training_seasons`.",
      call. = FALSE
    )
  }
  if (!identical(manifest$provenance$training_seasons, kit_training_seasons)) {
    stop(
      "Deployment manifest `training_seasons` do not match the promoted kit.",
      call. = FALSE
    )
  }

  validate_page_kit(kit, mode = "frozen")
}

.result_manifest_extension <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    stop("`path` must be one non-empty file path.", call. = FALSE)
  }
  extension <- tolower(tools::file_ext(path))
  if (!extension %in% c("json", "rds")) {
    stop("Result manifest path must use a `.json` or `.rds` extension.",
      call. = FALSE
    )
  }
  extension
}

.require_jsonlite <- function() {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("JSON manifest support requires the `jsonlite` package.", call. = FALSE)
  }
}

.coerce_json_result_manifest <- function(manifest) {
  if (!is.list(manifest) || !is.list(manifest$provenance)) {
    return(manifest)
  }
  manifest$schema_version <- as.integer(manifest$schema_version)
  character_fields <- c(
    "code_commit", "run_timestamp", "r_version", "input_fingerprint",
    "seasons", "exclusions", "spec_id", "training_seasons", "fold_ids",
    "evaluation_seasons"
  )
  for (field in character_fields) {
    manifest$provenance[[field]] <- as.character(
      unlist(manifest$provenance[[field]], use.names = FALSE)
    )
  }
  manifest$provenance$package_versions <- .as_named_character(
    manifest$provenance$package_versions
  )
  manifest$provenance$source_artifact_hashes <- .as_named_character(
    manifest$provenance$source_artifact_hashes
  )
  manifest$provenance$row_counts <- .as_named_numeric(
    manifest$provenance$row_counts
  )
  manifest
}

.result_manifest_json_payload <- function(manifest) {
  payload <- unclass(manifest)
  named_fields <- c(
    "package_versions", "row_counts", "source_artifact_hashes"
  )
  for (field in named_fields) {
    payload$provenance[[field]] <- as.list(payload$provenance[[field]])
  }
  payload
}

.as_named_character <- function(x) {
  values <- unlist(x, use.names = TRUE)
  result <- as.character(values)
  names(result) <- names(values)
  result
}

.as_named_numeric <- function(x) {
  values <- unlist(x, use.names = TRUE)
  result <- as.numeric(values)
  names(result) <- names(values)
  result
}
