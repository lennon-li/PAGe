test_that("expert decimal timing preserves sub-week values exactly", {
  x <- PAGe:::new_expert_timing_annotation(
    season = "2022-23",
    ignition_week_decimal = 18.4,
    peak_week_decimal = 27.2,
    annotator = "epi-1",
    annotation_version = "v1",
    annotated_at = "2026-09-22T13:00:00Z",
    data_snapshot_id = "snapshot-abc",
    positivity_version = "positivity-v1"
  )

  expect_s3_class(x, "page_expert_timing_annotation_v1")
  expect_equal(x$ignition_week_decimal, 18.4)
  expect_equal(x$peak_week_decimal, 27.2)
  expect_equal(x$coordinate_version, "page-continuous-week-v1")
  expect_equal(x$schema_version, "expert-timing-annotation-v1")
})

test_that("expert decimal timing is separate from legacy integer-pair normalization", {
  legacy <- PAGe:::validate_timing_labels(ignition = 18L, peak = 27L)
  expert <- PAGe:::new_expert_timing_annotation(
    season = "demo",
    ignition_week_decimal = 18.4,
    peak_week_decimal = 27.2,
    annotator = "epi-1",
    annotation_version = "v1",
    annotated_at = "2026-09-22T13:00:00Z",
    data_snapshot_id = "snapshot-abc",
    positivity_version = "positivity-v1"
  )

  expect_equal(legacy$ignition$weeks, c(17L, 18L))
  expect_equal(expert$ignition_week_decimal, 18.4)
  expect_false("weeks" %in% names(expert))
})

test_that("52- and 53-week expert timing bounds are explicit", {
  x53 <- PAGe:::new_expert_timing_annotation(
    season = "long",
    ignition_week_decimal = 51.2,
    peak_week_decimal = 53.8,
    n_weeks = 53L,
    annotator = "epi-1",
    annotation_version = "v1",
    annotated_at = "2026-09-22T13:00:00Z",
    data_snapshot_id = "snapshot-long",
    positivity_version = "positivity-v1"
  )
  expect_equal(x53$n_weeks, 53L)

  expect_error(
    PAGe:::new_expert_timing_annotation(
      season = "short", ignition_week_decimal = 51.2, peak_week_decimal = 53.1,
      n_weeks = 52L, annotator = "epi-1", annotation_version = "v1",
      annotated_at = "2026-09-22T13:00:00Z", data_snapshot_id = "snapshot-short",
      positivity_version = "positivity-v1"
    ),
    "\\[1, n_weeks \\+ 1\\)"
  )
})

test_that("expert timing enforces ignition before peak", {
  expect_error(
    PAGe:::new_expert_timing_annotation(
      season = "demo", ignition_week_decimal = 27.2, peak_week_decimal = 27.2,
      annotator = "epi-1", annotation_version = "v1",
      annotated_at = "2026-09-22T13:00:00Z", data_snapshot_id = "snapshot",
      positivity_version = "positivity-v1"
    ),
    "strictly before"
  )
})

test_that("uncertainty intervals must contain point estimates", {
  x <- PAGe:::new_expert_timing_annotation(
    season = "demo",
    ignition_week_decimal = 18.4,
    peak_week_decimal = 27.2,
    ignition_interval = c(18.1, 18.8),
    peak_interval = c(26.8, 27.6),
    peak_status = "uncertain",
    annotator = "epi-1",
    annotation_version = "v1",
    annotated_at = "2026-09-22T13:00:00Z",
    data_snapshot_id = "snapshot",
    positivity_version = "positivity-v1"
  )
  expect_equal(x$peak_interval, c(26.8, 27.6))

  expect_error(
    PAGe:::new_expert_timing_annotation(
      season = "demo", ignition_week_decimal = 18.4, peak_week_decimal = 27.2,
      peak_interval = c(27.3, 27.8), annotator = "epi-1", annotation_version = "v1",
      annotated_at = "2026-09-22T13:00:00Z", data_snapshot_id = "snapshot",
      positivity_version = "positivity-v1"
    ),
    "contain its point estimate"
  )
})

test_that("unlabelable peak can omit a point only with documented reason", {
  x <- PAGe:::new_expert_timing_annotation(
    season = "ambiguous",
    ignition_week_decimal = 18.4,
    peak_week_decimal = NA_real_,
    peak_status = "unlabelable",
    annotator = "epi-1",
    annotation_version = "v1",
    annotated_at = "2026-09-22T13:00:00Z",
    data_snapshot_id = "snapshot",
    positivity_version = "positivity-v1",
    comment = "Two distinct waves without a defensible primary peak."
  )
  expect_true(is.na(x$peak_week_decimal))

  expect_error(
    PAGe:::new_expert_timing_annotation(
      season = "ambiguous", ignition_week_decimal = 18.4,
      peak_week_decimal = NA_real_, peak_status = "unlabelable",
      annotator = "epi-1", annotation_version = "v1",
      annotated_at = "2026-09-22T13:00:00Z", data_snapshot_id = "snapshot",
      positivity_version = "positivity-v1"
    ),
    "comment"
  )
})

test_that("expert annotation provenance is required", {
  base <- list(
    season = "demo", ignition_week_decimal = 18.4, peak_week_decimal = 27.2,
    annotator = "epi-1", annotation_version = "v1",
    annotated_at = "2026-09-22T13:00:00Z", data_snapshot_id = "snapshot",
    positivity_version = "positivity-v1"
  )

  missing_snapshot <- base
  missing_snapshot$data_snapshot_id <- ""
  expect_error(do.call(PAGe:::new_expert_timing_annotation, missing_snapshot), "data_snapshot_id")

  missing_annotator <- base
  missing_annotator$annotator <- ""
  expect_error(do.call(PAGe:::new_expert_timing_annotation, missing_annotator), "annotator")
})

test_that("compiled expert annotations are deterministic and flat", {
  a <- PAGe:::new_expert_timing_annotation(
    season = "2021-22", ignition_week_decimal = 17.8, peak_week_decimal = 26.6,
    ignition_interval = c(17.5, 18.0), peak_interval = c(26.2, 27.0),
    peak_status = "plateau", annotator = "epi-1", annotation_version = "v1",
    annotated_at = "2026-09-22T13:00:00Z", data_snapshot_id = "snap-a",
    positivity_version = "positivity-v1", comment = "Broad top."
  )
  b <- PAGe:::new_expert_timing_annotation(
    season = "2022-23", ignition_week_decimal = 18.4, peak_week_decimal = 27.2,
    annotator = "epi-1", annotation_version = "v1",
    annotated_at = "2026-09-22T13:05:00Z", data_snapshot_id = "snap-b",
    positivity_version = "positivity-v1"
  )

  one <- PAGe:::compile_expert_timing_annotations(list(a, b))
  two <- PAGe:::compile_expert_timing_annotations(list(a, b))

  expect_identical(one, two)
  expect_equal(one$season, c("2021-22", "2022-23"))
  expect_equal(one$peak_week_decimal, c(26.6, 27.2))
  expect_equal(one$peak_interval_low, c(26.2, NA_real_))
  expect_true(all(c("coordinate_version", "data_snapshot_id", "positivity_version") %in% names(one)))
})
