test_that("ignition review returns transparent signals and does not mutate data", {
  raw <- data.frame(
    season = rep("demo", 5), weekF = 1:5,
    y = c(0, 1, 2, 5, 4), N = rep(10, 5)
  )
  before <- raw
  review <- PAGe::review_ignition_label(
    raw, smooth_window = 3L, p_threshold = 0.2, confidence = 0.95
  )

  expect_s3_class(review, "page_ignition_review")
  expect_true(inherits(review$plot, "ggplot"))
  expect_true(all(c("weekF", "p", "p_ci_lo", "p_smooth",
                    "threshold_crossing") %in% names(review$signals)))
  expect_equal(raw, before)
  expect_equal(review$summary$season, "demo")
  expect_true(nrow(review$candidates) >= 1L)
  expect_true(is.character(review$provenance$data_hash))
})

test_that("finalization validates the selected week and records provenance", {
  review <- PAGe::review_ignition_label(
    data.frame(season = rep("demo", 4), weekF = 1:4,
               y = c(0, 1, 3, 4), N = rep(10, 4)),
    candidate_window = c(2L, 4L)
  )
  label <- PAGe::finalize_ignition_label(
    review, 3L, annotator = "tester", note = "sustained rise"
  )

  expect_s3_class(label, "page_ignition_label")
  expect_equal(label$labels, c(demo = 3L))
  expect_equal(label$rationale$annotator, "tester")
  expect_equal(label$provenance$selected_weekF, 3L)
  expect_error(PAGe::finalize_ignition_label(review, 1L), "outside")
  expect_error(PAGe::finalize_ignition_label(review, 9L), "not observed")
})

test_that("finalized labels produce phase and aligned week without changing counts", {
  raw <- data.frame(
    season = rep(c("a", "b"), each = 3), weekF = rep(1:3, 2),
    y = c(0, 2, 3, 1, 2, 4), N = rep(10, 6),
    nW_true = rep(4L, 6)
  )
  out <- PAGe::apply_ignition_labels(
    raw, c(a = 2L, b = 3L), anchor_week = 2L,
    n_weeks_col = "nW_true"
  )

  expect_equal(out$iWeek, c(2L, 2L, 2L, 3L, 3L, 3L))
  expect_equal(out$phase, c(0L, 1L, 1L, 0L, 0L, 1L))
  expect_equal(out$newWeek, c(1L, 2L, 3L, 4L, 1L, 2L))
  expect_equal(out$y, raw$y)
  expect_equal(out$N, raw$N)
  expect_equal(attr(out, "anchorWeek"), 2L)
})

test_that("label application rejects missing or unnamed labels", {
  raw <- data.frame(season = "a", weekF = 1L, y = 1L, N = 2L)
  expect_error(PAGe::apply_ignition_labels(raw, c(b = 1L)), "Missing")
  expect_error(PAGe::apply_ignition_labels(raw, 1L), "named")
  expect_error(PAGe::apply_ignition_labels(raw, c(b = 1L), require_all = FALSE), "match")
})

test_that("peak review exposes missingness, ties, and validated selection", {
  raw <- data.frame(
    season = rep("demo", 6), weekF = 1:6,
    y = c(0L, 1L, 4L, 8L, 8L, 0L), N = c(10L, 10L, 10L, 10L, 10L, 0L)
  )
  review <- PAGe::review_ignition_label(raw, candidate_window = c(2L, 5L))
  expect_equal(review$peak_summary$missing_weeks, 1L)
  expect_equal(review$peak_candidates, c(4L, 5L))
  expect_true(review$peak_summary$plateau)
  peak <- PAGe::finalize_peak_label(review, 5L, require_candidate = TRUE)
  expect_equal(peak$label, c(demo = 5L))
  expect_error(PAGe::finalize_peak_label(review, 6L), "missing positivity")
  expect_error(PAGe::finalize_peak_label(review, 3L, require_candidate = TRUE), "candidate")
})

test_that("combined finalization returns downstream-ready named labels", {
  raw <- data.frame(season = rep("demo", 5), weekF = 1:5,
                    y = c(0L, 1L, 2L, 8L, 3L), N = rep(10L, 5))
  review <- PAGe::review_ignition_label(raw, candidate_window = c(1L, 5L))
  labels <- PAGe::finalize_season_labels(review, ignition_weekF = 2L, peak_weekF = 4L)
  expect_equal(labels$ignition_labels, c(demo = 2L))
  expect_equal(labels$peak_labels, c(demo = 4L))
  expect_equal(labels$ignition$provenance$review_data_hash,
               labels$peak$provenance$review_data_hash)
})
