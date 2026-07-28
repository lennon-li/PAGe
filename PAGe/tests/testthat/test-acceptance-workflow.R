acceptance_helper <- normalizePath(
  file.path(testthat::test_path(), "..", "..", "..", "scripts", "acceptance", "acceptance_workflow.R"),
  mustWork = FALSE
)
if (!file.exists(acceptance_helper)) {
  testthat::skip(
    "Repository acceptance workflow script is not included in package tarballs."
  )
}
source(acceptance_helper)

acceptance_kit <- function(spec_id, training_seasons = "2024-25") {
  list(m2_production = list(spec_id = spec_id, training_seasons = training_seasons))
}

acceptance_predictions <- function(scale = 1) {
  data.frame(
    season = rep("2025-26", 6L),
    weekF = seq_len(6L),
    lead = rep(c(1L, 2L), 3L),
    t_since = c(-1, 1, 3, 5, 7, 9),
    p_hat = c(.10, .20, .30, .40, .45, .50) * scale,
    p_obs = c(.11, .18, .33, .38, .43, .48),
    N_lead = rep(100L, 6L),
    p_lo = c(.05, .14, .25, .32, .37, .41),
    p_hi = c(.16, .25, .38, .46, .50, .55)
  )
}

acceptance_replay <- function(kit, allD, season) {
  predictions <- acceptance_predictions()
  predictions$p_hat <- if (identical(kit$m2_production$spec_id, "candidate")) {
    predictions$p_obs
  } else {
    predictions$p_obs * .70
  }
  list(
    season = season,
    predictions = predictions,
    metrics = PAGe::summarize_forecast_metrics(predictions),
    diagnostics = PAGe::summarize_replay_diagnostics(predictions),
    ignition_week = 12,
    ignition_status = "locked"
  )
}

acceptance_inputs <- function() {
  root <- tempfile("page-acceptance-")
  dir.create(root)
  data_path <- file.path(root, "authorized.csv")
  candidate_path <- file.path(root, "candidate.rds")
  incumbent_path <- file.path(root, "incumbent.rds")
  private_dir <- file.path(root, "private")
  audit_dir <- file.path(root, "audit")
  utils::write.csv(
    data.frame(
      season = rep("2025-26", 6L), weekF = seq_len(6L),
      y = c(11L, 18L, 33L, 38L, 43L, 48L), N = rep(100L, 6L)
    ),
    data_path,
    row.names = FALSE
  )
  saveRDS(acceptance_kit("candidate"), candidate_path)
  saveRDS(acceptance_kit("incumbent"), incumbent_path)
  list(
    root = root, data_path = data_path, candidate_path = candidate_path,
    incumbent_path = incumbent_path, private_dir = private_dir, audit_dir = audit_dir
  )
}

acceptance_run_test <- function(inputs, run_id = "synthetic-pass", replay_fun = acceptance_replay) {
  run_acceptance_replay(
    data_path = inputs$data_path,
    candidate_path = inputs$candidate_path,
    incumbent_path = inputs$incumbent_path,
    private_output_dir = inputs$private_dir,
    audit_output_dir = inputs$audit_dir,
    season = "2025-26",
    replay_fun = replay_fun,
    prepare_fun = identity,
    code_commit = "ab3aeb6",
    run_timestamp = "2026-07-28T12:00:00Z",
    run_id = run_id
  )
}

test_that("preflight rejects candidate and incumbent holdout leakage", {
  expect_error(
    acceptance_kit_identity(acceptance_kit("candidate", c("2024-25", "2025-26")), "candidate", "2025-26"),
    "candidate.*leakage"
  )
  expect_error(
    acceptance_kit_identity(acceptance_kit("incumbent", c("2024-25", "2025-26")), "incumbent", "2025-26"),
    "incumbent.*leakage"
  )
  expect_error(acceptance_kit_identity(list(m2_production = list(training_seasons = "2024-25")), "candidate", "2025-26"), "spec")
  expect_error(
    acceptance_kit_identity(
      list(m2_production = list(training_seasons = "2024-25", spec_version = "v16")),
      "candidate", "2025-26"
    ),
    "spec"
  )
})

test_that("acceptance identity prefers canonical M2 and isolates legacy compatibility", {
  canonical <- list(spec_id = "canonical", training_seasons = "2024-25")
  expect_identical(
    acceptance_kit_identity(list(m2_production = canonical), "candidate", "2025-26")$spec_id,
    "canonical"
  )
  expect_error(
    acceptance_kit_identity(
      list(
        m2_production = canonical,
        m2 = list(spec_id = "legacy", training_seasons = "2024-25")
      ),
      "candidate", "2025-26"
    ),
    "conflicting"
  )
  expect_error(
    acceptance_kit_identity(list(m2 = canonical), "candidate", "2025-26"),
    "compatibility"
  )
  expect_warning(
    legacy <- acceptance_kit_identity(
      list(m2 = canonical), "candidate", "2025-26",
      compatibility = "legacy_m2"
    ),
    "legacy"
  )
  expect_identical(legacy$spec_id, "canonical")
})

test_that("a passing replay writes disclosure-safe aggregate evidence and a valid manifest", {
  inputs <- acceptance_inputs()
  withr::defer(unlink(inputs$root, recursive = TRUE))
  result <- acceptance_run_test(inputs)

  expect_true(result$gate$pass)
  expect_true(file.exists(result$paths$private_bundle))
  expect_true(file.exists(result$paths$manifest))
  bundle <- readRDS(result$paths$private_bundle)
  expect_identical(bundle$schema, "page_holdout_decision_bundle")
  expect_identical(bundle$schema_version, 1L)
  expect_named(bundle, c(
    "schema", "schema_version", "run_id", "created_at", "holdout_season",
    "report", "source_artifact_hashes"
  ))
  expect_identical(bundle$holdout_season, "2025-26")
  expect_true(is.list(bundle$report))
  expect_identical(bundle$created_at, "2026-07-28T12:00:00Z")
  expect_identical(bundle$source_artifact_hashes[["candidate"]], PAGe::hash_file_sha256(inputs$candidate_path))
  expect_identical(bundle$source_artifact_hashes[["incumbent"]], PAGe::hash_file_sha256(inputs$incumbent_path))
  manifest <- acceptance_read_manifest(result$paths$manifest)
  expect_true(PAGe::validate_result_manifest(manifest))
  expect_identical(
    unname(manifest$provenance$source_artifact_hashes[["promotion_bundle"]]),
    PAGe::hash_file_sha256(result$paths$private_bundle)
  )

  csvs <- list.files(result$paths$audit_dir, pattern = "[.]csv$", full.names = TRUE)
  expect_length(csvs, 11L)
  forbidden <- c("p_hat", "p_obs", "y_lead", "N_lead", "weekF", "season")
  expect_false(any(vapply(csvs, function(path) {
    any(forbidden %in% names(utils::read.csv(path, check.names = FALSE)))
  }, logical(1))))
  decision <- paste(readLines(result$paths$decision_markdown), collapse = "\n")
  expect_match(decision, "candidate training seasons: 2024-25")
  expect_match(decision, "incumbent training seasons: 2024-25")
  expect_match(decision, "candidate ignition: locked at week 12")
  expect_match(decision, "incumbent ignition: locked at week 12")
})

test_that("a failed gate saves evidence before returning an error", {
  inputs <- acceptance_inputs()
  withr::defer(unlink(inputs$root, recursive = TRUE))
  failing_replay <- function(kit, allD, season) {
    predictions <- acceptance_predictions()
    predictions$p_hat <- if (identical(kit$m2_production$spec_id, "candidate")) {
      1 - predictions$p_obs
    } else {
      predictions$p_obs
    }
    list(season = season, predictions = predictions, metrics = PAGe::summarize_forecast_metrics(predictions))
  }

  expect_error(acceptance_run_test(inputs, "synthetic-fail", failing_replay), "Promotion failed")
  audit_run <- file.path(inputs$audit_dir, "synthetic-fail")
  private_run <- file.path(inputs$private_dir, "synthetic-fail")
  expect_true(file.exists(file.path(audit_run, "decision.md")))
  expect_true(file.exists(file.path(audit_run, "result_manifest.json")))
  expect_true(file.exists(file.path(private_run, "decision_bundle.rds")))
})

test_that("acceptance output directories are immutable", {
  inputs <- acceptance_inputs()
  withr::defer(unlink(inputs$root, recursive = TRUE))
  acceptance_run_test(inputs, "collision")
  expect_error(acceptance_run_test(inputs, "collision"), "already exists")
})
