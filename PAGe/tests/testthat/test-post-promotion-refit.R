refit_workflow_helper <- testthat::test_path(
  "..", "..", "..", "season2526", "refit_helpers.R"
)
if (!file.exists(refit_workflow_helper)) {
  testthat::skip(
    "Repository post-promotion refit helper is not included in package tarballs."
  )
}
source(refit_workflow_helper)

refit_hash <- function(char = "a") paste(rep(char, 64L), collapse = "")

refit_passing_report <- function() {
  report <- PAGe::check_promotion(
    list(
      overall = data.frame(bernoulli_nll = 0.48),
      horizon = data.frame(lead = c("1", "2"), mae = c(0.103, 0.103)),
      phase = data.frame(phase = c("early", "late"), mae = c(0.105, 0.105))
    ),
    list(
      overall = data.frame(bernoulli_nll = 0.50),
      horizon = data.frame(lead = c("1", "2"), mae = c(0.10, 0.10)),
      phase = data.frame(phase = c("early", "late"), mae = c(0.10, 0.10))
    )
  )
  expect_true(report$pass)
  report
}

refit_candidate_kit <- function() {
  list(
    best_spec = list(k_f = 4L), m0_params = list(p_thr = .005),
    M1_PARAMS = list(k_ref = 25L), manual_labels = c("2024-25" = 23L),
    flag_args = list(p_thresh = .01),
    m2_production = list(
      best_spec_id = "locked-v16",
      spec = list(k_f = 4L),
      training_seasons = "2024-25"
    )
  )
}

refit_incumbent_path <- function(candidate_path) {
  paste0(candidate_path, ".incumbent.rds")
}

refit_bundle <- function(data_path, candidate_path, report = refit_passing_report()) {
  incumbent_path <- refit_incumbent_path(candidate_path)
  saveRDS(
    list(m2_production = list(
      best_spec_id = "incumbent",
      training_seasons = "2024-25"
    )),
    incumbent_path
  )
  withr::defer(unlink(incumbent_path), envir = parent.frame())
  hashes <- c(
    authorized_data = PAGe::hash_file_sha256(data_path),
    candidate = PAGe::hash_file_sha256(candidate_path),
    incumbent = PAGe::hash_file_sha256(incumbent_path)
  )
  list(
    schema = "page_holdout_decision_bundle", schema_version = 1L,
    run_id = "acceptance-2025-26", created_at = "2026-07-28T12:00:00Z",
    holdout_season = "2025-26", report = report,
    source_artifact_hashes = hashes
  )
}

refit_promotion_manifest <- function(bundle, bundle_path) {
  hashes <- c(
    bundle$source_artifact_hashes,
    promotion_bundle = PAGe::hash_file_sha256(bundle_path)
  )
  PAGe::new_result_manifest(
    artifact_role = "holdout_acceptance_decision", classification = "disclosure_safe",
    code_commit = "ab3aeb6", run_timestamp = "2026-07-28T12:00:00Z",
    r_version = "4.4.1", package_versions = c(PAGe = "0.2.0"),
    input_fingerprint = hashes[["authorized_data"]], seasons = "2025-26",
    exclusions = "none", row_counts = c(evaluation = 1L), spec_id = "locked-v16",
    training_seasons = "2024-25", source_artifact_hashes = hashes,
    fold_ids = "none", evaluation_seasons = "2025-26"
  )
}

refit_result <- function(status = "released", seasons = c("2024-25", "2025-26"),
                         spec_id = "selected-spec") {
  list(
    holdout = list(status = status),
    selection = list(selected_spec_id = spec_id),
    kit = list(m2_production = list(training_seasons = seasons))
  )
}

test_that("post-promotion preflight rejects malformed, custom, and failed reports", {
  data_path <- tempfile(fileext = ".rds")
  candidate_path <- tempfile(fileext = ".rds")
  saveRDS(data.frame(x = 1), data_path)
  saveRDS(refit_candidate_kit(), candidate_path)
  withr::defer(unlink(c(data_path, candidate_path)))
  bundle <- refit_bundle(data_path, candidate_path)

  malformed <- bundle
  malformed$report <- list(pass = TRUE)
  expect_error(page_validate_promotion_bundle(malformed, data_path = data_path), "canonical")

  custom <- bundle
  custom$report$thresholds$min_nll_improvement <- 0.01
  custom$report$gates$threshold[custom$report$gates$gate == "nll"] <- 0.01
  expect_error(page_validate_promotion_bundle(custom, data_path = data_path), "canonical")

  failed <- bundle
  failed$report$pass <- FALSE
  expect_error(page_validate_promotion_bundle(failed, data_path = data_path), "canonical")
})

test_that("post-promotion preflight accepts a bound passing report", {
  data_path <- tempfile(fileext = ".rds")
  bundle_path <- tempfile(fileext = ".rds")
  candidate_path <- tempfile(fileext = ".rds")
  saveRDS(data.frame(x = 1), data_path)
  saveRDS(refit_candidate_kit(), candidate_path)
  bundle <- refit_bundle(data_path, candidate_path)
  saveRDS(bundle, bundle_path)
  manifest <- refit_promotion_manifest(bundle, bundle_path)
  withr::defer(unlink(c(data_path, bundle_path, candidate_path)))

  expect_s3_class(page_validate_promotion_bundle(bundle, data_path = data_path), "page_promotion_report")
  expect_true(page_validate_promotion_manifest(manifest, bundle, bundle_path))
  expect_equal(
    page_candidate_refit_config(readRDS(candidate_path), candidate_path, bundle, manifest)$spec_id,
    "locked-v16"
  )

  permuted_bundle <- bundle
  permuted_bundle$source_artifact_hashes <- bundle$source_artifact_hashes[c(
    "incumbent", "authorized_data", "candidate"
  )]
  expect_s3_class(
    page_validate_promotion_bundle(permuted_bundle, data_path = data_path),
    "page_promotion_report"
  )

  unbound_manifest <- manifest
  unbound_manifest$provenance$source_artifact_hashes[["promotion_bundle"]] <- refit_hash("d")
  expect_error(
    page_validate_promotion_manifest(unbound_manifest, bundle, bundle_path),
    "do not bind"
  )

  unknown_bundle <- bundle
  names(unknown_bundle$source_artifact_hashes)[[1L]] <- "unknown"
  expect_error(page_validate_promotion_bundle(unknown_bundle), "SHA-256")
  duplicate_bundle <- bundle
  names(duplicate_bundle$source_artifact_hashes)[[2L]] <- "authorized_data"
  expect_error(page_validate_promotion_bundle(duplicate_bundle), "SHA-256")

  tampered_candidate <- refit_candidate_kit()
  tampered_candidate$m0_params$p_thr <- .01
  tampered_path <- tempfile(fileext = ".rds")
  saveRDS(tampered_candidate, tampered_path)
  withr::defer(unlink(tampered_path))
  expect_error(
    page_candidate_refit_config(tampered_candidate, tampered_path, bundle, manifest),
    "SHA-256"
  )
  wrong_spec <- readRDS(candidate_path)
  wrong_spec$m2_production$best_spec_id <- "other-spec"
  expect_error(page_candidate_refit_config(wrong_spec, candidate_path, bundle, manifest), "spec identity")
  wrong_component_spec <- readRDS(candidate_path)
  wrong_component_spec$m2_production$spec <- list(k_f = 5L)
  expect_error(page_candidate_refit_config(wrong_component_spec, candidate_path, bundle, manifest), "lacks fixed")

  json_path <- tempfile(fileext = ".json")
  json_manifest <- unclass(manifest)
  json_manifest$provenance$package_versions <- as.list(manifest$provenance$package_versions)
  json_manifest$provenance$source_artifact_hashes <- as.list(manifest$provenance$source_artifact_hashes)
  json_manifest$provenance$row_counts <- as.list(manifest$provenance$row_counts)
  jsonlite::write_json(json_manifest, json_path, auto_unbox = TRUE)
  withr::defer(unlink(json_path))
  expect_true(page_validate_promotion_manifest(page_read_promotion_manifest(json_path), bundle, bundle_path))
})

test_that("postconditions prevent every output on an unreleased or incomplete refit", {
  data_path <- tempfile(fileext = ".rds")
  bundle_path <- tempfile(fileext = ".rds")
  candidate_path <- tempfile(fileext = ".rds")
  allD <- workflow_surveillance("2025-26", 1L)
  saveRDS(allD, data_path)
  candidate_kit <- refit_candidate_kit()
  saveRDS(candidate_kit, candidate_path)
  bundle <- refit_bundle(data_path, candidate_path)
  saveRDS(bundle, bundle_path)
  promotion_manifest <- refit_promotion_manifest(bundle, bundle_path)
  withr::defer(unlink(c(data_path, bundle_path, candidate_path)))
  writes <- new.env(parent = emptyenv())
  writes$n <- 0L
  writer <- function(...) writes$n <- writes$n + 1L

  expect_error(
    page_run_post_promotion_refit(
      allD = allD, promotion_bundle = bundle, promotion_manifest = promotion_manifest,
      candidate_kit = candidate_kit, candidate_path = candidate_path, data_path = data_path,
      incumbent_path = refit_incumbent_path(candidate_path),
      promotion_bundle_path = bundle_path, promotion_manifest_path = bundle_path,
      output_dir = tempfile(), manifest_dir = tempfile(),
      train_fn = function(...) refit_result(status = "held_out"),
      save_rds = writer, write_manifest = writer, code_commit = "ab3aeb6"
    ),
    "not released"
  )
  expect_identical(writes$n, 0L)

  expect_error(
    page_run_post_promotion_refit(
      allD = allD, promotion_bundle = bundle, promotion_manifest = promotion_manifest,
      candidate_kit = candidate_kit, candidate_path = candidate_path, data_path = data_path,
      incumbent_path = refit_incumbent_path(candidate_path),
      promotion_bundle_path = bundle_path, promotion_manifest_path = bundle_path,
      output_dir = tempfile(), manifest_dir = tempfile(),
      train_fn = function(...) refit_result(seasons = "2024-25"),
      save_rds = writer, write_manifest = writer, code_commit = "ab3aeb6"
    ),
    "absent"
  )
  expect_identical(writes$n, 0L)
})

test_that("successful fixed refresh binds the saved artifact hash in its manifest", {
  data_path <- tempfile(fileext = ".rds")
  candidate_path <- tempfile(fileext = ".rds")
  bundle_path <- tempfile(fileext = ".rds")
  promotion_manifest_path <- tempfile(fileext = ".rds")
  output_dir <- tempfile()
  manifest_dir <- tempfile()
  allD <- workflow_surveillance("2025-26", 1L)
  saveRDS(allD, data_path)
  candidate_kit <- refit_candidate_kit()
  saveRDS(candidate_kit, candidate_path)
  bundle <- refit_bundle(data_path, candidate_path)
  saveRDS(bundle, bundle_path)
  promotion_manifest <- refit_promotion_manifest(bundle, bundle_path)
  saveRDS(promotion_manifest, promotion_manifest_path)
  withr::defer(unlink(c(
    data_path, candidate_path, bundle_path, promotion_manifest_path,
    output_dir, manifest_dir
  ), recursive = TRUE))
  candidate <- page_candidate_refit_config(candidate_kit, candidate_path, bundle, promotion_manifest)
  mock_refresh <- function(...) {
    list(
      holdout = list(status = "released"),
      components = list(
        m0 = list(
          best_params = candidate$m0_params,
          manual_labels = candidate$manual_labels,
          flag_args = candidate$flag_args
        ),
        m1 = list(m1_params = candidate$m1_params)
      ),
      kit = list(m2_production = list(
        training_seasons = c("2024-25", "2025-26"), best_spec_id = candidate$spec_id,
        spec = candidate$best_spec
      ), best_spec = candidate$best_spec)
    )
  }

  result <- page_run_post_promotion_refit(
    allD = allD, promotion_bundle = bundle,
    promotion_manifest = promotion_manifest, candidate_kit = candidate_kit,
    candidate_path = candidate_path, data_path = data_path,
    incumbent_path = refit_incumbent_path(candidate_path),
    promotion_bundle_path = bundle_path, promotion_manifest_path = promotion_manifest_path,
    output_dir = output_dir, manifest_dir = manifest_dir, train_fn = mock_refresh,
    code_commit = "ab3aeb6"
  )
  expect_true(file.exists(result$artifact_path))
  expect_true(PAGe::validate_result_manifest(result$manifest))
  expect_identical(
    result$manifest$provenance$source_artifact_hashes[["refit_artifact"]],
    PAGe::hash_file_sha256(result$artifact_path)
  )
  expect_identical(result$manifest$provenance$row_counts[["training"]], 1L)
  expect_identical(result$manifest$provenance$evaluation_seasons, "none")
})

test_that("an existing immutable output prevents the refresh from starting", {
  data_path <- tempfile(fileext = ".rds")
  candidate_path <- tempfile(fileext = ".rds")
  bundle_path <- tempfile(fileext = ".rds")
  promotion_manifest_path <- tempfile(fileext = ".rds")
  output_dir <- tempfile()
  manifest_dir <- tempfile()
  allD <- workflow_surveillance("2025-26", 1L)
  saveRDS(allD, data_path)
  candidate_kit <- refit_candidate_kit()
  saveRDS(candidate_kit, candidate_path)
  bundle <- refit_bundle(data_path, candidate_path)
  saveRDS(bundle, bundle_path)
  promotion_manifest <- refit_promotion_manifest(bundle, bundle_path)
  saveRDS(promotion_manifest, promotion_manifest_path)
  dir.create(output_dir)
  artifact_path <- file.path(
    output_dir,
    page_refit_filename(
      "locked-v16", PAGe::hash_file_sha256(data_path), PAGe::hash_file_sha256(bundle_path)
    )
  )
  file.create(artifact_path)
  withr::defer(unlink(c(
    data_path, candidate_path, bundle_path, promotion_manifest_path,
    output_dir, manifest_dir
  ), recursive = TRUE))
  called <- FALSE

  expect_error(
    page_run_post_promotion_refit(
      allD = allD, promotion_bundle = bundle,
      promotion_manifest = promotion_manifest, candidate_kit = candidate_kit,
      candidate_path = candidate_path, data_path = data_path,
      incumbent_path = refit_incumbent_path(candidate_path),
      promotion_bundle_path = bundle_path, promotion_manifest_path = promotion_manifest_path,
      output_dir = output_dir, manifest_dir = manifest_dir,
      train_fn = function(...) {
        called <<- TRUE
        stop("must not run")
      },
      code_commit = "ab3aeb6"
    ),
    "already exists"
  )
  expect_false(called)
})
