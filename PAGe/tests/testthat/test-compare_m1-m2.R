test_that("compare_m1_m2 is forecast-only and uses equal-season summaries", {
  forecasts <- data.frame(
    season = c("A", "A", "B"), origin = c(1L, 2L, 1L),
    target = c(2L, 4L, 2L), horizon = c(1L, 2L, 1L),
    observed = c(0.2, 0.8, 0.5), m1 = c(0.2, 0.6, 0.4),
    m2 = c(0.3, 0.7, 0.5)
  )
  result <- compare_m1_m2(
    forecasts, "observed", "m1", "m2", "season", "origin", "target", "horizon"
  )
  expect_named(result, c("forecast", "recommendation"))
  expect_equal(result$forecast$matched_rows, 3L)
  expect_equal(result$forecast$overall$equal_season$n_seasons, 2L)
  expect_equal(result$forecast$overall$equal_season$m1_mae, (0.1 + 0.1) / 2)
  expect_equal(result$forecast$overall$equal_season$m2_mae, ((0.1 + 0.1) / 2 + 0) / 2)
  expect_equal(result$recommendation$decision, "use_m2")
  expect_equal(result$recommendation$reasons, "forecast_within_tolerance")
})

test_that("forecast recommendation is conservative when M2 loses", {
  forecasts <- data.frame(
    season = c("A", "B"), origin = 1L, target = 2L, horizon = 1L,
    observed = 0.5, m1 = 0.5, m2 = 0.8
  )
  result <- compare_m1_m2(
    forecasts, "observed", "m1", "m2", "season", "origin", "target", "horizon"
  )
  expect_equal(result$recommendation$decision, "keep_m1")
  expect_contains(result$recommendation$reasons, "forecast_m2_exceeds_tolerance_mae")
})

test_that("denominator weighting is preserved for pooled and equal-season metrics", {
  forecasts <- data.frame(
    season = c("A", "A", "B"), origin = 1:3, target = 2:4, horizon = 1L,
    observed = c(0, 1, 0.5), m1 = c(0.2, 0.8, 0.25),
    m2 = c(0.1, 0.6, 0.75), tests = c(1, 3, 2)
  )
  result <- compare_m1_m2(
    forecasts, "observed", "m1", "m2", "season", "origin", "target", "horizon",
    denominator_col = "tests"
  )
  expect_equal(result$forecast$weighting, "denominator")
  expect_equal(result$forecast$total_denominator, 6)
  expect_equal(result$forecast$overall$pooled$m1_mae, (1 * .2 + 3 * .2 + 2 * .25) / 6)
  expect_equal(result$forecast$overall$equal_season$m1_mae, mean(c(.2, .25)))
  expect_equal(result$forecast$by_season$m2_loses_mae, c(TRUE, FALSE))
})

test_that("comparison exposes only forecast inputs and rejects malformed inputs", {
  valid <- data.frame(
    season = "A", origin = 1L, target = 2L, horizon = 1L,
    observed = 0.5, m1 = 0.5, m2 = 0.5
  )
  expect_false(any(grepl("peak|direction", names(formals(compare_m1_m2)), ignore.case = TRUE)))
  result <- compare_m1_m2(
    valid, "observed", "m1", "m2", "season", "origin", "target", "horizon"
  )
  expect_false(any(grepl("peak", names(result), ignore.case = TRUE)))
  expect_error(
    compare_m1_m2(valid, "observed", "m1", "m2", "season", "origin", "target", "horizon", tolerance = -1),
    "tolerance"
  )
  valid$m2 <- 1.1
  expect_error(
    compare_m1_m2(valid, "observed", "m1", "m2", "season", "origin", "target", "horizon"),
    "probabilities"
  )
})
