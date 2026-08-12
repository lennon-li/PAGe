test_that("a disclosure-safe result manifest validates", {
  manifest <- PAGe::new_result_manifest(
    artifact_role = "evaluation_summary",
    classification = "disclosure_safe",
    code_commit = "ab3aeb6",
    run_timestamp = "2026-07-28T12:00:00Z",
    r_version = "4.4.1",
    package_versions = c(PAGe = "0.2.0", digest = "0.6.37"),
    input_fingerprint = paste(rep("a", 64L), collapse = ""),
    seasons = c("2024-25", "2025-26"),
    exclusions = "none",
    row_counts = c(training = 120L, evaluation = 20L),
    spec_id = "m2_v16",
    training_seasons = "2024-25",
    source_artifact_hashes = c(
      training_input = paste(rep("b", 64L), collapse = "")
    ),
    fold_ids = c("fold_2024-25", "fold_2025-26"),
    evaluation_seasons = "2025-26"
  )

  expect_s3_class(manifest, "page_result_manifest")
  expect_identical(manifest$schema, "page_result_manifest")
  expect_identical(manifest$schema_version, 1L)
  expect_true(PAGe::validate_result_manifest(manifest))
})

test_that("result manifests fail precisely for required provenance fields", {
  manifest <- PAGe::new_result_manifest(
    artifact_role = "evaluation_summary",
    classification = "disclosure_safe",
    code_commit = "ab3aeb6",
    run_timestamp = "2026-07-28T12:00:00Z",
    r_version = "4.4.1",
    package_versions = c(PAGe = "0.2.0"),
    input_fingerprint = paste(rep("a", 64L), collapse = ""),
    seasons = "2025-26", exclusions = "none", row_counts = c(evaluation = 20L),
    spec_id = "m2_v16", training_seasons = "2024-25",
    source_artifact_hashes = c(input = paste(rep("b", 64L), collapse = "")),
    fold_ids = "fold_2025-26", evaluation_seasons = "2025-26"
  )
  manifest$provenance$code_commit <- NULL

  expect_error(PAGe::validate_result_manifest(manifest), "code_commit")
})

test_that("result manifests reject invalid hashes and row-level payloads", {
  manifest <- PAGe::new_result_manifest(
    artifact_role = "evaluation_summary",
    classification = "disclosure_safe",
    code_commit = "ab3aeb6",
    run_timestamp = "2026-07-28T12:00:00Z",
    r_version = "4.4.1",
    package_versions = c(PAGe = "0.2.0"),
    input_fingerprint = paste(rep("a", 64L), collapse = ""),
    seasons = "2025-26", exclusions = "none", row_counts = c(evaluation = 20L),
    spec_id = "m2_v16", training_seasons = "2024-25",
    source_artifact_hashes = c(input = paste(rep("b", 64L), collapse = "")),
    fold_ids = "fold_2025-26", evaluation_seasons = "2025-26"
  )
  manifest$provenance$source_artifact_hashes[[1L]] <- "not-a-hash"
  expect_error(PAGe::validate_result_manifest(manifest), "SHA-256")

  manifest$provenance$source_artifact_hashes[[1L]] <- paste(rep("b", 64L), collapse = "")
  manifest$predictions <- data.frame(p_hat = 0.2)
  expect_error(PAGe::validate_result_manifest(manifest), "row-level")
})

test_that("file hashing uses the SHA-256 digest and reports missing paths", {
  path <- tempfile("page-hash-")
  writeBin(charToRaw("abc"), path)
  withr::defer(unlink(path))

  expect_identical(
    PAGe::hash_file_sha256(path),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  )
  expect_error(PAGe::hash_file_sha256(paste0(path, "-missing")), "does not exist")
})
