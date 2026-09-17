baseline_calendar_gam <- PAGe:::baseline_calendar_gam

cal_gam_fixture <- function(weeks = 1:30) {
  seasons <- c("s1", "s2", "s3", "t")
  data <- expand.grid(
    season = seasons, weekF = weeks,
    stringsAsFactors = FALSE
  )
  data <- data[order(data$season, data$weekF), , drop = FALSE]
  rownames(data) <- NULL
  shape <- exp(-0.5 * ((data$weekF - 18) / 4)^2)
  data$N <- 300L
  data$y <- as.integer(round(data$N * (0.05 + 0.45 * shape)))
  data
}

cal_gam_origin <- function(data, origin, horizons = 1:2) {
  baseline_calendar_gam(
    data, "t", c("s1", "s2", "s3"),
    origins = origin, horizons = horizons
  )
}

cal_gam_schema <- c(
  "season", "origin", "target", "horizon", "outcome", "prediction",
  "t_since_target", "N_lead", "model"
)

test_that("calendar GAM returns the expected outer prediction schema", {
  data <- cal_gam_fixture()
  out <- baseline_calendar_gam(
    data, "t", c("s1", "s2", "s3"),
    origins = c(12, 20), horizons = 1:2
  )
  expect_identical(names(out), cal_gam_schema)
  expect_identical(out$season, rep("t", 4L))
  expect_identical(out$model, rep("calendar_gam", 4L))
  expect_identical(out$horizon, c(1, 2, 1, 2))
  expect_identical(out$origin, c(12, 12, 20, 20))
  expect_identical(out$target, c(13, 14, 21, 22))
  expect_true(all(is.na(out$t_since_target)))
  expect_true(all(is.finite(out$prediction)))
  expect_true(all(out$prediction >= 1e-6 & out$prediction <= 1 - 1e-6))
  rows <- data[data$season == "t", , drop = FALSE]
  expect_equal(out$outcome, rows$y[match(out$target, rows$weekF)] /
    rows$N[match(out$target, rows$weekF)])
  expect_equal(out$N_lead, rows$N[match(out$target, rows$weekF)])
})

test_that("calendar GAM predictions ignore observations after the origin", {
  data <- cal_gam_fixture()
  for (origin in c(12, 20)) {
    base <- cal_gam_origin(data, origin)
    mutated <- data
    later <- mutated$season == "t" & mutated$weekF > origin
    mutated$y[later] <- 0L
    mutated$N[later] <- 999L
    after <- cal_gam_origin(mutated, origin)
    expect_identical(base$prediction, after$prediction)
  }
})

test_that("calendar GAM never trains on the target season", {
  data <- cal_gam_fixture()
  expect_error(
    baseline_calendar_gam(data, "t", c("s1", "t"), origins = 12),
    "must not appear"
  )
  expect_error(
    baseline_calendar_gam(data, "t", "unknown", origins = 12),
    "absent"
  )
  base <- cal_gam_origin(data, 12)
  mutated <- data
  future_targets <- mutated$season == "t" & mutated$weekF > 12
  mutated$y[future_targets] <- 250L
  expect_identical(cal_gam_origin(mutated, 12)$prediction, base$prediction)
})

test_that("calendar GAM outcome lookup follows the requested horizons", {
  data <- cal_gam_fixture()
  h1 <- baseline_calendar_gam(
    data, "t", c("s1", "s2", "s3"),
    origins = 12, horizons = 1
  )
  expect_identical(h1$horizon, 1)
  expect_identical(h1$target, 13)
  h2 <- baseline_calendar_gam(
    data, "t", c("s1", "s2", "s3"),
    origins = 12, horizons = 2
  )
  expect_identical(h2$horizon, 2)
  expect_identical(h2$target, 14)
  full <- cal_gam_origin(data, 12)
  expect_identical(full$horizon, c(1, 2))
  # These are three independently-fit GAMs (separate baseline_calendar_gam()
  # calls), not the same fit reused -- IRLS convergence can land a few ULPs
  # apart across platforms/BLAS even for the same inputs, so compare the
  # predictions with a tolerance rather than exact bitwise identity.
  expect_equal(full$prediction[1], h1$prediction, tolerance = 1e-8)
  expect_equal(full$prediction[2], h2$prediction, tolerance = 1e-8)
})

test_that("calendar GAM is deterministic", {
  data <- cal_gam_fixture()
  first <- cal_gam_origin(data, c(12, 20))
  second <- cal_gam_origin(data, c(12, 20))
  expect_identical(first, second)
  tuned <- baseline_calendar_gam(
    data, "t", c("s1", "s2", "s3"),
    origins = c(12, 20), k_week = 6L, k_signal = 4L
  )
  expect_identical(
    tuned,
    baseline_calendar_gam(
      data, "t", c("s1", "s2", "s3"),
      origins = c(12, 20), k_week = 6L, k_signal = 4L
    )
  )
})

test_that("calendar GAM marks unobserved origins and lags as missing", {
  data <- cal_gam_fixture()
  gapped <- data[!(data$season == "t" & data$weekF == 15L), , drop = FALSE]
  out <- baseline_calendar_gam(
    gapped, "t", c("s1", "s2", "s3"),
    origins = c(15, 16), horizons = 1:2
  )
  expect_true(all(is.na(out$prediction[out$origin == 15])))
  expect_true(all(is.na(out$prediction[out$origin == 16])))
  intact <- baseline_calendar_gam(
    gapped, "t", c("s1", "s2", "s3"),
    origins = 12, horizons = 1:2
  )
  expect_true(all(is.finite(intact$prediction)))
})

test_that("calendar GAM reports missing targets without dropping rows", {
  data <- cal_gam_fixture()
  out <- baseline_calendar_gam(
    data, "t", c("s1", "s2", "s3"),
    origins = 29, horizons = 2
  )
  expect_identical(out$target, 31)
  expect_true(is.na(out$outcome))
  expect_true(is.na(out$N_lead))
  expect_true(is.finite(out$prediction))
})

test_that("calendar GAM validates its inputs", {
  data <- cal_gam_fixture()
  expect_error(
    baseline_calendar_gam(1:3, "t", "s1", origins = 1),
    "data frame"
  )
  expect_error(
    baseline_calendar_gam(data, "t", character(0), origins = 1),
    "train_seasons"
  )
  expect_error(
    baseline_calendar_gam(data, "missing", "s1", origins = 1),
    "absent"
  )
  expect_error(
    baseline_calendar_gam(data, "t", "s1", origins = 1, horizons = 3),
    "subset"
  )
  expect_error(
    baseline_calendar_gam(data, "t", "s1", origins = 0),
    "positive"
  )
  expect_error(
    baseline_calendar_gam(data, "t", "s1", origins = 1, k_week = 0),
    "positive"
  )
})
