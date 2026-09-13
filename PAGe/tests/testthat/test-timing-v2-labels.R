test_that("singleton labels expand and preserve legacy scalar references", {
  labels <- PAGe:::validate_timing_labels(
    ignition = 18L, peak = c(27L, 28L), season = "demo", n_weeks = 52L
  )

  expect_s3_class(labels, "page_timing_labels_v2")
  expect_equal(labels$ignition$original_input, 18L)
  expect_equal(labels$ignition$weeks, c(17L, 18L))
  expect_equal(labels$ignition$scoring_weekF, 17L)
  expect_equal(labels$scoring_ignition_labels, c(demo = 17L))
  expect_equal(labels$peak$original_input, c(27L, 28L))
  expect_equal(labels$peak$weeks, c(27L, 28L))
  expect_equal(labels$scoring_peak_labels, c(demo = 27L))
})

test_that("ignition and peak labels can be supplied independently", {
  ignition <- PAGe:::validate_timing_labels(ignition = c(2L, 3L), n_weeks = 4L)
  peak <- PAGe:::validate_timing_labels(peak = 3L, n_weeks = 4L)

  expect_equal(ignition$ignition$weeks, c(2L, 3L))
  expect_null(ignition$peak)
  expect_null(peak$ignition)
  expect_equal(peak$peak$weeks, c(2L, 3L))
})

test_that("invalid and out-of-season labels fail clearly", {
  expect_error(PAGe:::validate_timing_labels(ignition = 1L), "at least week 2")
  expect_error(PAGe:::validate_timing_labels(peak = c(18L, 20L)), "consecutive")
  expect_error(PAGe:::validate_timing_labels(peak = c(18L, 17L, 16L)), "one integer")
  expect_error(PAGe:::validate_timing_labels(peak = 53L, n_weeks = 52L), "weeks 1 through 52")
  expect_error(PAGe:::validate_timing_labels(peak = 0L, n_weeks = 53L), "at least week 2")
  expect_error(PAGe:::validate_timing_labels(), "at least one")
})

test_that("invalid season lengths fail before calendar comparison", {
  calendar53 <- PAGe:::new_timing_calendar(season = "demo", n_weeks = 53L)

  expect_error(
    PAGe:::validate_timing_labels(peak = 30L, n_weeks = 1.5, calendar = calendar53),
    "one integer of at least 2"
  )
  expect_error(
    PAGe:::validate_timing_labels(peak = 30L, n_weeks = Inf, calendar = calendar53),
    "one integer of at least 2"
  )
  expect_error(
    PAGe:::validate_timing_labels(peak = 30L, n_weeks = 2^31, calendar = calendar53),
    "one integer of at least 2"
  )
  expect_error(
    PAGe:::validate_timing_labels(peak = 30L, n_weeks = TRUE, calendar = calendar53),
    "one integer of at least 2"
  )
})

test_that("52- and 53-week calendars validate and preserve week boundaries", {
  calendar52 <- PAGe:::new_timing_calendar(n_weeks = 52L)
  calendar53 <- PAGe:::new_timing_calendar(season = "demo", n_weeks = 53L)
  inferred53 <- PAGe:::new_timing_calendar(
    week_starts = as.Date("2025-01-01") + 7 * 0:52
  )

  expect_s3_class(calendar52, "page_timing_calendar_v2")
  expect_equal(calendar52$n_weeks, 52L)
  expect_equal(calendar53$n_weeks, 53L)
  expect_equal(inferred53$n_weeks, 53L)
  expect_equal(calendar53$week_table$weekF, 1:53)
  expect_equal(calendar53$coordinate_convention, "week w is [w, w + 1); dates use actual week boundaries")
  expect_equal(PAGe:::validate_timing_labels(peak = 53L, calendar = calendar53)$peak$weeks, c(52L, 53L))
  expect_equal(PAGe:::label_season_timing(peak = 30L, calendar = calendar53)$n_weeks, 53L)
  expect_error(
    PAGe:::label_season_timing(peak = 30L, n_weeks = 52L, calendar = calendar53),
    "agree"
  )
  expect_error(
    PAGe:::label_season_timing(season = "other", peak = 30L, calendar = calendar53),
    "calendar\\$season"
  )
})

test_that("dated calendars map dates and fractional coordinates consistently", {
  starts <- as.Date("2025-01-01") + 7 * 0:3
  calendar <- PAGe:::new_timing_calendar(
    season = "demo", n_weeks = 4L, week_starts = starts
  )

  expect_equal(PAGe:::date_to_timing(calendar, starts[1L]), 1)
  expect_equal(PAGe:::date_to_timing(calendar, starts[2L] + 3), 2 + 3 / 7)
  expect_equal(PAGe:::timing_to_week(calendar, c(1, 2.4, 4)), c(1L, 2L, 4L))
  expect_equal(PAGe:::timing_to_date(calendar, 2.5), starts[2L] + 3.5, tolerance = 1e-7)
  expect_error(PAGe:::date_to_timing(calendar, starts[4L] + 7), "outside")
  expect_error(PAGe:::timing_to_week(calendar, 5), "\\[1, n_weeks \\+ 1\\)")
})

test_that("evidence compilation retains original and normalized inputs", {
  labels <- PAGe:::label_season_timing(
    season = "2025-26", ignition = 19L, peak = c(27L, 28L)
  )
  evidence <- PAGe:::compile_timing_evidence(labels)

  expect_equal(evidence$event_type, c("ignition", "peak"))
  expect_equal(evidence$original_input[[1L]], 19L)
  expect_equal(evidence$normalized_weeks[[1L]], c(18L, 19L))
  expect_equal(evidence$scoring_weekF, c(18L, 27L))
  expect_equal(labels$legacy_scalar_labels$ignition, c(`2025-26` = 18L))
})

test_that("label validation covers reversed pairs, types, and legacy isolation", {
  legacy_before <- PAGe:::page_manual_ignition_labels()
  labels <- PAGe:::validate_timing_labels(ignition = c(18L, 17L), peak = c(27L, 28L))

  expect_equal(labels$ignition$original_input, c(18L, 17L))
  expect_equal(labels$ignition$weeks, c(17L, 18L))
  expect_false("ignition_labels" %in% names(labels))
  expect_false("peak_labels" %in% names(labels))
  expect_identical(PAGe:::page_manual_ignition_labels(), legacy_before)

  expect_error(PAGe:::validate_timing_labels(peak = 18.5), "one integer")
  expect_error(PAGe:::validate_timing_labels(peak = TRUE), "one integer")
  expect_error(PAGe:::validate_timing_labels(peak = "18"), "one integer")
})

test_that("dated 53-week calendars and missing values behave explicitly", {
  starts <- as.Date("2025-01-01") + 7 * 0:52
  calendar <- PAGe:::new_timing_calendar(
    season = "long", n_weeks = 53L, week_starts = starts
  )

  expect_equal(PAGe:::date_to_timing(calendar, starts[53L] + 3), 53 + 3 / 7)
  expect_equal(PAGe:::timing_to_week(calendar, 53.9), 53L)
  expect_equal(PAGe:::timing_to_date(calendar, 53.5), starts[53L] + 3.5, tolerance = 1e-7)
  expect_true(is.na(PAGe:::date_to_timing(calendar, as.Date(NA))))
  expect_true(is.na(PAGe:::timing_to_week(calendar, NA_real_)))
  expect_error(PAGe:::date_to_timing(calendar, as.Date(NA), allow_na = FALSE), "cannot")
  expect_error(PAGe:::timing_to_week(calendar, NA_real_, allow_na = FALSE), "cannot")

  expect_equal(
    PAGe:::date_to_timing(calendar, c(starts[1L], as.Date(NA), starts[2L] + 3)),
    c(1, NA_real_, 2 + 3 / 7)
  )
  expect_equal(
    PAGe:::timing_to_week(calendar, c(1, NA_real_, 53.9)),
    c(1L, NA_integer_, 53L)
  )
  expect_equal(
    PAGe:::timing_to_date(calendar, c(1, NA_real_, 53.5)),
    c(starts[1L], as.Date(NA), starts[53L] + 3.5)
  )
})

test_that("calendar validation rejects malformed and undated mappings", {
  expect_error(PAGe:::new_timing_calendar(n_weeks = 4L, week_ends = as.Date("2025-01-08")), "week_starts")
  expect_error(
    PAGe:::new_timing_calendar(n_weeks = 4L, week_starts = as.Date("2025-01-01") + 7 * 0:2),
    "one date per"
  )
  starts <- as.Date("2025-01-01") + 7 * 0:3
  ends <- c(starts[2:4], starts[4] + 7)
  ends[2] <- ends[2] + 1
  expect_error(PAGe:::new_timing_calendar(n_weeks = 4L, week_starts = starts, week_ends = ends), "contiguous")

  undated <- PAGe:::new_timing_calendar(n_weeks = 4L)
  expect_error(PAGe:::date_to_timing(undated, as.Date("2025-01-01")), "no dates")
  expect_error(PAGe:::timing_to_date(undated, 2.5), "no dates")
  expect_error(PAGe:::validate_timing_calendar(list()), "created by")

  partially_dated <- PAGe:::new_timing_calendar(
    n_weeks = 4L, week_starts = starts
  )
  partially_dated$week_table$start_date[2L] <- as.Date(NA)
  expect_error(PAGe:::validate_timing_calendar(partially_dated), "either complete")

  bad_midpoint <- PAGe:::new_timing_calendar(
    n_weeks = 4L, week_starts = starts
  )
  bad_midpoint$week_table$midpoint_date[2L] <- as.Date(NA)
  expect_error(PAGe:::validate_timing_calendar(bad_midpoint), "midpoint")

  bad_n_weeks <- undated
  bad_n_weeks$n_weeks <- 2^31
  expect_error(PAGe:::validate_timing_calendar(bad_n_weeks), "one integer of at least 2")
})

test_that("single-event evidence validates its input", {
  labels <- PAGe:::label_season_timing(peak = 12L, season = "demo")
  evidence <- PAGe:::compile_timing_evidence(labels)

  expect_equal(nrow(evidence), 1L)
  expect_equal(evidence$event_type, "peak")
  expect_error(PAGe:::compile_timing_evidence(list()), "created by")
})

test_that("timing labels reject unsafe integer conversions", {
  expect_error(PAGe:::validate_timing_labels(peak = .Machine$integer.max + 1), "weeks 1 through")
  expect_error(PAGe:::validate_timing_labels(peak = -(.Machine$integer.max + 1)), "at least week 2")
  expect_error(PAGe:::validate_timing_labels(peak = 1e20), "weeks 1 through")
})
