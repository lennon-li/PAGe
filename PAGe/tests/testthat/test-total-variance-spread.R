test_that("m1_make_params carries spread_method in configuration", {
  expect_identical(PAGe:::.default_m1_params()$spread_method, "between")

  params_default <- PAGe::m1_make_params()
  expect_identical(params_default$spread_method, "between")

  params_total <- PAGe::m1_make_params(spread_method = "total")
  expect_identical(params_total$spread_method, "total")
})

test_that(".canonical_m1_params preserves supplied spread_method", {
  params <- PAGe::m1_make_params(spread_method = "total")
  canonical <- PAGe:::.canonical_m1_params(params)
  expect_identical(canonical$spread_method, "total")

  params_between <- PAGe::m1_make_params(spread_method = "between")
  canonical_between <- PAGe:::.canonical_m1_params(params_between)
  expect_identical(canonical_between$spread_method, "between")
})

test_that("m1_make_params rejects invalid spread_method", {
  expect_error(PAGe::m1_make_params(spread_method = "invalid"))
})

test_that("between mode preserves the existing weighted-SD result", {
  logit_mat <- matrix(c(-2, -1, 0, 1, 2, 1.5), nrow = 3, ncol = 2)
  wts <- c(0.6, 0.4)

  res_between <- PAGe:::.compute_logit_spread(
    logit_mat, wts,
    se_mat = NULL, spread_method = "between"
  )

  expected <- vapply(seq_len(nrow(logit_mat)), function(i) {
    lv <- logit_mat[i, ]
    mu <- sum(wts * lv)
    sqrt(sum(wts * (lv - mu)^2))
  }, numeric(1))

  expect_equal(res_between$spread, expected)
  expect_identical(res_between$fallback_count, 0L)
})

test_that("one-template total spread equals its SE", {
  se_vals <- c(0.3, 0.5, 0.7)
  logit_mat <- matrix(c(-1, 0, 1), nrow = 3, ncol = 1)
  wts <- 1
  se_mat <- matrix(se_vals, nrow = 3, ncol = 1)

  res_total <- PAGe:::.compute_logit_spread(
    logit_mat, wts,
    se_mat = se_mat, spread_method = "total"
  )

  expect_equal(res_total$spread, se_vals)
  expect_identical(res_total$fallback_count, 0L)
})

test_that("total spread adds weighted within-template SE^2 to between variance", {
  logit_mat <- matrix(c(-2, 0, 2, -1, 1, 3), nrow = 3, ncol = 2)
  wts <- c(0.7, 0.3)
  se_mat <- matrix(c(0.4, 0.6, 0.2, 0.5, 0.1, 0.8), nrow = 3, ncol = 2)

  res_between <- PAGe:::.compute_logit_spread(
    logit_mat, wts,
    se_mat = NULL, spread_method = "between"
  )
  res_total <- PAGe:::.compute_logit_spread(
    logit_mat, wts,
    se_mat = se_mat, spread_method = "total"
  )

  for (i in seq_len(nrow(logit_mat))) {
    lv <- logit_mat[i, ]
    mu <- sum(wts * lv)
    between_var <- sum(wts * (lv - mu)^2)
    within_var <- sum(wts * se_mat[i, ]^2)
    expected_total <- sqrt(between_var + within_var)
    expect_equal(res_total$spread[i], expected_total)
    expect_equal(res_between$spread[i], sqrt(between_var))
    expect_gt(res_total$spread[i], res_between$spread[i])
  }
  expect_identical(res_total$fallback_count, 0L)
})

test_that("total mode falls back to between-only when SEs are all zero", {
  logit_mat <- matrix(c(-2, 0, 2, -1, 1, 3), nrow = 3, ncol = 2)
  wts <- c(0.5, 0.5)
  se_mat_zero <- matrix(0, nrow = 3, ncol = 2)

  res <- PAGe:::.compute_logit_spread(
    logit_mat, wts,
    se_mat = se_mat_zero, spread_method = "total"
  )

  res_between <- PAGe:::.compute_logit_spread(
    logit_mat, wts,
    se_mat = NULL, spread_method = "between"
  )

  expect_equal(res$spread, res_between$spread)
  expect_identical(res$fallback_count, 3L)
})

test_that("total mode falls back per-week when SEs are partially missing", {
  logit_mat <- matrix(c(-1, 0, 1, 0.5, 1.5, 2.5), nrow = 3, ncol = 2)
  wts <- c(0.6, 0.4)
  se_mat <- matrix(c(0, 0, 0.4, 0, 0, 0.5), nrow = 3, ncol = 2)

  res <- PAGe:::.compute_logit_spread(
    logit_mat, wts,
    se_mat = se_mat, spread_method = "total"
  )

  res_between <- PAGe:::.compute_logit_spread(
    logit_mat, wts,
    se_mat = NULL, spread_method = "between"
  )

  expect_equal(res$spread[1], res_between$spread[1])
  expect_gt(res$spread[3], res_between$spread[3])
  expect_identical(res$fallback_count, 2L)
})

test_that(".compute_logit_spread handles empty forecast matrix", {
  logit_mat <- matrix(numeric(0), nrow = 0, ncol = 2)
  wts <- c(0.5, 0.5)

  res <- PAGe:::.compute_logit_spread(
    logit_mat, wts,
    se_mat = NULL, spread_method = "between"
  )
  expect_identical(res$spread, numeric(0))
  expect_identical(res$fallback_count, 0L)
})
