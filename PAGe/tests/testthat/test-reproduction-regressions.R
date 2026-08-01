test_that("tune_m1 accepts an explicit historical label vector", {
  captured <- new.env(parent = emptyenv())
  labels <- c("2012-13" = 24L, "2013-14" = 22L)

  local_mocked_bindings(
    tune_m1_alignment = function(...) {
      captured$args <- list(...)
      list(
        scores = data.frame(spec_id = "s001", mae_weibull = 1),
        best = data.frame(spec_id = "s001", mae_weibull = 1),
        grid = data.frame(spec_id = "s001")
      )
    },
    .package = "PAGe"
  )

  result <- tune_m1(
    allD = data.frame(season = names(labels)),
    m0 = list(best_params = list(p_thr = 0.01)),
    grid = data.frame(k_ref = 25L, slope_weight = 8),
    manual_labels = labels,
    n_cores = 1L,
    checkpoint_dir = withr::local_tempdir(),
    verbose = FALSE
  )

  expect_identical(captured$args$manual_labels, labels - 1L)
  expect_identical(result$manual_labels, labels - 1L)
})

test_that("M2 fold training labels exclude the held-out season", {
  labels <- c(
    "2012-13" = 18L,
    "2013-14" = 20L,
    "2014-15" = 20L
  )

  expect_identical(
    .m2_training_labels_for_fold(labels, "2013-14"),
    labels[c("2012-13", "2014-15")]
  )
  expect_identical(
    .m2_training_labels_for_fold(labels, "not-present"),
    labels
  )
})
