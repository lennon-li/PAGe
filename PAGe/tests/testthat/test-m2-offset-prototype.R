test_that("offset formula keeps M1 as a true formula offset", {
  formula <- PAGe:::m2_offset_formula(k_z = 3L, k_sp = 0L)
  text <- paste(deparse(formula), collapse = " ")
  expect_match(text, "offset\\(logit_f_eff\\)")
  expect_match(text, "s\\(z_ema")
  expect_false(grepl("s\\(logit_f_eff", text))
})

test_that("zero correction returns the M1 baseline exactly", {
  newdata <- data.frame(
    logit_f_eff = c(-4, -1, 0.5, 3),
    lead = factor(c("h1", "h2", "h1", "h2"))
  )
  expect_equal(PAGe:::m2_offset_baseline(newdata), stats::plogis(newdata$logit_f_eff))
})

test_that("penalized intercepts can shrink the fitted correction to zero", {
  d <- data.frame(
    lead = factor(rep(c("h1", "h2"), each = 30)),
    logit_f_eff = -1, z_ema = seq(-3, 1, length.out = 60),
    N_lead = 100L, y_lead = 50L
  )
  fit <- PAGe:::fit_m2_offset_correction(d,
    k_z = 0,
    penalize_intercepts = TRUE, intercept_sp = 1e12
  )
  pred <- PAGe:::predict_m2_offset_correction(fit, d)
  expect_lt(max(abs(pred$correction_logit)), 1e-7)
  expect_equal(pred$p_hat, plogis(d$logit_f_eff), tolerance = 1e-7)
})

test_that("unseen horizons and nonfinite prediction offsets fail explicitly", {
  d <- data.frame(
    lead = factor(rep(c("h1", "h2"), each = 30)),
    logit_f_eff = -1, z_ema = seq(-3, 1, length.out = 60),
    N_lead = 100L, y_lead = 30L
  )
  fit <- PAGe:::fit_m2_offset_correction(d, k_z = 0)
  nd <- d[1, ]
  nd$lead <- "h3"
  expect_error(PAGe:::predict_m2_offset_correction(fit, nd), "horizon")
  nd <- d[1, ]
  nd$logit_f_eff <- Inf
  expect_error(PAGe:::predict_m2_offset_correction(fit, nd), "finite")
})

test_that("known positive and negative corrections are recovered without an M1 coefficient", {
  set.seed(20260908)
  n <- 5000L
  d <- data.frame(
    lead = factor(rep(c("h1", "h2"), length.out = n)),
    logit_f_eff = stats::runif(n, -3, 1),
    z_ema = stats::runif(n, -3, 1),
    N_lead = 250L
  )
  d$y_lead <- stats::rbinom(
    n, d$N_lead,
    stats::plogis(d$logit_f_eff + ifelse(d$lead == "h1", 0.45, -0.35))
  )
  out <- PAGe:::fit_m2_offset_correction(d, k_z = 0L)
  pred <- PAGe:::predict_m2_offset_correction(out, d)
  recovered <- tapply(pred$correction_logit, d$lead, median)

  expect_true(out$converged)
  expect_lt(max(abs(recovered[c("h1", "h2")] - c(h1 = 0.45, h2 = -0.35))), 0.08)
  expect_false(any(grepl("logit_f_eff", names(stats::coef(out$fit)), fixed = TRUE)))
  expect_equal(pred$m1_p, PAGe:::m2_offset_baseline(d), tolerance = 1e-12)
})

test_that("season balancing equalizes trial mass and validates response boundaries", {
  d <- data.frame(
    season = rep(c("early", "late"), each = 4),
    lead = factor(rep(c("h1", "h2"), 4)),
    logit_f_eff = -1,
    z_ema = seq(-2, 1, length.out = 8),
    N_lead = c(rep(10, 4), rep(100, 4)),
    y_lead = c(2, 3, 4, 5, 20, 30, 40, 50)
  )
  fit <- PAGe:::fit_m2_offset_correction(d, k_z = 0, season_balance = TRUE)
  weighted_trials <- fit$season_trial_totals * fit$fit_weight_by_season

  expect_true(fit$season_balance)
  expect_equal(as.numeric(fit$season_trial_totals), c(40, 400))
  expect_equal(as.numeric(weighted_trials), rep(mean(fit$season_trial_totals), 2))
  expect_error(
    PAGe:::fit_m2_offset_correction(transform(d, y_lead = N_lead + 1), k_z = 0),
    "Invalid binomial response"
  )
  expect_error(PAGe:::fit_m2_offset_correction(d, k_z = -1), "non-negative")
})

test_that("prediction is prefix-safe and ignores future outcome columns", {
  d <- data.frame(
    lead = factor(rep(c("h1", "h2"), each = 20)),
    logit_f_eff = seq(-2, 0, length.out = 40),
    z_ema = seq(-2, 1, length.out = 40),
    N_lead = 100L,
    y_lead = 50L
  )
  fit <- PAGe:::fit_m2_offset_correction(d, k_z = 3)
  prefix <- d[1:8, c("lead", "logit_f_eff", "z_ema")]
  with_outcomes <- transform(prefix, y_lead = 0, N_lead = 1e9)

  expect_equal(
    PAGe:::predict_m2_offset_correction(fit, prefix)$p_hat,
    PAGe:::predict_m2_offset_correction(fit, with_outcomes)$p_hat,
    tolerance = 1e-12
  )
})
