promotion_test_metrics <- function(nll, mae) {
  list(
    overall = data.frame(bernoulli_nll = nll),
    horizon = data.frame(lead = c("1", "2"), mae = c(mae, mae)),
    phase = data.frame(phase = c("rise", "peak"), mae = c(mae, mae))
  )
}

promotion_test_manifest <- function(role, spec_id, training_seasons, hashes,
                                    evaluation_seasons = "none") {
  PAGe::new_result_manifest(
    artifact_role = role,
    classification = "disclosure_safe",
    code_commit = "abcdef1",
    run_timestamp = "2026-07-28T12:00:00Z",
    r_version = as.character(getRversion()),
    package_versions = c(PAGe = as.character(utils::packageVersion("PAGe"))),
    input_fingerprint = unname(hashes[[1L]]),
    seasons = unique(c(training_seasons, evaluation_seasons)),
    exclusions = "none",
    row_counts = c(training = length(training_seasons)),
    spec_id = spec_id,
    training_seasons = training_seasons,
    source_artifact_hashes = hashes,
    fold_ids = "none",
    evaluation_seasons = evaluation_seasons
  )
}

promotion_test_fixture <- function() {
  root <- tempfile("page-promotion-test-")
  dir.create(root)
  paths <- file.path(root, c(
    "authorized-data.rds", "candidate.rds", "incumbent.rds",
    "acceptance-bundle.rds", "acceptance-manifest.rds",
    "refit-artifact.rds", "refit-manifest.rds"
  ))
  names(paths) <- c(
    "data", "candidate", "incumbent", "acceptance_bundle",
    "acceptance_manifest", "refit_artifact", "refit_manifest"
  )

  data <- data.frame(
    season = c("2024-25", "2025-26"),
    week = c(1L, 1L),
    value = c(0.1, 0.2)
  )
  accepted_spec <- list(k_f = 4L, k_e = 2L, alpha_state = 0.15)
  fit <- structure(
    list(model = data.frame(logit_f_eff = 0, z_ema = 0, lead = 1L)),
    class = c("gam", "list")
  )
  candidate <- list(
    m0_params = list(p_thresh = 0.005),
    ref = list(anchorWeek = 20),
    hyper = list(),
    manual_labels = c("2024-25" = 23L),
    flag_args = list(p_thresh = 0.01, n_consec = 2L),
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
    best_spec = accepted_spec,
    m2_production = list(
      fit = fit,
      best_spec_id = "candidate-spec",
      spec = accepted_spec,
      training_seasons = c("2023-24", "2024-25")
    )
  )
  incumbent <- list(
    m2_production = list(
      best_spec_id = "incumbent-spec",
      spec = list(k_f = 3L),
      training_seasons = c("2023-24", "2024-25")
    )
  )
  saveRDS(data, paths[["data"]])
  saveRDS(candidate, paths[["candidate"]])
  saveRDS(incumbent, paths[["incumbent"]])

  report <- PAGe::check_promotion(
    promotion_test_metrics(0.8, 0.9),
    promotion_test_metrics(1.0, 1.0)
  )
  bundle_hashes <- c(
    authorized_data = PAGe::hash_file_sha256(paths[["data"]]),
    candidate = PAGe::hash_file_sha256(paths[["candidate"]]),
    incumbent = PAGe::hash_file_sha256(paths[["incumbent"]])
  )
  bundle <- structure(
    list(
      schema = "page_holdout_decision_bundle",
      schema_version = 1L,
      run_id = "acceptance-test",
      created_at = "2026-07-28T12:00:00Z",
      holdout_season = "2025-26",
      report = report,
      source_artifact_hashes = bundle_hashes
    ),
    class = "page_holdout_decision_bundle"
  )
  saveRDS(bundle, paths[["acceptance_bundle"]])

  acceptance_hashes <- c(
    bundle_hashes,
    promotion_bundle = PAGe::hash_file_sha256(paths[["acceptance_bundle"]])
  )
  acceptance_manifest <- promotion_test_manifest(
    "holdout_acceptance_decision",
    "candidate-spec",
    c("2023-24", "2024-25"),
    acceptance_hashes,
    evaluation_seasons = "2025-26"
  )
  saveRDS(acceptance_manifest, paths[["acceptance_manifest"]])

  promoted_kit <- candidate
  promoted_kit$m2_production$training_seasons <- c(
    "2023-24", "2024-25", "2025-26"
  )
  refit <- list(
    kit = promoted_kit,
    holdout = list(status = "released"),
    components = list(
      m0 = list(
        best_params = candidate$m0_params,
        manual_labels = candidate$manual_labels,
        flag_args = candidate$flag_args
      ),
      m1 = list(m1_params = candidate$M1_PARAMS)
    )
  )
  saveRDS(refit, paths[["refit_artifact"]])
  refit_hashes <- c(
    authorized_data = bundle_hashes[["authorized_data"]],
    candidate = bundle_hashes[["candidate"]],
    promotion_bundle = acceptance_hashes[["promotion_bundle"]],
    promotion_manifest = PAGe::hash_file_sha256(paths[["acceptance_manifest"]]),
    refit_artifact = PAGe::hash_file_sha256(paths[["refit_artifact"]])
  )
  refit_manifest <- promotion_test_manifest(
    "post_promotion_refit",
    "candidate-spec",
    promoted_kit$m2_production$training_seasons,
    refit_hashes
  )
  saveRDS(refit_manifest, paths[["refit_manifest"]])

  list(
    root = root,
    paths = paths,
    registry_dir = file.path(root, "private-registry"),
    audit_dir = file.path(root, "audit"),
    promoted_kit = promoted_kit
  )
}

promotion_test_writer <- function(manifest, path, overwrite = FALSE) {
  if (file.exists(path) && !isTRUE(overwrite)) {
    stop("refusing overwrite")
  }
  saveRDS(manifest, path)
  normalizePath(path)
}

promotion_workflow_helper <- testthat::test_path(
  "..", "..", "..", "scripts", "promotion", "promotion_workflow.R"
)
if (!file.exists(promotion_workflow_helper)) {
  testthat::skip(
    "Repository promotion workflow script is not included in package tarballs."
  )
}
source(promotion_workflow_helper)

test_that("promotion kit identity is strict unless legacy mode is explicit", {
  legacy <- list(m2 = list(
    best_spec_id = "legacy",
    spec = list(k_f = 4L),
    training_seasons = "2024-25"
  ))
  expect_error(
    promotion_m2(legacy, "incumbent"),
    "legacy `m2`"
  )
  expect_warning(
    resolved <- promotion_m2(
      legacy, "incumbent", compatibility = "legacy_m2"
    ),
    "legacy `m2` identity"
  )
  expect_identical(resolved, legacy$m2)

  conflicting <- list(
    m2_production = list(best_spec_id = "canonical"),
    m2 = list(best_spec_id = "legacy")
  )
  expect_error(
    promotion_m2(conflicting, "incumbent"),
    "conflicting"
  )
})

test_that("preflight validates the complete chain without writing outputs", {
  fixture <- promotion_test_fixture()
  result <- promote_post_refit(
    data_path = fixture$paths[["data"]],
    acceptance_bundle_path = fixture$paths[["acceptance_bundle"]],
    acceptance_manifest_path = fixture$paths[["acceptance_manifest"]],
    candidate_path = fixture$paths[["candidate"]],
    incumbent_path = fixture$paths[["incumbent"]],
    refit_artifact_path = fixture$paths[["refit_artifact"]],
    refit_manifest_path = fixture$paths[["refit_manifest"]],
    registry_dir = fixture$registry_dir,
    audit_dir = fixture$audit_dir,
    deployment_id = "deployment-test",
    preflight_only = TRUE,
    read_manifest = readRDS,
    write_manifest = promotion_test_writer,
    code_commit = "abcdef1"
  )

  expect_true(result$preflight)
  expect_identical(result$spec_id, "candidate-spec")
  expect_false(dir.exists(fixture$registry_dir))
  expect_false(dir.exists(fixture$audit_dir))
})

test_that("promotion publishes one immutable deployment and audit manifest", {
  fixture <- promotion_test_fixture()
  result <- promote_post_refit(
    data_path = fixture$paths[["data"]],
    acceptance_bundle_path = fixture$paths[["acceptance_bundle"]],
    acceptance_manifest_path = fixture$paths[["acceptance_manifest"]],
    candidate_path = fixture$paths[["candidate"]],
    incumbent_path = fixture$paths[["incumbent"]],
    refit_artifact_path = fixture$paths[["refit_artifact"]],
    refit_manifest_path = fixture$paths[["refit_manifest"]],
    registry_dir = fixture$registry_dir,
    audit_dir = fixture$audit_dir,
    deployment_id = "deployment-test",
    read_manifest = readRDS,
    write_manifest = promotion_test_writer,
    code_commit = "abcdef1"
  )

  expect_identical(readRDS(result$promoted_kit_path), fixture$promoted_kit)
  expect_true(file.exists(result$manifest_json_path))
  expect_true(file.exists(result$manifest_markdown_path))
  expect_false(file.exists(file.path(fixture$registry_dir, "current")))
  expect_identical(basename(dirname(result$promoted_kit_path)), "deployment-test")

  manifest <- readRDS(result$manifest_json_path)
  expect_true(PAGe::validate_result_manifest(manifest))
  expect_identical(manifest$artifact$role, "promoted_deployment_kit")
  expect_identical(
    manifest$provenance$source_artifact_hashes[["promoted_kit"]],
    PAGe::hash_file_sha256(result$promoted_kit_path)
  )
  expect_setequal(
    names(manifest$provenance$source_artifact_hashes),
    c(
      "authorized_data", "candidate", "incumbent", "acceptance_bundle",
      "acceptance_manifest", "refit_artifact", "refit_manifest", "promoted_kit"
    )
  )
})

test_that("canonical manifest I/O produces a loadable promoted kit", {
  fixture <- promotion_test_fixture()
  result <- promote_post_refit(
    data_path = fixture$paths[["data"]],
    acceptance_bundle_path = fixture$paths[["acceptance_bundle"]],
    acceptance_manifest_path = fixture$paths[["acceptance_manifest"]],
    candidate_path = fixture$paths[["candidate"]],
    incumbent_path = fixture$paths[["incumbent"]],
    refit_artifact_path = fixture$paths[["refit_artifact"]],
    refit_manifest_path = fixture$paths[["refit_manifest"]],
    registry_dir = fixture$registry_dir,
    audit_dir = fixture$audit_dir,
    deployment_id = "canonical-io",
    code_commit = "abcdef1"
  )

  loaded <- PAGe::load_promoted_kit(
    result$promoted_kit_path,
    result$manifest_json_path
  )
  expect_identical(loaded, fixture$promoted_kit)
  expect_true(file.exists(result$manifest_markdown_path))
})

test_that("tampered candidate and refit artifacts create no promotion", {
  fixture <- promotion_test_fixture()
  saveRDS(list(tampered = TRUE), fixture$paths[["candidate"]])
  expect_error(
    promote_post_refit(
      data_path = fixture$paths[["data"]],
      acceptance_bundle_path = fixture$paths[["acceptance_bundle"]],
      acceptance_manifest_path = fixture$paths[["acceptance_manifest"]],
      candidate_path = fixture$paths[["candidate"]],
      incumbent_path = fixture$paths[["incumbent"]],
      refit_artifact_path = fixture$paths[["refit_artifact"]],
      refit_manifest_path = fixture$paths[["refit_manifest"]],
      registry_dir = fixture$registry_dir,
      audit_dir = fixture$audit_dir,
      deployment_id = "candidate-tampered",
      read_manifest = readRDS,
      write_manifest = promotion_test_writer,
      code_commit = "abcdef1"
    ),
    "Candidate kit SHA-256"
  )
  expect_false(dir.exists(fixture$registry_dir))

  fixture <- promotion_test_fixture()
  saveRDS(list(tampered = TRUE), fixture$paths[["refit_artifact"]])
  expect_error(
    promote_post_refit(
      data_path = fixture$paths[["data"]],
      acceptance_bundle_path = fixture$paths[["acceptance_bundle"]],
      acceptance_manifest_path = fixture$paths[["acceptance_manifest"]],
      candidate_path = fixture$paths[["candidate"]],
      incumbent_path = fixture$paths[["incumbent"]],
      refit_artifact_path = fixture$paths[["refit_artifact"]],
      refit_manifest_path = fixture$paths[["refit_manifest"]],
      registry_dir = fixture$registry_dir,
      audit_dir = fixture$audit_dir,
      deployment_id = "refit-tampered",
      read_manifest = readRDS,
      write_manifest = promotion_test_writer,
      code_commit = "abcdef1"
    ),
    "Refit artifact SHA-256"
  )
  expect_false(dir.exists(fixture$registry_dir))
})

test_that("tampered acceptance evidence creates no promotion", {
  fixture <- promotion_test_fixture()
  bundle <- readRDS(fixture$paths[["acceptance_bundle"]])
  bundle$report$thresholds$min_nll_improvement <- 0
  saveRDS(bundle, fixture$paths[["acceptance_bundle"]])
  expect_error(
    promote_post_refit(
      data_path = fixture$paths[["data"]],
      acceptance_bundle_path = fixture$paths[["acceptance_bundle"]],
      acceptance_manifest_path = fixture$paths[["acceptance_manifest"]],
      candidate_path = fixture$paths[["candidate"]],
      incumbent_path = fixture$paths[["incumbent"]],
      refit_artifact_path = fixture$paths[["refit_artifact"]],
      refit_manifest_path = fixture$paths[["refit_manifest"]],
      registry_dir = fixture$registry_dir,
      audit_dir = fixture$audit_dir,
      deployment_id = "unlocked-report",
      read_manifest = readRDS,
      write_manifest = promotion_test_writer,
      code_commit = "abcdef1"
    ),
    "locked thresholds"
  )
  expect_false(dir.exists(fixture$registry_dir))

  fixture <- promotion_test_fixture()
  manifest <- readRDS(fixture$paths[["acceptance_manifest"]])
  manifest$provenance$code_commit <- "abcdef2"
  saveRDS(manifest, fixture$paths[["acceptance_manifest"]])
  expect_error(
    promote_post_refit(
      data_path = fixture$paths[["data"]],
      acceptance_bundle_path = fixture$paths[["acceptance_bundle"]],
      acceptance_manifest_path = fixture$paths[["acceptance_manifest"]],
      candidate_path = fixture$paths[["candidate"]],
      incumbent_path = fixture$paths[["incumbent"]],
      refit_artifact_path = fixture$paths[["refit_artifact"]],
      refit_manifest_path = fixture$paths[["refit_manifest"]],
      registry_dir = fixture$registry_dir,
      audit_dir = fixture$audit_dir,
      deployment_id = "manifest-tampered",
      read_manifest = readRDS,
      write_manifest = promotion_test_writer,
      code_commit = "abcdef1"
    ),
    "post-promotion refit manifest source hashes"
  )
  expect_false(dir.exists(fixture$registry_dir))
})

test_that("spec drift and destination collisions create no promotion", {
  fixture <- promotion_test_fixture()
  refit <- readRDS(fixture$paths[["refit_artifact"]])
  refit$kit$m2_production$best_spec_id <- "different-spec"
  saveRDS(refit, fixture$paths[["refit_artifact"]])
  refit_manifest <- readRDS(fixture$paths[["refit_manifest"]])
  refit_manifest$provenance$source_artifact_hashes[["refit_artifact"]] <-
    PAGe::hash_file_sha256(fixture$paths[["refit_artifact"]])
  saveRDS(refit_manifest, fixture$paths[["refit_manifest"]])
  expect_error(
    promote_post_refit(
      data_path = fixture$paths[["data"]],
      acceptance_bundle_path = fixture$paths[["acceptance_bundle"]],
      acceptance_manifest_path = fixture$paths[["acceptance_manifest"]],
      candidate_path = fixture$paths[["candidate"]],
      incumbent_path = fixture$paths[["incumbent"]],
      refit_artifact_path = fixture$paths[["refit_artifact"]],
      refit_manifest_path = fixture$paths[["refit_manifest"]],
      registry_dir = fixture$registry_dir,
      audit_dir = fixture$audit_dir,
      deployment_id = "spec-drift",
      read_manifest = readRDS,
      write_manifest = promotion_test_writer,
      code_commit = "abcdef1"
    ),
    "accepted candidate spec"
  )
  expect_false(dir.exists(fixture$registry_dir))

  fixture <- promotion_test_fixture()
  dir.create(file.path(fixture$registry_dir, "collision"), recursive = TRUE)
  expect_error(
    promote_post_refit(
      data_path = fixture$paths[["data"]],
      acceptance_bundle_path = fixture$paths[["acceptance_bundle"]],
      acceptance_manifest_path = fixture$paths[["acceptance_manifest"]],
      candidate_path = fixture$paths[["candidate"]],
      incumbent_path = fixture$paths[["incumbent"]],
      refit_artifact_path = fixture$paths[["refit_artifact"]],
      refit_manifest_path = fixture$paths[["refit_manifest"]],
      registry_dir = fixture$registry_dir,
      audit_dir = fixture$audit_dir,
      deployment_id = "collision",
      read_manifest = readRDS,
      write_manifest = promotion_test_writer,
      code_commit = "abcdef1"
    ),
    "already exists"
  )
  expect_false(dir.exists(file.path(fixture$audit_dir, "collision")))
})

test_that("fixed M0, M1, and runtime drift creates no promotion", {
  fixture <- promotion_test_fixture()
  refit <- readRDS(fixture$paths[["refit_artifact"]])
  refit$components$m1$m1_params$slope_weight <- 9
  saveRDS(refit, fixture$paths[["refit_artifact"]])
  refit_manifest <- readRDS(fixture$paths[["refit_manifest"]])
  refit_manifest$provenance$source_artifact_hashes[["refit_artifact"]] <-
    PAGe::hash_file_sha256(fixture$paths[["refit_artifact"]])
  saveRDS(refit_manifest, fixture$paths[["refit_manifest"]])

  expect_error(
    promote_post_refit(
      data_path = fixture$paths[["data"]],
      acceptance_bundle_path = fixture$paths[["acceptance_bundle"]],
      acceptance_manifest_path = fixture$paths[["acceptance_manifest"]],
      candidate_path = fixture$paths[["candidate"]],
      incumbent_path = fixture$paths[["incumbent"]],
      refit_artifact_path = fixture$paths[["refit_artifact"]],
      refit_manifest_path = fixture$paths[["refit_manifest"]],
      registry_dir = fixture$registry_dir,
      audit_dir = fixture$audit_dir,
      deployment_id = "m1-drift",
      read_manifest = readRDS,
      write_manifest = promotion_test_writer,
      code_commit = "abcdef1"
    ),
    "fixed M0, M1, and runtime configuration"
  )
  expect_false(dir.exists(fixture$registry_dir))
  expect_false(dir.exists(fixture$audit_dir))
})

test_that("partial staging creation is cleaned up", {
  fixture <- promotion_test_fixture()
  stage_creations <- 0L
  create_dir <- function(path, recursive = FALSE, showWarnings = FALSE) {
    if (startsWith(basename(path), ".promotion-")) {
      stage_creations <<- stage_creations + 1L
      if (stage_creations == 2L) {
        return(FALSE)
      }
    }
    dir.create(path, recursive = recursive, showWarnings = showWarnings)
  }

  expect_error(
    promote_post_refit(
      data_path = fixture$paths[["data"]],
      acceptance_bundle_path = fixture$paths[["acceptance_bundle"]],
      acceptance_manifest_path = fixture$paths[["acceptance_manifest"]],
      candidate_path = fixture$paths[["candidate"]],
      incumbent_path = fixture$paths[["incumbent"]],
      refit_artifact_path = fixture$paths[["refit_artifact"]],
      refit_manifest_path = fixture$paths[["refit_manifest"]],
      registry_dir = fixture$registry_dir,
      audit_dir = fixture$audit_dir,
      deployment_id = "stage-create-failure",
      read_manifest = readRDS,
      write_manifest = promotion_test_writer,
      create_dir = create_dir,
      code_commit = "abcdef1"
    ),
    "staging directories"
  )
  expect_identical(stage_creations, 2L)
  expect_false(dir.exists(file.path(
    fixture$registry_dir,
    "stage-create-failure"
  )))
  expect_false(dir.exists(file.path(
    fixture$audit_dir,
    "stage-create-failure"
  )))
  expect_length(
    list.files(fixture$registry_dir, all.files = TRUE, no.. = TRUE),
    0L
  )
  expect_length(
    list.files(fixture$audit_dir, all.files = TRUE, no.. = TRUE),
    0L
  )
})

test_that("audit publication failure rolls back the private registry", {
  fixture <- promotion_test_fixture()
  renames <- 0L
  targets <- character()
  rename_path <- function(from, to) {
    renames <<- renames + 1L
    targets <<- c(targets, to)
    if (renames == 2L) {
      return(FALSE)
    }
    file.rename(from, to)
  }

  expect_error(
    promote_post_refit(
      data_path = fixture$paths[["data"]],
      acceptance_bundle_path = fixture$paths[["acceptance_bundle"]],
      acceptance_manifest_path = fixture$paths[["acceptance_manifest"]],
      candidate_path = fixture$paths[["candidate"]],
      incumbent_path = fixture$paths[["incumbent"]],
      refit_artifact_path = fixture$paths[["refit_artifact"]],
      refit_manifest_path = fixture$paths[["refit_manifest"]],
      registry_dir = fixture$registry_dir,
      audit_dir = fixture$audit_dir,
      deployment_id = "audit-publish-failure",
      read_manifest = readRDS,
      write_manifest = promotion_test_writer,
      rename_path = rename_path,
      code_commit = "abcdef1"
    ),
    "audit directory"
  )
  expect_identical(renames, 2L)
  expect_identical(
    targets,
    c(
      file.path(fixture$registry_dir, "audit-publish-failure"),
      file.path(fixture$audit_dir, "audit-publish-failure")
    )
  )
  expect_false(dir.exists(file.path(
    fixture$registry_dir,
    "audit-publish-failure"
  )))
  expect_false(dir.exists(file.path(
    fixture$audit_dir,
    "audit-publish-failure"
  )))
})

test_that("promotion CLI exposes help without creating state", {
  script <- testthat::test_path(
    "..", "..", "..", "scripts", "promotion", "promote_post_refit.R"
  )
  output <- system2(
    file.path(R.home("bin"), "Rscript"),
    c(shQuote(script), "--help"),
    stdout = TRUE,
    stderr = TRUE
  )
  expect_identical(attr(output, "status"), NULL)
  expect_true(any(grepl("--preflight-only", output, fixed = TRUE)))
  expect_true(any(grepl("--deployment-id", output, fixed = TRUE)))
})

test_that("promotion CLI preflight validates without writing outputs", {
  fixture <- promotion_test_fixture()
  script <- testthat::test_path(
    "..", "..", "..", "scripts", "promotion", "promote_post_refit.R"
  )
  cli_args <- c(
    script,
    paste0("--data=", fixture$paths[["data"]]),
    paste0(
      "--acceptance-bundle=",
      fixture$paths[["acceptance_bundle"]]
    ),
    paste0(
      "--acceptance-manifest=",
      fixture$paths[["acceptance_manifest"]]
    ),
    paste0("--candidate-kit=", fixture$paths[["candidate"]]),
    paste0("--incumbent-kit=", fixture$paths[["incumbent"]]),
    paste0("--refit-artifact=", fixture$paths[["refit_artifact"]]),
    paste0("--refit-manifest=", fixture$paths[["refit_manifest"]]),
    paste0("--registry-dir=", fixture$registry_dir),
    paste0("--audit-dir=", fixture$audit_dir),
    "--deployment-id=cli-preflight",
    "--preflight-only"
  )
  output <- system2(
    file.path(R.home("bin"), "Rscript"),
    cli_args,
    stdout = TRUE,
    stderr = TRUE
  )

  expect_identical(attr(output, "status"), NULL)
  expect_true(any(grepl("Preflight passed", output, fixed = TRUE)))
  expect_false(dir.exists(fixture$registry_dir))
  expect_false(dir.exists(fixture$audit_dir))
})
