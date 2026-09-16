# m2_subset_train() previously had no `timing_truth` formal; fit_m2()/
# train_outer_fold() pass it through `...`, which m2_subset_train()'s own
# `...` silently discarded. Consequence: m2_subset_tune() selects the
# winning spec on rows built with the true ignition week (timing_truth
# supplied), but m2_subset_train() fit the deployed GAM on rows built with
# the detected ignition week (timing_truth dropped) -- different features
# for selection and deployment under timing_mode = "fractional", with
# nothing catching the mismatch (m2_subset_check_tuning_match() only
# compares data_id/config/upstream_ids, not row construction).

test_that("m2_subset_train forwards timing_truth into m2_subset_make_rows", {
  recorded <- new.env()
  fake_make_rows <- function(data, m0, m1, m1_train_preds = NULL,
                             seasons = unique(as.character(data$season)),
                             detector = run_ignition_weekly,
                             alpha_state = 0.2,
                             timing_mode = c("legacy", "fractional"),
                             parallel = FALSE,
                             timing_truth = NULL) {
    recorded$timing_truth <- timing_truth
    list(data = data.frame(
      season = "A", weekF = 1:2, y = 1, N = 10,
      forecast_available = TRUE, stringsAsFactors = FALSE
    ))
  }
  fake_fit <- function(fit_data, spec, method, gamma, bs, intercept_sp) {
    list(spec = spec)
  }

  testthat::local_mocked_bindings(
    m2_subset_make_rows = fake_make_rows,
    m2_subset_fit = fake_fit,
    .package = "PAGe"
  )

  data <- data.frame(season = "A", weekF = 1:2, y = 1, N = 10, stringsAsFactors = FALSE)
  config <- m2_subset_config()
  truth <- data.frame(season = "A", ignition_target_weekF = 5.5, stringsAsFactors = FALSE)

  PAGe:::m2_subset_train(data, m0 = list(), m1 = list(), config = config, timing_truth = truth)
  expect_identical(recorded$timing_truth, truth)

  recorded$timing_truth <- "unset"
  PAGe:::m2_subset_train(data, m0 = list(), m1 = list(), config = config)
  expect_null(recorded$timing_truth)
})

test_that("train_m2's governed-family shortcut forwards timing_truth too", {
  recorded <- new.env()
  fake_train <- function(data, m0, m1, config, m1_train_preds = NULL,
                         detector = run_ignition_weekly,
                         timing_mode = c("legacy", "fractional"),
                         timing_truth = NULL, ...) {
    recorded$timing_truth <- timing_truth
    list(ok = TRUE)
  }
  testthat::local_mocked_bindings(m2_subset_train = fake_train, .package = "PAGe")

  data <- data.frame(season = "A", weekF = 1:2, y = 1, N = 10, stringsAsFactors = FALSE)
  config <- m2_subset_config()
  truth <- data.frame(season = "A", ignition_target_weekF = 5.5, stringsAsFactors = FALSE)

  PAGe:::train_m2(data, m0 = list(), m1 = list(), best_spec = config, timing_truth = truth)
  expect_identical(recorded$timing_truth, truth)
})
