baseline_persistence <- PAGe:::baseline_persistence
baseline_seasonal_mean <- PAGe:::baseline_seasonal_mean
simulate_flu_seasons <- PAGe::simulate_flu_seasons

baseline_fixture <- function(S = 3L, weeks = 1:52, seed = 2025) {
  raw <- simulate_flu_seasons(S = S, weeks = weeks, seed = seed)
  data <- data.frame(
    season = paste0("syn-", as.integer(raw$season)),
    weekF = as.integer(raw$newWeek),
    y = as.integer(raw$y),
    N = as.integer(raw$y + raw$neg),
    stringsAsFactors = FALSE
  )
  data <- data[order(data$season, data$weekF), , drop = FALSE]
  rownames(data) <- NULL
  data
}

baseline_small <- function() {
  data.frame(
    season = rep(c("s1", "s2", "t"), each = 6L),
    weekF = rep(1:6, times = 3L),
    y = c(
      1L, 2L, 3L, 4L, 5L, 6L,
      6L, 5L, 4L, 3L, 2L, 1L,
      0L, 0L, 0L, 0L, 0L, 0L
    ),
    N = rep(10L, 18L),
    stringsAsFactors = FALSE
  )
}

test_that("persistence returns the expected outer prediction schema", {
  out <- baseline_persistence(
    baseline_fixture(), "syn-1",
    origins = c(10, 20), horizons = 1:2
  )
  expect_identical(
    names(out),
    c(
      "season", "origin", "target", "horizon", "outcome", "prediction",
      "t_since_target", "N_lead", "model"
    )
  )
  expect_identical(out$season, rep("syn-1", 4L))
  expect_identical(out$model, rep("persistence", 4L))
  expect_identical(out$horizon, c(1, 2, 1, 2))
  expect_identical(out$origin, c(10, 10, 20, 20))
  expect_identical(out$target, c(11, 12, 21, 22))
  expect_true(all(is.na(out$t_since_target)))
})

test_that("persistence predictions use only observations at or before origin", {
  data <- baseline_fixture()
  for (origin in c(10, 20)) {
    base <- baseline_persistence(data, "syn-1", origins = origin, horizons = 1:2)
    mutated <- data
    later <- mutated$season == "syn-1" & mutated$weekF > origin
    mutated$y[later] <- 0L
    mutated$N[later] <- 50L
    after <- baseline_persistence(mutated, "syn-1", origins = origin, horizons = 1:2)
    expect_identical(base$prediction, after$prediction)
  }
})

test_that("persistence prediction equals the origin positivity", {
  data <- baseline_fixture()
  rows <- data[data$season == "syn-1", , drop = FALSE]
  out <- baseline_persistence(data, "syn-1", origins = 15, horizons = 1:2)
  expected <- rows$y[match(15, rows$weekF)] / rows$N[match(15, rows$weekF)]
  expect_equal(out$prediction, rep(expected, 2L))
})

test_that("persistence carries the last observation across a missing origin week", {
  data <- baseline_fixture()
  gapped <- data[!(data$season == "syn-1" & data$weekF == 15L), , drop = FALSE]
  out <- baseline_persistence(gapped, "syn-1", origins = 15, horizons = 1)
  rows <- gapped[gapped$season == "syn-1", , drop = FALSE]
  last <- max(rows$weekF[rows$weekF < 15])
  expected <- rows$y[match(last, rows$weekF)] / rows$N[match(last, rows$weekF)]
  expect_equal(out$prediction, expected)
})

test_that("persistence marks unobserved targets as missing", {
  data <- data.frame(season = "s", weekF = 1:3, y = c(1L, 2L, 3L), N = 10L)
  out <- baseline_persistence(data, "s", origins = 3, horizons = 1:2)
  expect_true(all(is.na(out$outcome)))
  expect_true(all(is.na(out$N_lead)))
  expect_equal(out$prediction, rep(3 / 10, 2L))
})

test_that("persistence records the observed target outcome and count", {
  data <- data.frame(season = "s", weekF = 1:4, y = c(1L, 2L, 6L, 4L), N = 10L)
  out <- baseline_persistence(data, "s", origins = 2, horizons = 1:2)
  expect_equal(out$outcome, c(6 / 10, 4 / 10))
  expect_equal(out$N_lead, c(10, 10))
})

test_that("baseline predictions are clamped away from the boundaries", {
  data <- data.frame(season = "s", weekF = 1:5, y = c(10L, 10L, 0L, 0L, 5L), N = 10L)
  out <- baseline_persistence(data, "s", origins = c(1, 3), horizons = 1)
  expect_equal(out$prediction, c(1 - 1e-6, 1e-6))
  expect_true(all(out$prediction >= 1e-6 & out$prediction <= 1 - 1e-6))
})

test_that("seasonal mean clamps saturated training weeks", {
  data <- data.frame(
    season = rep(c("s1", "t"), each = 2L),
    weekF = rep(1:2, times = 2L),
    y = c(10L, 10L, 10L, 10L),
    N = 10L
  )
  out <- baseline_seasonal_mean(data, "t", "s1", origins = 1, horizons = 1)
  expect_equal(out$prediction, 1 - 1e-6)
})

test_that("seasonal mean errors when the test season is in training", {
  expect_error(
    baseline_seasonal_mean(baseline_small(), "s1", c("s1", "s2"), origins = 2),
    "must not appear"
  )
})

test_that("calendar and ignition alignment give different training weeks", {
  data <- baseline_small()
  ign <- c(s1 = 3, s2 = 1, t = 2)
  cal <- baseline_seasonal_mean(
    data, "t", c("s1", "s2"),
    origins = 2, horizons = 2, align = "calendar", ignition = ign
  )
  aligned <- baseline_seasonal_mean(
    data, "t", c("s1", "s2"),
    origins = 2, horizons = 2, align = "ignition", ignition = ign
  )
  expect_equal(cal$prediction, 7 / 20)
  expect_equal(aligned$prediction, 9 / 20)
  expect_equal(cal$t_since_target, 2)
  expect_equal(aligned$t_since_target, 2)
})

test_that("seasonal mean uses test-count weighting across training seasons", {
  data <- data.frame(
    season = c("s1", "s1", "s2", "s2", "t"),
    weekF = c(1L, 2L, 1L, 2L, 1L),
    y = c(0L, 0L, 90L, 90L, 0L),
    N = c(10L, 10L, 100L, 100L, 10L)
  )
  out <- baseline_seasonal_mean(data, "t", c("s1", "s2"), origins = 1, horizons = 1)
  expect_equal(out$prediction, 90 / 110)
})

test_that("seasonal mean ignores the test season when predicting", {
  data <- baseline_small()
  base <- baseline_seasonal_mean(data, "t", c("s1", "s2"), origins = 2, horizons = 1)
  mutated <- data
  mutated$y[mutated$season == "t"] <- 9L
  after <- baseline_seasonal_mean(mutated, "t", c("s1", "s2"), origins = 2, horizons = 1)
  expect_equal(base$prediction, after$prediction)
  expect_false(isTRUE(all.equal(base$outcome, after$outcome)))
})

test_that("seasonal mean returns missing predictions when support is absent", {
  data <- data.frame(
    season = rep(c("s1", "t"), each = 3L),
    weekF = rep(1:3, times = 2L),
    y = c(1L, 2L, 3L, 0L, 0L, 0L),
    N = 10L
  )
  out <- baseline_seasonal_mean(data, "t", "s1", origins = 3, horizons = 1:2)
  expect_true(all(is.na(out$prediction)))
  expect_identical(out$model, rep("seasonal_mean", 2L))
})

test_that("seasonal mean reports t_since_target only when ignition is supplied", {
  data <- baseline_small()
  no_timing <- baseline_seasonal_mean(data, "t", "s1", origins = 2, horizons = 2)
  expect_true(all(is.na(no_timing$t_since_target)))
  timed <- baseline_seasonal_mean(
    data, "t", "s1",
    origins = 2, horizons = 2, ignition = c(s1 = 1, t = 2)
  )
  expect_equal(timed$t_since_target, 2)
})

test_that("seasonal mean validates alignment and ignition inputs", {
  data <- baseline_small()
  expect_error(
    baseline_seasonal_mean(
      data, "t", c("s1", "s2"),
      origins = 2, horizons = 2, align = "ignition"
    ),
    "requires a named"
  )
  expect_error(
    baseline_seasonal_mean(
      data, "t", c("s1", "s2"),
      origins = 2, horizons = 2, align = "ignition", ignition = c(s1 = 3, t = 2)
    ),
    "missing season"
  )
  expect_error(
    baseline_seasonal_mean(
      data, "t", "s1",
      origins = 2, horizons = 2, ignition = c(s1 = 3)
    ),
    "must name"
  )
})

test_that("baselines validate their inputs", {
  data <- baseline_small()
  expect_error(baseline_persistence(1:3, "s1", origins = 1), "data frame")
  expect_error(baseline_persistence(data, "missing", origins = 1), "absent")
  expect_error(baseline_persistence(data, c("s1", "s2"), origins = 1), "non-empty")
  expect_error(baseline_persistence(data, "s1", origins = 0), "positive")
  expect_error(baseline_persistence(data, "s1", origins = 1.5), "positive")
  expect_error(baseline_persistence(data, "s1", origins = 1, horizons = -1), "positive")
  expect_error(
    baseline_seasonal_mean(data, "s1", character(0), origins = 1),
    "train_seasons"
  )
  expect_error(
    baseline_seasonal_mean(data, "s1", "unknown", origins = 1),
    "absent"
  )
})
