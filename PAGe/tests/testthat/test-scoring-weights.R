page_scoring_weights <- PAGe:::page_scoring_weights
page_phase_weights <- PAGe:::page_phase_weights

phase_frame <- function(season, target, ignition, peak) {
  data.frame(
    season = season, target = target,
    ignition = ignition, peak = peak,
    stringsAsFactors = FALSE
  )
}

score_phases <- function(rows, weights = page_scoring_weights(),
                         allow_censored = FALSE) {
  page_phase_weights(
    rows, weights, "season", "target", "ignition", "peak",
    allow_censored = allow_censored
  )
}

test_that("page_scoring_weights validates and classes its object", {
  w <- page_scoring_weights()
  expect_s3_class(w, "page_scoring_weights")
  expect_equal(w$pre_ignition, 0)
  expect_equal(w$rise, 2)
  expect_equal(w$turning, 3)
  expect_equal(w$decline, 1)
  expect_equal(w$turning_before, -1L)
  expect_equal(w$turning_after, 3L)

  custom <- page_scoring_weights(
    pre_ignition = 0.5, rise = 0, turning = 3, decline = 1.5,
    turning_before = 0L, turning_after = 0L
  )
  expect_equal(custom$pre_ignition, 0.5)
  expect_equal(custom$rise, 0)
  expect_equal(custom$turning_before, 0L)
  expect_equal(custom$turning_after, 0L)
})

test_that("page_scoring_weights rejects invalid weights and windows", {
  expect_error(page_scoring_weights(rise = -1), "rise")
  expect_error(page_scoring_weights(turning = NA_real_), "turning")
  expect_error(page_scoring_weights(decline = Inf), "decline")
  expect_error(page_scoring_weights(pre_ignition = c(1, 2)), "pre_ignition")
  expect_error(page_scoring_weights(pre_ignition = "a"), "pre_ignition")
  expect_silent(page_scoring_weights(turning_before = -1L))
  expect_error(page_scoring_weights(turning_after = 1.5), "turning_after")
  expect_error(page_scoring_weights(turning_before = NA_integer_), "turning_before")
  expect_error(page_scoring_weights(turning_after = "x"), "turning_after")
})

test_that("phase boundaries are inclusive at the lower edge", {
  rows <- phase_frame("s1", c(9, 10, 28, 29, 33, 34), 10, 30)
  out <- score_phases(rows)
  expect_equal(
    out$phase,
    c("pre_ignition", "rise", "rise", "turning", "turning", "decline")
  )
  expect_equal(out$weight, c(0, 2, 2, 3, 3, 1))
  expect_true(is.numeric(out$weight))
})

test_that("phase boundaries respect fractional weeks", {
  rows <- phase_frame(
    "s1",
    c(10.4, 10.5, 29.249, 29.25, 33.25, 33.251),
    10.5, 30.25
  )
  out <- score_phases(rows)
  expect_equal(
    out$phase,
    c("pre_ignition", "rise", "rise", "turning", "turning", "decline")
  )
})

test_that("zero windows collapse the turning phase to the peak week", {
  w <- page_scoring_weights(turning_before = 0L, turning_after = 0L)
  rows <- phase_frame("s1", c(9, 10, 29, 30, 31), 10, 30)
  out <- score_phases(rows, w)
  expect_equal(
    out$phase,
    c("pre_ignition", "rise", "rise", "turning", "decline")
  )
})

test_that("custom weights including all-zero are applied verbatim", {
  w <- page_scoring_weights(
    pre_ignition = 0, rise = 5, turning = 0, decline = 0,
    turning_before = -2L, turning_after = 4L
  )
  rows <- phase_frame("s1", c(5, 10, 30, 40), 10, 30)
  out <- score_phases(rows, w)
  expect_equal(out$weight, c(0, 5, 0, 0))

  zero <- page_scoring_weights(0, 0, 0, 0)
  expect_equal(score_phases(rows, zero)$weight, c(0, 0, 0, 0))
})

test_that("a named list is coerced to the scoring-weight contract", {
  rows <- phase_frame("s1", c(10, 30), 10, 30)
  out <- score_phases(rows, list(rise = 7, turning = 3))
  expect_equal(out$weight, c(7, 3))
  expect_error(score_phases(rows, list(bogus = 1)), "bogus")
  expect_error(score_phases(rows, 1), "page_scoring_weights")
})

test_that("censored seasons error by default and label when allowed", {
  complete <- phase_frame("s1", c(10, 30), 10, 30)
  missing_peak <- phase_frame("s2", c(10, 30), 10, NA_real_)
  rows <- rbind(complete, missing_peak)
  expect_error(score_phases(rows), "s2")

  out <- score_phases(rows, allow_censored = TRUE)
  expect_equal(out$phase, c("rise", "turning", "censored", "censored"))
  expect_equal(out$weight, c(2, 3, NA_real_, NA_real_))

  missing_ignition <- phase_frame("s3", c(NA, 30), NA_real_, 20)
  out_i <- score_phases(missing_ignition, allow_censored = TRUE)
  expect_equal(out_i$phase, c("censored", "censored"))
  expect_true(all(is.na(out_i$weight)))
})

test_that("multi-season input is vectorized and order-preserving", {
  rows <- phase_frame(
    c("s1", "s2", "s1", "s2", "s1", "s2"),
    c(5, 5, 20, 11, 31, 13),
    c(10, 5, 10, 5, 10, 5),
    c(30, 12, 30, 12, 30, 12)
  )
  out <- score_phases(rows)
  expect_equal(
    out$phase,
    c("pre_ignition", "rise", "rise", "turning", "turning", "turning")
  )
  expect_equal(out$weight, c(0, 2, 2, 3, 3, 3))
  expect_equal(out$season, rows$season)
  expect_equal(out$target, rows$target)
  expect_true(all(c("phase", "weight") %in% names(out)))
})

test_that("page_phase_weights validates its inputs", {
  rows <- phase_frame("s1", c(10, 30), 10, 30)
  expect_error(page_phase_weights(
    list(), page_scoring_weights(),
    "season", "target", "ignition", "peak"
  ), "rows")
  expect_error(page_phase_weights(
    rows[0, ], page_scoring_weights(),
    "season", "target", "ignition", "peak"
  ), "rows")
  expect_error(page_phase_weights(
    rows, page_scoring_weights(),
    "nope", "target", "ignition", "peak"
  ), "nope")
  expect_error(page_phase_weights(
    rows, page_scoring_weights(),
    "season", "nope", "ignition", "peak"
  ), "nope")

  rows$char_target <- as.character(rows$target)
  expect_error(page_phase_weights(
    rows, page_scoring_weights(),
    "season", "char_target", "ignition", "peak"
  ), "numeric")

  bad_season <- rows
  bad_season$season <- c(NA_character_, "s1")
  expect_error(page_phase_weights(
    bad_season, page_scoring_weights(),
    "season", "target", "ignition", "peak"
  ), "season_col")

  conflicting_i <- phase_frame("s1", c(10, 30), c(10, 11), 30)
  expect_error(score_phases(conflicting_i), "multiple ignition")

  conflicting_p <- phase_frame("s1", c(10, 30), 10, c(30, 31))
  expect_error(score_phases(conflicting_p), "multiple peak")

  missing_target <- phase_frame("s1", c(10, NA), 10, 30)
  expect_error(score_phases(missing_target), "target_col")

  expect_error(
    page_phase_weights(rows, page_scoring_weights(), "season", "target",
      "ignition", "peak",
      allow_censored = NA
    ),
    "allow_censored"
  )
})
