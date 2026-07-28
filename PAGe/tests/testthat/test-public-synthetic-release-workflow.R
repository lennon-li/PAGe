test_that("public smoke workflow releases 2025-26 only after acceptance", {
  script <- testthat::test_path(
    "..", "..", "..", "scripts", "public",
    "synthetic_release_workflow.R"
  )
  if (!file.exists(script)) {
    skip("Repository synthetic release script is not included in package tarballs.")
  }
  source(script, local = TRUE)

  output_dir <- tempfile("page-public-release-")
  withr::defer(unlink(output_dir, recursive = TRUE, force = TRUE))
  result <- run_public_synthetic_release(
    output_dir = output_dir,
    repo_root = testthat::test_path("..", "..", ".."),
    run_id = "public-acceptance-test",
    deployment_id = "public-deployment-test",
    code_commit = "abcdef1"
  )

  expect_true(result$acceptance$gate$pass)
  expect_false("2025-26" %in% result$pre_acceptance_training_seasons)
  expect_false("2025-26" %in% result$incumbent_training_seasons)
  expect_true("2025-26" %in% result$final_training_seasons)
  expect_identical(
    result$accepted_spec_id,
    result$loaded_kit$m2_production$best_spec_id
  )
  expect_identical(
    result$accepted_spec_id,
    result$promotion$manifest$provenance$spec_id
  )
  expect_identical(
    result$final_training_seasons,
    result$loaded_kit$m2_production$training_seasons
  )
  expect_true(file.exists(result$promotion$promoted_kit_path))
  expect_true(file.exists(result$promotion$manifest_json_path))
  expect_identical(PAGe::validate_page_kit(result$loaded_kit), result$loaded_kit)
})
