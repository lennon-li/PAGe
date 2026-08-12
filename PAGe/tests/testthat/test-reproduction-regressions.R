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

test_that("M1 weighted scoring ignores non-finite rows", {
  scores <- data.frame(
    error = c(1, 2, NA_real_, 3),
    weight = c(1, NA_real_, 2, Inf)
  )

  expect_equal(PAGe:::.weighted_mae(scores, "weight"), 1)
  expect_true(is.na(PAGe:::.weighted_mae(
    data.frame(error = 1, weight = NA_real_), "weight"
  )))
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

test_that("M2 checkpoints resume only for the exact governed evaluation", {
  data <- data.frame(
    season = c("2023-24", "2024-25"),
    weekF = c(1L, 1L),
    y = c(1L, 2L),
    N = c(100L, 100L)
  )
  grid <- data.frame(
    delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
    alpha_state = 0.2, k_r = 0L, k_de = 0L, k_sp = 8L,
    bias_alpha = 0.05, bias_beta = 0,
    spec_id = "candidate", stringsAsFactors = FALSE
  )
  m0 <- list(
    best_params = list(p_thr = 0.005),
    manual_labels = c("2023-24" = 20L),
    flag_args = list(p_thresh = 0.01)
  )
  m1 <- list(
    m1_params = list(k_ref = 25L),
    ref = list(anchorWeek = 20L),
    hyper = list(scale = 1)
  )
  identity <- PAGe:::.m2_checkpoint_identity(
    data, c("2023-24", "2024-25"), grid, m0, m1
  )
  results <- list(candidate = list(scores = data.frame(
    season = c("2023-24", "2024-25"),
    bernoulli_nll = c(0.4, 0.5)
  )))
  checkpoint <- tempfile(fileext = ".rds")

  expect_identical(
    PAGe:::.write_m2_checkpoint(checkpoint, identity, results),
    checkpoint
  )
  expect_identical(PAGe:::.read_m2_checkpoint(checkpoint, identity), results)

  changed_data <- data
  changed_data$y[1L] <- changed_data$y[1L] + 1L
  changed_data_identity <- PAGe:::.m2_checkpoint_identity(
    changed_data, c("2023-24", "2024-25"), grid, m0, m1
  )
  expect_null(PAGe:::.read_m2_checkpoint(checkpoint, changed_data_identity))

  changed_m0 <- m0
  changed_m0$best_params$p_thr <- 0.01
  changed_stage_identity <- PAGe:::.m2_checkpoint_identity(
    data, c("2023-24", "2024-25"), grid, changed_m0, m1
  )
  expect_null(PAGe:::.read_m2_checkpoint(checkpoint, changed_stage_identity))

  legacy_checkpoint <- tempfile(fileext = ".rds")
  saveRDS(results, legacy_checkpoint)
  expect_null(PAGe:::.read_m2_checkpoint(legacy_checkpoint, identity))
})
