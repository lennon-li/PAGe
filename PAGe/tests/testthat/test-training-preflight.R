test_that("preflight audit passes valid M0 grid", {
  data <- data.frame(
    season = rep(c("a", "b"), each = 30),
    weekF = rep(1:30, 2),
    p_cls_p = 0.2, p = 0.1, y = 1, N = 10
  )
  grid <- data.frame(
    cls_thr = 0.26, p_thr = 0.005, prev_thr = 0.001,
    n_consec = 5L, L = 2L, eps = 0, K_sum = 5L,
    p_sum_thr = 0.06, N_req = 4L, w_min = 13L, w_max = 26L
  )
  audit <- PAGe::preflight_support_audit(data, m0_grid = grid)
  expect_s3_class(audit, "page_preflight_audit")
  expect_true(audit$m0$valid)
  expect_length(audit$m0$issues, 0)
})

test_that("preflight audit fails unsupported M0 grid", {
  data <- data.frame(
    season = rep(c("a", "b"), each = 4),
    weekF = rep(1:4, 2),
    p_cls_p = 0.2, p = 0.1, y = 1, N = 10
  )
  grid <- data.frame(
    cls_thr = 0.26, p_thr = 0.005, prev_thr = 0.001,
    n_consec = 5L, L = 2L, eps = 0, K_sum = 6L,
    p_sum_thr = 0.06, N_req = 4L, w_min = 1L, w_max = 4L
  )
  audit <- PAGe::preflight_support_audit(data, m0_grid = grid)
  expect_false(audit$m0$valid)
  expect_length(audit$m0$issues, 1)
  expect_true(grepl("shortest training season", audit$m0$issues[1]))
  expect_length(audit$m0$remediation, 1)
})

test_that("preflight audit passes valid M1 grid", {
  grid <- data.frame(
    k_ref = c(20L, 25L, 30L),
    slope_weight = c(8, 12, 16),
    slope_window = 6L
  )
  audit <- PAGe::preflight_support_audit(
    data.frame(season = "a", weekF = 1L),
    m1_grid = grid
  )
  expect_true(audit$m1$valid)
})

test_that("preflight audit fails unsupported M1 grid", {
  grid <- data.frame(
    k_ref = c(20L, 60L),
    slope_weight = c(8, 12),
    slope_window = 6L
  )
  audit <- PAGe::preflight_support_audit(
    data.frame(season = "a", weekF = 1L),
    m1_grid = grid, n_weeks = 52L
  )
  expect_false(audit$m1$valid)
  expect_true(grepl("unsupported value", audit$m1$issues[1]))
})

test_that("preflight audit passes valid M2 grid", {
  data <- data.frame(
    season = rep("a", 20),
    weekF = rep(1:20, each = 1),
    y = 1, N = 100,
    post_ign = TRUE,
    lead = factor("h1", levels = c("h1", "h2")),
    logit_f_eff = rnorm(20),
    z_ema = rnorm(20),
    newWeek = 1:20,
    z_resid = rnorm(20),
    logN_now = rnorm(20),
    dz_ema = rnorm(20),
    logit_spread = abs(rnorm(20))
  )
  grid <- data.frame(
    delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
    alpha_state = 0.2, k_r = 0L, k_de = 0L, k_sp = 4L,
    bias_alpha = 0.05, bias_beta = 0
  )
  audit <- PAGe::preflight_support_audit(data, m2_grid = grid)
  expect_true(audit$m2$valid)
})

test_that("preflight audit fails unsupported M2 grid", {
  data <- data.frame(
    season = rep("a", 6),
    post_ign = TRUE,
    lead = factor(rep(c("h1", "h2"), each = 3), levels = c("h1", "h2")),
    logit_f_eff = rep(c(-1, 0, 1), 2),
    z_ema = rep(c(-0.5, 0, 0.5), 2),
    stringsAsFactors = FALSE
  )
  grid <- data.frame(
    delta = 0L, Kr = 1L, k_f = 4L, k_e = 0L,
    alpha_state = 0.2, k_r = 0L, k_de = 0L, k_sp = 0L,
    bias_alpha = 0.05, bias_beta = 0
  )
  audit <- PAGe::preflight_support_audit(data, m2_grid = grid)
  expect_false(audit$m2$valid)
  expect_true(grepl("exceed data support", audit$m2$issues[1]))
})

test_that("preflight audit fails on malformed input", {
  expect_error(
    PAGe::preflight_support_audit("not a data frame", m0_grid = data.frame()),
    "must be a data frame"
  )
  expect_error(
    PAGe::preflight_support_audit(data.frame(season = "a"), m0_grid = "not a grid"),
    "must be a data frame"
  )
  expect_error(
    PAGe::preflight_support_audit(data.frame(season = "a")),
    "must be supplied"
  )
})

test_that("preflight audit covers multiple stages", {
  data <- data.frame(
    season = rep(c("a", "b"), each = 30),
    weekF = rep(1:30, 2),
    p_cls_p = 0.2, p = 0.1, y = 1, N = 10
  )
  m0_grid <- data.frame(
    cls_thr = 0.26, p_thr = 0.005, prev_thr = 0.001,
    n_consec = 5L, L = 2L, eps = 0, K_sum = 5L,
    p_sum_thr = 0.06, N_req = 4L, w_min = 13L, w_max = 26L
  )
  m1_grid <- data.frame(k_ref = 25L, slope_weight = 8, slope_window = 6L)
  audit <- PAGe::preflight_support_audit(data, m0_grid = m0_grid, m1_grid = m1_grid)
  expect_true("m0" %in% names(audit))
  expect_true("m1" %in% names(audit))
  expect_true(audit$m0$valid)
  expect_true(audit$m1$valid)
})

test_that(".normalize_m1_hard_caps accepts NULL", {
  expect_null(PAGe:::.normalize_m1_hard_caps(NULL))
})

test_that(".normalize_m1_hard_caps normalizes named numeric vector", {
  caps <- PAGe:::.normalize_m1_hard_caps(c(k_ref = 50))
  expect_true(is.list(caps))
  expect_equal(names(caps), "k_ref")
  expect_true(is.na(caps$k_ref[["lower"]]))
  expect_equal(caps$k_ref[["upper"]], 50)
})

test_that(".normalize_m1_hard_caps normalizes named list with bounds", {
  caps <- PAGe:::.normalize_m1_hard_caps(
    list(k_ref = c(lower = 10L, upper = 50L))
  )
  expect_equal(caps$k_ref[["lower"]], 10)
  expect_equal(caps$k_ref[["upper"]], 50)
})

test_that(".normalize_m1_hard_caps rejects invalid input", {
  expect_error(
    PAGe:::.normalize_m1_hard_caps("invalid"),
    "must be NULL"
  )
  expect_error(
    PAGe:::.normalize_m1_hard_caps(c(50)),
    "must be named"
  )
  expect_error(
    PAGe:::.normalize_m1_hard_caps(list(k_ref = c(lower = 50, upper = 10))),
    "must not exceed"
  )
})

test_that(".normalize_m1_hard_caps handles scalar list entries", {
  caps <- PAGe:::.normalize_m1_hard_caps(list(k_ref = 50))
  expect_true(is.na(caps$k_ref[["lower"]]))
  expect_equal(caps$k_ref[["upper"]], 50)
})
