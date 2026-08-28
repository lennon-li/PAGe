test_that("run_m1_alignment returns an empty result for an exhausted walk", {
  out <- PAGe::run_m1_alignment(
    kit = list(),
    current_data = data.frame(weekF = 1:4),
    m0_result = list(iWeek_locked = 10L),
    walk_start = 1L,
    verbose = FALSE
  )

  expect_identical(nrow(out$params_df), 0L)
  expect_length(out$per_week, 0L)
  expect_identical(out$m0_result$iWeek_locked, 10L)
})

test_that("m1_walkforward_predictions returns empty output when the walk starts late", {
  out <- PAGe:::m1_walkforward_predictions(
    seasonD = data.frame(season = "2024-25", weekF = 1:4),
    ref = list(),
    hyper = list(),
    ign_out = list(ign_week_locked = 10L)
  )

  expect_s3_class(out, "tbl_df")
  expect_identical(nrow(out), 0L)
})

test_that("train_m2 restores its caller future plan", {
  body_text <- paste(deparse(body(PAGe::train_m2)), collapse = " ")
  expect_match(body_text, "old_future_plan")
  expect_match(body_text, "on\\.exit\\(future::plan\\(old_future_plan\\), add = TRUE\\)")
  expect_false(grepl("future::plan\\(future::sequential\\)", body_text))
})
