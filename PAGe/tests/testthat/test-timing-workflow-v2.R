test_that("timing-v2 review and finalization preserve both labels", {
  raw <- data.frame(
    season = rep("demo", 6), weekF = 1:6,
    y = c(0L, 1L, 3L, 8L, 6L, 2L), N = rep(10L, 6)
  )
  review <- PAGe::review_season_timing_v2(raw, p_threshold = 0.2)
  labels <- PAGe::finalize_season_timing_v2(
    review,
    ignition = c(2L, 3L), peak = 4L, note = "two-week timing review"
  )

  expect_s3_class(review, "page_timing_review_v2")
  expect_s3_class(labels, "page_season_timing_v2")
  expect_equal(labels$ignition$weeks, c(2L, 3L))
  expect_equal(labels$peak$weeks, c(3L, 4L))
  expect_equal(labels$scoring_ignition_labels, c(demo = 2L))
  expect_equal(labels$scoring_peak_labels, c(demo = 3L))
  expect_equal(labels$evidence$scoring_weekF, c(2L, 3L))
  expect_equal(labels$rationale$note, "two-week timing review")
  expect_equal(labels$provenance$method, "finalize_season_timing_v2")
  expect_null(labels$review)
  expect_equal(labels$review_summary$season, "demo")
  expect_equal(PAGe::as_manual_labels_v2(labels), c(demo = 2L))
  expect_equal(PAGe::as_manual_labels_v2(list(named = labels)), c(demo = 2L))
})

test_that("timing-v2 review can select one season from combined data", {
  raw <- data.frame(
    season = rep(c("a", "b"), each = 4), weekF = rep(1:4, 2),
    y = c(0L, 1L, 3L, 2L, 0L, 2L, 4L, 3L), N = rep(10L, 8)
  )
  review <- PAGe::review_season_timing_v2(raw, season = "b")

  expect_equal(unique(review$signals$season), "b")
  expect_equal(review$provenance$season, "b")
})

test_that("timing-v2 application uses recorded season lengths and peak scores", {
  raw <- data.frame(
    season = rep(c("a", "b"), each = 4), weekF = rep(1:4, 2),
    y = c(0L, 1L, 3L, 2L, 0L, 2L, 4L, 3L), N = rep(10L, 8)
  )
  make_labels <- function(season, ignition, peak) {
    review <- PAGe::review_season_timing_v2(raw[raw$season == season, , drop = FALSE])
    PAGe::finalize_season_timing_v2(
      review,
      ignition = ignition, peak = peak, n_weeks = 4L
    )
  }
  labels <- list(
    make_labels("a", c(2L, 3L), c(3L, 4L)),
    make_labels("b", 2L, 3L)
  )
  out <- PAGe::apply_timing_labels_v2(raw, labels, anchor_week = 2L)

  expect_equal(out$iWeek, c(2L, 2L, 2L, 2L, 1L, 1L, 1L, 1L))
  expect_equal(out$peak_weekF, rep(c(3L, 2L), each = 4))
  expect_equal(out$y, raw$y)
  expect_equal(
    attr(out, "timing_evidence_v2")$event_type,
    c("ignition", "peak", "ignition", "peak")
  )
})

test_that("timing-v2 rejects extreme labels before integer arithmetic", {
  expect_error(
    PAGe:::validate_timing_labels(peak = -(.Machine$integer.max - 1), n_weeks = 52L),
    "at least week 2"
  )
  expect_error(
    PAGe:::validate_timing_labels(peak = c(-1, .Machine$integer.max), n_weeks = 52L),
    "weeks 1 through 52"
  )
})

test_that("timing-v2 application distinguishes unnamed and duplicate seasons", {
  unnamed <- PAGe:::label_season_timing(ignition = c(2L, 3L), peak = c(3L, 4L), n_weeks = 4L)
  expect_error(PAGe::apply_timing_labels_v2(
    data.frame(season = "a", weekF = 1:4, y = 1:4, N = rep(10L, 4)),
    unnamed
  ), "must have season names")
})

test_that("timing-v2 adapter rejects mixed input and preserves legacy isolation", {
  labels <- PAGe:::label_season_timing(
    season = "demo", ignition = c(2L, 3L), peak = c(3L, 4L), n_weeks = 4L
  )
  expect_error(
    PAGe::as_manual_labels_v2(PAGe:::label_season_timing(
      ignition = c(2L, 3L), peak = c(3L, 4L), n_weeks = 4L
    )),
    "season names"
  )
  expect_equal(labels$ignition$weeks, c(2L, 3L))
  expect_equal(PAGe::as_manual_labels_v2(labels), c(demo = 2L))
  expect_true("timing_labels" %in% names(formals(PAGe::train_pipeline)))
  expect_error(
    PAGe::train_pipeline(
      data.frame(season = "demo", weekF = 1L, y = 1L, N = 2L),
      manual_labels = c(demo = 2L), timing_labels = labels,
      verbose = FALSE
    ),
    "either `manual_labels` or `timing_labels`"
  )
})
