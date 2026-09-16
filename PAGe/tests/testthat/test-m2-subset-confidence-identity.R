testthat::test_that("unit confidence scale makes peak_ci exactly equivalent to none", {
  testthat::skip_if_not_installed("mgcv")
  set.seed(572)
  d <- expand.grid(
    row = 1:50, lead = factor(c("h1", "h2")),
    season = c("A", "B", "C")
  )
  d$z <- stats::rnorm(nrow(d))
  d$u <- stats::runif(nrow(d), 0, 30)
  d$d <- stats::rnorm(nrow(d))
  d$m1_logit <- stats::qlogis(0.2)
  d$N_lead <- 100
  d$y_lead <- stats::rbinom(
    nrow(d), 100, stats::plogis(d$m1_logit + 0.4 * sin(d$z) + 0.05 * d$u)
  )
  # Every row shares the median width, so c = 1 identically.
  d$peak_ci_width <- 4
  specs <- list(
    PAGe:::m2_subset_spec(intercept = TRUE, k_z = 5),
    PAGe:::m2_subset_spec(intercept = FALSE, k_u = 4),
    PAGe:::m2_subset_spec(intercept = TRUE, k_z = 4, k_u = 5, k_d = 3)
  )
  for (spec in specs) {
    none <- PAGe:::m2_subset_fit(d, spec, gamma = 1.4)
    ci_spec <- spec
    ci_spec$conf_scale <- "peak_ci"
    ci <- PAGe:::m2_subset_fit(d, ci_spec, gamma = 1.4)
    pred_none <- PAGe:::m2_subset_predict(none, d)
    pred_ci <- PAGe:::m2_subset_predict(ci, d)
    testthat::expect_equal(stats::coef(ci$fit), stats::coef(none$fit), tolerance = 0)
    testthat::expect_equal(pred_ci$p_hat, pred_none$p_hat, tolerance = 0)
    testthat::expect_equal(pred_ci$eta, pred_none$eta, tolerance = 0)
    testthat::expect_true(all(pred_ci$confidence_scale == 1))
  }
})

testthat::test_that("fitted method and gamma are the governed values actually used", {
  testthat::skip_if_not_installed("mgcv")
  set.seed(123)
  d <- expand.grid(week = 1:30, h = 1:2, season = c("A", "B", "C"))
  d$lead <- factor(paste0("h", d$h))
  d$z <- stats::rnorm(nrow(d))
  d$u <- stats::runif(nrow(d), 0, 20)
  d$d <- stats::rnorm(nrow(d))
  d$m1_logit <- stats::qlogis(0.15)
  d$N_lead <- 100
  d$y_lead <- stats::rbinom(
    nrow(d), 100, stats::plogis(d$m1_logit + 0.3 * sin(d$z))
  )
  d$peak_ci_width <- rep(c(1, 4, 8), length.out = nrow(d))
  spec <- PAGe:::m2_subset_spec(intercept = TRUE, k_z = 5)
  for (mode in c("none", "peak_ci")) {
    s <- spec
    s$conf_scale <- mode
    fit14 <- PAGe:::m2_subset_fit(d, s, gamma = 1.4)
    fit9 <- PAGe:::m2_subset_fit(d, s, gamma = 9)
    testthat::expect_equal(fit14$method, "REML")
    testthat::expect_equal(fit14$gamma, 1.4)
    testthat::expect_equal(as.character(fit14$fit$method), "REML")
    testthat::expect_false(identical(
      stats::coef(fit14$fit), stats::coef(fit9$fit)
    ))
  }
})

testthat::test_that("a silent mgcv method switch is rejected", {
  testthat::expect_error(
    PAGe:::.m2_subset_check_fit_method(list(method = "UBRE"), "REML"),
    "silently used method"
  )
  testthat::expect_silent(
    PAGe:::.m2_subset_check_fit_method(list(method = "REML"), "REML")
  )
})

testthat::test_that("varying confidence scale still changes the peak_ci fit", {
  testthat::skip_if_not_installed("mgcv")
  set.seed(20260908)
  d <- expand.grid(week = 1:30, h = 1:2, season = c("A", "B", "C"))
  d$lead <- factor(paste0("h", d$h))
  d$z <- stats::rnorm(nrow(d))
  d$u <- stats::runif(nrow(d), 0, 20)
  d$d <- stats::rnorm(nrow(d))
  d$m1_logit <- stats::qlogis(0.15)
  d$N_lead <- 100
  d$y_lead <- stats::rbinom(
    nrow(d), 100, stats::plogis(d$m1_logit + 0.4 * sin(d$z))
  )
  d$peak_ci_width <- rep(c(0, 1, 4, 8, NA), length.out = nrow(d))
  spec <- PAGe:::m2_subset_spec(intercept = TRUE, k_z = 5)
  none <- PAGe:::m2_subset_fit(d, spec)
  ci_spec <- spec
  ci_spec$conf_scale <- "peak_ci"
  ci <- PAGe:::m2_subset_fit(d, ci_spec)
  testthat::expect_gt(
    max(abs(stats::coef(none$fit) - stats::coef(ci$fit))), 1e-6
  )
  testthat::expect_gt(
    max(abs(
      PAGe:::m2_subset_predict(none, d)$correction_logit -
        PAGe:::m2_subset_predict(ci, d)$correction_logit
    )),
    1e-6
  )
})
