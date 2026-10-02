test_that("shared-denominator correlation matches multinomial identity", {
  p <- c(A = 0.05, B = 0.02)
  R <- page_shared_denominator_correlation(p)
  expected <- -sqrt((p[["A"]] * p[["B"]]) /
                      ((1 - p[["A"]]) * (1 - p[["B"]])))
  expect_equal(R["A", "B"], expected, tolerance = 1e-14)
  expect_equal(unname(diag(R)), c(1, 1))
  expect_equal(rownames(R), c("A", "B"))
})

test_that("shared-denominator analytic aggregation reproduces correlated sum", {
  p <- c(A = 0.05, B = 0.02)
  se <- c(A = 0.004, B = 0.002)
  R <- page_shared_denominator_correlation(p)
  expected_se <- sqrt(se[[1]]^2 + se[[2]]^2 + 2 * R[1, 2] * se[[1]] * se[[2]])

  z <- page_aggregate_strata(
    estimate = p,
    se = se,
    method = "sum",
    dependence = "shared_denominator",
    bounds = c(0, 1)
  )

  expect_s3_class(z, "page_strata_aggregate")
  expect_equal(z$estimate, 0.07, tolerance = 1e-14)
  expect_equal(z$se, expected_se, tolerance = 1e-14)
  expect_lt(z$se, sqrt(sum(se^2)))
})

test_that("asymmetric component intervals remain asymmetric after aggregation", {
  p <- c(A = 0.05, B = 0.02)
  z <- page_aggregate_strata(
    estimate = p,
    lower = c(A = 0.043, B = 0.017),
    upper = c(A = 0.061, B = 0.026),
    method = "sum",
    dependence = "shared_denominator",
    bounds = c(0, 1)
  )
  expect_true(is.finite(z$lower))
  expect_true(is.finite(z$upper))
  expect_false(isTRUE(all.equal(z$estimate - z$lower, z$upper - z$estimate)))
})

test_that("independent age strata use normalized denominator weights", {
  p <- c(`0-17` = 0.10, `18-64` = 0.20, `65+` = 0.30)
  n <- c(`0-17` = 100, `18-64` = 300, `65+` = 100)
  se <- c(`0-17` = 0.01, `18-64` = 0.02, `65+` = 0.03)

  z <- page_aggregate_strata(
    estimate = p,
    se = se,
    method = "weighted_mean",
    weights = n,
    dependence = "independent",
    bounds = c(0, 1)
  )

  w <- n / sum(n)
  expect_equal(z$weights, w, tolerance = 1e-14)
  expect_equal(z$estimate, sum(w * p), tolerance = 1e-14)
  expect_equal(z$se, sqrt(sum((w * se)^2)), tolerance = 1e-14)
})

test_that("explicit correlation and covariance paths are equivalent", {
  p <- c(a = 0.10, b = 0.20, c = 0.15)
  se <- c(a = 0.01, b = 0.02, c = 0.015)
  R <- matrix(c(
    1, 0.25, -0.10,
    0.25, 1, 0.20,
    -0.10, 0.20, 1
  ), 3, 3, byrow = TRUE, dimnames = list(names(p), names(p)))
  Sigma <- diag(se) %*% R %*% diag(se)

  a <- page_aggregate_strata(
    p, se = se, method = "weighted_mean", weights = c(1, 2, 1),
    dependence = "correlation", correlation = R
  )
  b <- page_aggregate_strata(
    p, method = "weighted_mean", weights = c(1, 2, 1),
    dependence = "covariance", covariance = Sigma
  )

  expect_equal(a$estimate, b$estimate, tolerance = 1e-14)
  expect_equal(a$se, b$se, tolerance = 1e-14)
  expect_equal(a$lower, b$lower, tolerance = 1e-14)
  expect_equal(a$upper, b$upper, tolerance = 1e-14)
})

test_that("draw aggregation preserves joint dependence", {
  set.seed(12)
  n <- 20000
  z1 <- rnorm(n)
  z2 <- 0.6 * z1 + sqrt(1 - 0.6^2) * rnorm(n)
  draws <- cbind(A = 0.05 + 0.005 * z1, B = 0.02 + 0.003 * z2)

  out <- page_aggregate_strata_draws(
    draws,
    method = "sum",
    bounds = c(0, 1),
    keep_draws = TRUE
  )

  expect_s3_class(out, "page_strata_aggregate_draws")
  expect_equal(out$draws, rowSums(draws), tolerance = 1e-14)
  expect_equal(out$estimate, mean(rowSums(draws)), tolerance = 1e-14)
})

test_that("draw aggregation composes across age and virus axes", {
  set.seed(42)
  n <- 5000
  # Four jointly simulated components: A/B within two age groups.
  x <- matrix(rnorm(n * 4), ncol = 4)
  colnames(x) <- c("young_A", "young_B", "old_A", "old_B")
  x <- sweep(x, 2, c(0.04, 0.01, 0.08, 0.02), function(z, mu) mu + 0.002 * z)
  w <- c(young = 0.4, old = 0.6)

  # Virus first, then age.
  young_ab <- rowSums(x[, c("young_A", "young_B")])
  old_ab <- rowSums(x[, c("old_A", "old_B")])
  virus_then_age <- page_aggregate_strata_draws(
    cbind(young = young_ab, old = old_ab),
    method = "weighted_mean", weights = w, bounds = c(0, 1), keep_draws = TRUE
  )

  # Age first, then virus.
  all_a <- w[["young"]] * x[, "young_A"] + w[["old"]] * x[, "old_A"]
  all_b <- w[["young"]] * x[, "young_B"] + w[["old"]] * x[, "old_B"]
  age_then_virus <- page_aggregate_strata_draws(
    cbind(A = all_a, B = all_b),
    method = "sum", bounds = c(0, 1), keep_draws = TRUE
  )

  expect_equal(virus_then_age$draws, age_then_virus$draws, tolerance = 1e-14)
})

test_that("shared denominator rejects impossible multinomial partition", {
  expect_error(
    page_shared_denominator_correlation(c(A = 0.8, B = 0.5)),
    "sum\\(p\\) <= 1"
  )
})
