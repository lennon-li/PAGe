make_decision_forecasts <- function(m2 = c(.15, .15, .15, .15)) {
  data.frame(
    season = LETTERS[1:4], origin = 1L, target = 2L, horizon = 1L,
    observed = 0, m1 = .2, m2 = m2
  )
}

test_that("baseline decision adopts a clearly better M2 candidate", {
  result <- PAGe::decide_m2_vs_m1(
    make_decision_forecasts(), "observed", "m1", "m2",
    "season", "origin", "target", "horizon"
  )
  expect_equal(result$decision, "use_m2")
  expect_equal(result$reasons, character(0))
  expect_gt(result$overall$gain_nll, result$overall$required_gain)
  expect_equal(result$overall$n_seasons, 4L)
})

test_that("season uncertainty can reject a small apparent gain", {
  result <- PAGe::decide_m2_vs_m1(
    make_decision_forecasts(c(.18, .2, .2, .2)), "observed", "m1", "m2",
    "season", "origin", "target", "horizon"
  )
  expect_equal(result$decision, "keep_m1")
  expect_contains(result$reasons, "overall_minimum_gain_failed")
})

test_that("a historical season degradation triggers the M1 fallback", {
  result <- PAGe::decide_m2_vs_m1(
    make_decision_forecasts(c(.15, .15, .15, .3)), "observed", "m1", "m2",
    "season", "origin", "target", "horizon",
    min_gain = 0, confidence = .5
  )
  expect_equal(result$decision, "keep_m1")
  expect_contains(result$reasons, "season_degradation_limit_failed")
})

test_that("phase and denominator weighting are configurable", {
  forecasts <- rbind(
    data.frame(season = c("A", "B"), origin = 1L, target = 2L, horizon = 1L,
      observed = 0, m1 = .2, m2 = .15, phase = "early", tests = c(1, 10)),
    data.frame(season = c("A", "B"), origin = 2L, target = 3L, horizon = 1L,
      observed = 0, m1 = .2, m2 = .3, phase = "late", tests = c(10, 1))
  )
  result <- PAGe::decide_m2_vs_m1(
    forecasts, "observed", "m1", "m2", "season", "origin", "target", "horizon",
    phase_col = "phase", phase_weights = c(early = 2, late = 1),
    denominator_col = "tests", confidence = .5
  )
  expect_equal(result$rule$denominator_weighting, TRUE)
  expect_equal(nrow(result$matched), 4L)
  expect_true(is.character(result$decision))
})

test_that("t_since phase definitions are explicit and recorded", {
  forecasts <- make_decision_forecasts()
  forecasts$t_since <- c(-1, 0, 12, 13)
  expect_error(
    PAGe::decide_m2_vs_m1(
      forecasts, "observed", "m1", "m2", "season", "origin", "target", "horizon",
      t_since_col = "t_since"
    ),
    "phase_break"
  )
  result <- PAGe::decide_m2_vs_m1(
    forecasts, "observed", "m1", "m2", "season", "origin", "target", "horizon",
    t_since_col = "t_since", phase_break = 12,
    phase_weights = c(pre_ignition = 0, early = 2, late = 1), confidence = .5
  )
  expect_equal(result$rule$phase_source, "t_since_col")
  expect_equal(result$rule$phase_break, 12)
})
