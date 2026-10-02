test_that("page_label_ignitions preserves decimal expert labels and integer training anchors", {
  d <- rbind(
    data.frame(season = "2022-23", weekF = 10:14, y = c(1, 2, 4, 9, 15), N = 1000),
    data.frame(season = "2023-24", weekF = 10:14, y = c(1, 3, 5, 8, 13), N = 1000)
  )
  d$p <- d$y / d$N
  x <- page_label_ignitions(
    d,
    ignition_weeks = c("2022-23" = 12.75, "2023-24" = 13.2),
    annotator = "test",
    interactive = FALSE
  )
  expect_s3_class(x, "page_ignition_label_set")
  expect_equal(x$table$ignition_week_decimal, c(12.75, 13.2))
  expect_equal(unname(x$manual_labels), c(12L, 13L))
  expect_equal(names(x$manual_labels), c("2022-23", "2023-24"))
  expect_true(all(vapply(x$annotations, inherits, logical(1), "page_expert_ignition_annotation_v2")))
})

test_that("page_label_ignitions fails closed on incomplete or invalid reproducible labels", {
  d <- data.frame(season = rep(c("2022-23", "2023-24"), each = 3), weekF = rep(10:12, 2), y = 1:6, N = 1000)
  d$p <- d$y / d$N
  expect_error(
    page_label_ignitions(d, ignition_weeks = c("2022-23" = 11), annotator = "test", interactive = FALSE),
    "Missing ignition"
  )
  expect_error(
    page_label_ignitions(d, ignition_weeks = c("2022-23" = 11, "2022-23" = 12), annotator = "test", interactive = FALSE),
    "uniquely named"
  )
  expect_error(
    page_label_ignitions(d[d$season == "2022-23", ], ignition_weeks = c("2022-23" = 99), annotator = "test", interactive = FALSE),
    "ignition_week_decimal"
  )
  expect_error(page_label_ignitions(d, annotator = "test", interactive = FALSE), "Supply `ignition_weeks`")
})

test_that("page_train forwards user labels and never falls back to defaults", {
  d <- rbind(
    data.frame(season = "2022-23", weekF = 10:14, y = c(1, 2, 4, 9, 15), N = 1000),
    data.frame(season = "2023-24", weekF = 10:14, y = c(1, 3, 5, 8, 13), N = 1000)
  )
  d$p <- d$y / d$N
  seen <- NULL
  testthat::local_mocked_bindings(
    train_pipeline = function(allD, mode, exclude, prospective_holdout, n_cores,
                              checkpoint_dir, verbose, manual_labels, timing_mode, ...) {
      seen <<- list(labels = manual_labels, timing_mode = timing_mode, mode = mode)
      structure(list(mode = mode, kit = list(fake = TRUE)), class = c("page_training_result", "list"))
    },
    .package = "PAGe"
  )
  x <- page_train(
    d,
    ignition_weeks = c("2022-23" = 12.75, "2023-24" = 13.2),
    annotator = "test",
    interactive = FALSE,
    prospective_holdout = NULL,
    n_cores = 1,
    verbose = FALSE
  )
  expect_s3_class(x, "page_training_workflow")
  expect_equal(seen$labels, c("2022-23" = 12L, "2023-24" = 13L))
  expect_identical(seen$timing_mode, "legacy")
  expect_identical(seen$mode, "refresh")
})

test_that("page_train requires labels for every trainable season", {
  d <- rbind(
    data.frame(season = "2022-23", weekF = 10:14, y = 1:5, N = 1000),
    data.frame(season = "2023-24", weekF = 10:14, y = 2:6, N = 1000)
  )
  d$p <- d$y / d$N
  ann <- page_label_ignitions(
    d,
    seasons = "2022-23",
    ignition_weeks = c("2022-23" = 12.5),
    annotator = "test",
    interactive = FALSE
  )
  expect_error(
    page_train(d, labels = ann, prospective_holdout = NULL, n_cores = 1, verbose = FALSE),
    "Missing: 2023-24"
  )
})

test_that("unreleased prospective holdout does not require or inject its ignition label", {
  d <- rbind(
    data.frame(season = "2022-23", weekF = 10:14, y = 1:5, N = 1000),
    data.frame(season = "2023-24", weekF = 10:14, y = 2:6, N = 1000)
  )
  d$p <- d$y / d$N
  labels <- page_label_ignitions(
    d,
    seasons = "2022-23",
    ignition_weeks = c("2022-23" = 12.5),
    annotator = "test",
    interactive = FALSE
  )
  seen <- NULL
  testthat::local_mocked_bindings(
    train_pipeline = function(allD, mode, exclude, prospective_holdout, n_cores,
                              checkpoint_dir, verbose, manual_labels, timing_mode, ...) {
      seen <<- list(labels = manual_labels, holdout = prospective_holdout)
      structure(list(mode = mode, kit = list(fake = TRUE)), class = c("page_training_result", "list"))
    },
    .package = "PAGe"
  )
  x <- page_train(
    d,
    labels = labels,
    prospective_holdout = "2023-24",
    n_cores = 1,
    verbose = FALSE
  )
  expect_s3_class(x, "page_training_workflow")
  expect_identical(seen$holdout, "2023-24")
  expect_equal(seen$labels, c("2022-23" = 12L))
  expect_false("2023-24" %in% names(seen$labels))
})



test_that("supplied holdout and excluded labels are stripped before training", {
  d <- rbind(
    data.frame(season = "2021-22", weekF = 10:14, y = 1:5, N = 1000),
    data.frame(season = "2022-23", weekF = 10:14, y = 2:6, N = 1000),
    data.frame(season = "2023-24", weekF = 10:14, y = 3:7, N = 1000)
  )
  d$p <- d$y / d$N
  labels <- page_label_ignitions(
    d,
    ignition_weeks = c("2021-22" = 11.5, "2022-23" = 12.5, "2023-24" = 13.5),
    annotator = "test",
    interactive = FALSE
  )
  seen <- NULL
  testthat::local_mocked_bindings(
    train_pipeline = function(allD, mode, exclude, prospective_holdout, n_cores,
                              checkpoint_dir, verbose, manual_labels, timing_mode, ...) {
      seen <<- manual_labels
      structure(list(mode = mode, kit = list(fake = TRUE)), class = c("page_training_result", "list"))
    },
    .package = "PAGe"
  )
  page_train(
    d,
    labels = labels,
    prospective_holdout = "2023-24",
    exclude = "2021-22",
    n_cores = 1,
    verbose = FALSE
  )
  expect_equal(seen, c("2022-23" = 12L))
})

test_that("automatic labeling excludes unreleased holdout and excluded seasons", {
  d <- rbind(
    data.frame(season = "2021-22", weekF = 10:14, y = 1:5, N = 1000),
    data.frame(season = "2022-23", weekF = 10:14, y = 2:6, N = 1000),
    data.frame(season = "2023-24", weekF = 10:14, y = 3:7, N = 1000)
  )
  d$p <- d$y / d$N
  seen_seasons <- NULL
  seen_labels <- NULL
  testthat::local_mocked_bindings(
    page_label_ignitions = function(data, ignition_weeks, seasons, annotator, interactive) {
      seen_seasons <<- seasons
      structure(
        list(manual_labels = stats::setNames(rep(12L, length(seasons)), seasons), table = data.frame()),
        class = "page_ignition_label_set"
      )
    },
    train_pipeline = function(allD, mode, exclude, prospective_holdout, n_cores,
                              checkpoint_dir, verbose, manual_labels, timing_mode, ...) {
      seen_labels <<- manual_labels
      structure(list(mode = mode, kit = list(fake = TRUE)), class = c("page_training_result", "list"))
    },
    .package = "PAGe"
  )
  x <- page_train(
    d,
    prospective_holdout = "2023-24",
    exclude = "2021-22",
    annotator = "test",
    interactive = TRUE,
    n_cores = 1,
    verbose = FALSE
  )
  expect_s3_class(x, "page_training_workflow")
  expect_identical(seen_seasons, "2022-23")
  expect_equal(seen_labels, c("2022-23" = 12L))
  expect_false(any(c("2021-22", "2023-24") %in% seen_seasons))
})

test_that("training workflow print methods are concise", {
  labels <- structure(list(manual_labels = c("2022-23" = 12L)), class = "page_ignition_label_set")
  expect_output(print(labels), "PAGe ignition labels")
  wf <- structure(list(labels = labels, training_result = list(mode = "refresh"), kit = list()), class = "page_training_workflow")
  expect_output(print(wf), "deployment kit: ready")
})
