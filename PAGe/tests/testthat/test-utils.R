test_that("num_deriv approximates known derivatives", {
  # d/dx sin(x) = cos(x)
  expect_equal(PAGe:::num_deriv(0, sin), cos(0), tolerance = 1e-6)
  expect_equal(PAGe:::num_deriv(pi / 4, sin), cos(pi / 4), tolerance = 1e-6)
  # d/dx x^3 = 3x^2
  expect_equal(PAGe:::num_deriv(2, function(x) x^3), 12, tolerance = 1e-4)
})

test_that("logit clips to avoid +/-Inf at the boundary", {
  logit <- getFromNamespace("logit", "PAGe")
  expect_true(is.finite(logit(0)))
  expect_true(is.finite(logit(1)))
  # interior values match qlogis exactly
  expect_equal(logit(0.5), qlogis(0.5))
  expect_equal(logit(0.9), qlogis(0.9))
})

test_that("is_cov_ok accepts valid covariance matrices and rejects bad ones", {
  is_cov_ok <- getFromNamespace("is_cov_ok", "PAGe")
  expect_true(is_cov_ok(diag(2)))
  expect_true(is_cov_ok(matrix(c(1, 0.3, 0.3, 1), 2, 2)))
  expect_false(is_cov_ok(matrix(c(1, 2, 2, 1), 2, 2)))          # not PD
  expect_false(is_cov_ok(matrix(c(NA, 0, 0, 1), 2, 2)))          # non-finite
  expect_false(is_cov_ok(matrix(1:6, 2, 3)))                     # non-square
})

test_that("wilson_ci stays within [0,1] and contains the point estimate", {
  wilson_ci <- getFromNamespace("wilson_ci", "PAGe")
  ci <- wilson_ci(5, 20)
  expect_true(ci[, "lo"] >= 0 && ci[, "hi"] <= 1)
  expect_true(ci[, "lo"] <= 5 / 20 && ci[, "hi"] >= 5 / 20)
  # edge: 0 successes
  ci0 <- wilson_ci(0, 10)
  expect_equal(unname(ci0[, "lo"]), 0)
})

test_that("n_weeks_in_start_year returns 52 or 53", {
  n_weeks_in_start_year <- getFromNamespace("n_weeks_in_start_year", "PAGe")
  for (yr in 2010:2025) {
    n <- n_weeks_in_start_year(yr)
    expect_true(n %in% c(52L, 53L),
                info = sprintf("year %d returned %s", yr, n))
  }
})
