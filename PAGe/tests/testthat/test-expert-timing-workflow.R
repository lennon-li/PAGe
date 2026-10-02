test_that("expert ignition review creates a Plotly season review without assigning truth", {
  d <- data.frame(
    season = rep("2022-23", 8),
    weekF = 16:23,
    y = c(2, 4, 7, 12, 19, 26, 31, 29),
    N = rep(200, 8)
  )

  r <- review_expert_ignition(d)

  expect_s3_class(r, "page_expert_ignition_review_v2")
  expect_s3_class(r$plot, "plotly")
  expect_equal(r$season, "2022-23")
  expect_equal(r$provenance$coordinate_version, "page-continuous-week-v1")
  expect_false("ignition_week_decimal" %in% names(r))
  expect_false("peak_week_decimal" %in% names(r))
})

test_that("review can finalize explicit decimal expert ignition label", {
  d <- data.frame(
    season = rep("2022-23", 52),
    weekF = 1:52,
    y = pmin(100L, round(5 + 80 * exp(-((1:52 - 27) / 5)^2))),
    N = rep(500, 52)
  )
  r <- review_expert_ignition(d)
  a <- finalize_expert_ignition_review(
    r,
    ignition_week_decimal = 18.4,
    annotator = "epi-1",
    annotation_version = "labels-v2-pass1",
    positivity_version = "positivity-v1"
  )

  expect_equal(a$ignition_week_decimal, 18.4)
  expect_equal(a$data_snapshot_id, r$provenance$data_snapshot_id)
  expect_false("peak_week_decimal" %in% names(a))
})

test_that("existing expert ignition annotation is overlaid only on matching season", {
  d <- data.frame(season = rep("A", 4), weekF = 1:4, y = c(1, 2, 3, 2), N = rep(20, 4))
  a <- new_expert_ignition_annotation(
    season = "A", ignition_week_decimal = 1.2,
    n_weeks = 4, annotator = "epi", annotation_version = "v2",
    annotated_at = "2026-09-22T14:00:00Z", data_snapshot_id = "other-snapshot",
    positivity_version = "p-v1"
  )
  r <- review_expert_ignition(d, existing_annotation = a)
  expect_length(plotly::plotly_build(r$plot)$x$layout$shapes, 1)

  bad <- a
  bad$season <- "B"
  expect_error(review_expert_ignition(d, existing_annotation = bad), "does not match")
})

test_that("versioned expert ignition annotation writer refuses silent overwrite", {
  a <- new_expert_ignition_annotation(
    season = "A", ignition_week_decimal = 1.2,
    n_weeks = 4, annotator = "epi", annotation_version = "v2",
    annotated_at = "2026-09-22T14:00:00Z", data_snapshot_id = "snapshot",
    positivity_version = "p-v1"
  )
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)

  write_expert_ignition_annotations(a, path)
  expect_true(file.exists(path))
  out <- utils::read.csv(path, stringsAsFactors = FALSE)
  expect_equal(out$ignition_week_decimal, 1.2)
  expect_false("peak_week_decimal" %in% names(out))

  expect_error(write_expert_ignition_annotations(a, path), "Refusing to overwrite")
  expect_silent(write_expert_ignition_annotations(a, path, overwrite = TRUE))
})
