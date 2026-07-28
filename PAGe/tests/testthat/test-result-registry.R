registry_test_kit <- function() {
  fit <- structure(
    list(model = data.frame(logit_f_eff = 0, z_ema = 0, lead = 1L)),
    class = c("gam", "list")
  )
  list(
    m0_params = list(p_thresh = 0.005),
    ref = list(anchorWeek = 20),
    hyper = list(),
    M1_PARAMS = list(
      temperature = 0.25,
      rise_weight = 1,
      trough_weight = 0.1,
      peak_decay = 0.3,
      slope_weight = 8,
      slope_window = 6L,
      dynamic_temp = FALSE,
      dynamic_temp_pivot = 10L
    ),
    m2_production = list(
      fit = fit,
      best_spec_id = "spec-promoted",
      training_seasons = c("2024-25", "2025-26")
    ),
    best_spec = list(k_n = 0L, k_de = 0L, k_r = 0L, k_sp = 0L)
  )
}

registry_test_manifest <- function(kit_path,
                                   role = "promoted_deployment_kit",
                                   spec_id = "spec-promoted",
                                   training_seasons = c("2024-25", "2025-26")) {
  kit_hash <- PAGe::hash_file_sha256(kit_path)
  PAGe::new_result_manifest(
    artifact_role = role,
    classification = "disclosure_safe",
    code_commit = "ab3aeb6",
    run_timestamp = "2026-07-28T12:00:00Z",
    r_version = "4.6.1",
    package_versions = c(PAGe = "0.2.0"),
    input_fingerprint = kit_hash,
    seasons = training_seasons,
    exclusions = "none",
    row_counts = c(training = 2L),
    spec_id = spec_id,
    training_seasons = training_seasons,
    source_artifact_hashes = c(promoted_kit = kit_hash),
    fold_ids = "none",
    evaluation_seasons = "none"
  )
}

test_that("result manifests round-trip through immutable RDS and JSON files", {
  kit_path <- tempfile(fileext = ".rds")
  saveRDS(registry_test_kit(), kit_path)
  manifest <- registry_test_manifest(kit_path)

  for (extension in c(".rds", ".json")) {
    path <- tempfile(fileext = extension)
    expect_identical(
      PAGe::write_result_manifest(manifest, path),
      normalizePath(path, mustWork = TRUE)
    )
    restored <- PAGe::read_result_manifest(path)
    expect_s3_class(restored, "page_result_manifest")
    expect_true(PAGe::validate_result_manifest(restored))
    expect_identical(restored$provenance$spec_id, "spec-promoted")
    expect_identical(
      restored$provenance$training_seasons,
      c("2024-25", "2025-26")
    )
  }
})

test_that("manifest writes reject collisions and unsupported formats", {
  kit_path <- tempfile(fileext = ".rds")
  saveRDS(registry_test_kit(), kit_path)
  manifest <- registry_test_manifest(kit_path)
  path <- tempfile(fileext = ".rds")

  PAGe::write_result_manifest(manifest, path)
  original_hash <- PAGe::hash_file_sha256(path)
  expect_error(
    PAGe::write_result_manifest(manifest, path),
    "already exists"
  )
  expect_identical(PAGe::hash_file_sha256(path), original_hash)
  expect_error(
    PAGe::write_result_manifest(manifest, tempfile(fileext = ".txt")),
    "extension"
  )
  expect_error(
    PAGe::read_result_manifest(tempfile(fileext = ".txt")),
    "extension"
  )
})

test_that("manifest readers fail closed on malformed or invalid files", {
  malformed <- tempfile(fileext = ".json")
  writeLines("{not-json", malformed)
  expect_error(PAGe::read_result_manifest(malformed), "Could not read")

  invalid <- tempfile(fileext = ".rds")
  saveRDS(list(schema = "not-a-manifest"), invalid)
  expect_error(PAGe::read_result_manifest(invalid), "Invalid result manifest")
})

test_that("promoted kits load from full-kit and training-result artifacts", {
  for (wrap_training_result in c(FALSE, TRUE)) {
    kit <- registry_test_kit()
    artifact <- if (wrap_training_result) {
      structure(list(kit = kit), class = c("page_training_result", "list"))
    } else {
      kit
    }
    kit_path <- tempfile(fileext = ".rds")
    manifest_path <- tempfile(fileext = ".json")
    saveRDS(artifact, kit_path)
    PAGe::write_result_manifest(
      registry_test_manifest(kit_path),
      manifest_path
    )

    loaded <- PAGe::load_promoted_kit(kit_path, manifest_path)
    expect_identical(
      loaded$m2_production$best_spec_id,
      "spec-promoted"
    )
    expect_identical(
      loaded$m2_production$training_seasons,
      c("2024-25", "2025-26")
    )
  }
})

test_that("promoted-kit loading rejects wrong roles and tampering", {
  kit_path <- tempfile(fileext = ".rds")
  manifest_path <- tempfile(fileext = ".rds")
  saveRDS(registry_test_kit(), kit_path)
  PAGe::write_result_manifest(
    registry_test_manifest(kit_path, role = "candidate_deployment_kit"),
    manifest_path
  )
  expect_error(
    PAGe::load_promoted_kit(kit_path, manifest_path),
    "promoted_deployment_kit"
  )

  PAGe::write_result_manifest(
    registry_test_manifest(kit_path),
    manifest_path,
    overwrite = TRUE
  )
  writeBin(charToRaw("tamper"), kit_path)
  expect_error(
    PAGe::load_promoted_kit(kit_path, manifest_path),
    "SHA-256"
  )
})

test_that("promoted-kit loading explicitly rejects private manifests", {
  kit_path <- tempfile(fileext = ".rds")
  saveRDS(registry_test_kit(), kit_path)
  manifest <- registry_test_manifest(kit_path)
  manifest$artifact$classification <- "private"
  testthat::local_mocked_bindings(
    read_result_manifest = function(path) manifest,
    .package = "PAGe"
  )

  expect_error(
    PAGe::load_promoted_kit(kit_path, tempfile(fileext = ".rds")),
    "disclosure_safe"
  )
})

test_that("promoted-kit loading enforces manifest and kit identity", {
  kit_path <- tempfile(fileext = ".rds")
  manifest_path <- tempfile(fileext = ".rds")
  saveRDS(registry_test_kit(), kit_path)

  PAGe::write_result_manifest(
    registry_test_manifest(kit_path, spec_id = "wrong-spec"),
    manifest_path
  )
  expect_error(
    PAGe::load_promoted_kit(kit_path, manifest_path),
    "spec_id"
  )

  PAGe::write_result_manifest(
    registry_test_manifest(kit_path, training_seasons = "2025-26"),
    manifest_path,
    overwrite = TRUE
  )
  expect_error(
    PAGe::load_promoted_kit(kit_path, manifest_path),
    "training_seasons"
  )
})

test_that("promoted-kit loading rejects missing hashes and invalid kits", {
  kit_path <- tempfile(fileext = ".rds")
  manifest_path <- tempfile(fileext = ".rds")
  saveRDS(registry_test_kit(), kit_path)
  manifest <- registry_test_manifest(kit_path)
  manifest$provenance$source_artifact_hashes <- c(
    source = manifest$provenance$source_artifact_hashes[[1L]]
  )
  saveRDS(manifest, manifest_path)
  expect_error(
    PAGe::load_promoted_kit(kit_path, manifest_path),
    "promoted_kit"
  )

  invalid_kit <- registry_test_kit()
  invalid_kit$m0_params <- NULL
  saveRDS(invalid_kit, kit_path)
  PAGe::write_result_manifest(
    registry_test_manifest(kit_path),
    manifest_path,
    overwrite = TRUE
  )
  expect_error(
    PAGe::load_promoted_kit(kit_path, manifest_path),
    "m0_params"
  )
})
