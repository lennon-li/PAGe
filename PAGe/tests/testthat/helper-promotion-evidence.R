training_promotion_fixture <- function(allD, report) {
  root <- tempfile("page-promotion-evidence-")
  dir.create(root)
  paths <- file.path(
    root,
    c("authorized.rds", "candidate.rds", "incumbent.rds", "bundle.rds")
  )
  names(paths) <- c("data", "candidate", "incumbent", "bundle")
  saveRDS(allD, paths[["data"]])
  saveRDS(
    list(m2_production = list(
      best_spec_id = "candidate",
      training_seasons = "2024-25"
    )),
    paths[["candidate"]]
  )
  saveRDS(
    list(m2_production = list(
      best_spec_id = "incumbent",
      training_seasons = "2024-25"
    )),
    paths[["incumbent"]]
  )
  source_hashes <- c(
    authorized_data = PAGe::hash_file_sha256(paths[["data"]]),
    candidate = PAGe::hash_file_sha256(paths[["candidate"]]),
    incumbent = PAGe::hash_file_sha256(paths[["incumbent"]])
  )
  bundle <- structure(
    list(
      schema = "page_holdout_decision_bundle",
      schema_version = 1L,
      run_id = "test-acceptance",
      created_at = "2026-07-28T12:00:00Z",
      holdout_season = "2025-26",
      report = report,
      source_artifact_hashes = source_hashes
    ),
    class = c("page_holdout_decision_bundle", "list")
  )
  saveRDS(bundle, paths[["bundle"]])
  manifest_hashes <- c(
    source_hashes,
    promotion_bundle = PAGe::hash_file_sha256(paths[["bundle"]])
  )
  manifest <- PAGe::new_result_manifest(
    artifact_role = "holdout_acceptance_decision",
    classification = "disclosure_safe",
    code_commit = "ab3aeb6",
    run_timestamp = "2026-07-28T12:00:00Z",
    r_version = "4.4.1",
    package_versions = c(PAGe = "0.2.0"),
    input_fingerprint = source_hashes[["authorized_data"]],
    seasons = "2025-26",
    exclusions = "none",
    row_counts = c(evaluation = 1L),
    spec_id = "candidate",
    training_seasons = "2024-25",
    source_artifact_hashes = manifest_hashes,
    fold_ids = "holdout_2025-26",
    evaluation_seasons = "2025-26"
  )
  list(
    root = root,
    args = list(
      bundle = bundle,
      manifest = manifest,
      data_path = paths[["data"]],
      candidate_path = paths[["candidate"]],
      incumbent_path = paths[["incumbent"]],
      bundle_path = paths[["bundle"]]
    )
  )
}

training_rebind_fixture <- function(fixture) {
  paths <- c(
    authorized_data = fixture$args$data_path,
    candidate = fixture$args$candidate_path,
    incumbent = fixture$args$incumbent_path
  )
  source_hashes <- vapply(paths, PAGe::hash_file_sha256, character(1))
  fixture$args$bundle$source_artifact_hashes <- source_hashes
  saveRDS(fixture$args$bundle, fixture$args$bundle_path)
  fixture$args$manifest$provenance$source_artifact_hashes <- c(
    source_hashes,
    promotion_bundle = PAGe::hash_file_sha256(fixture$args$bundle_path)
  )
  fixture
}

training_promotion_evidence <- function(allD, report) {
  fixture <- training_promotion_fixture(allD, report)
  on.exit(unlink(fixture$root, recursive = TRUE))
  do.call(PAGe::verify_promotion_evidence, fixture$args)
}
