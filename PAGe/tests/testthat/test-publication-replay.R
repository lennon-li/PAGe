test_that("raw GAM predictor survives correction, capping and post-peak substitution", {
  d <- data.frame(
    y = c(2, 3, 5, 7, 8, 10, 12, 14), N = 20,
    lead = factor(rep(c("h1", "h2"), 4)),
    season = factor(rep(c("a", "b"), each = 4)),
    logit_f_eff = seq(-2, 1.5, .5)
  )
  fit <- stats::glm(cbind(y, N - y) ~ lead + season + logit_f_eff,
    data = d, family = stats::binomial())
  args <- list(fit = fit, ew = 10, h = 1, iWeek = 8,
    anchorWeek = 20, logit_f_eff = -1, z_ema = -1, logN_now = log(20),
    bias_logit = 2, soft_cap_fn = function(p) pmin(p, .1))
  expected <- unname(stats::predict(fit, data.frame(
    lead = factor("h1", levels = levels(d$lead)),
    season = factor("a", levels = levels(d$season)), logit_f_eff = -1), type = "link"))
  for (ci in c(FALSE, TRUE)) {
    pr <- do.call(PAGe:::m2_predict_one, c(args, list(return_ci = ci)))
    expect_equal(pr$m2_eta_raw, expected)
    expect_lte(pr$m2_p, .1)
    pr$m2_p <- .7 # post-peak trajectory substitution
    entry <- PAGe:::.m2_prediction_log(pr, 11, 1)
    expect_equal(entry$m2_eta_raw, expected)
    expect_equal(entry$m2_p, .7)
  }
})

test_that("replay retains bounds, stages, missing targets and failed predictions", {
  d <- data.frame(season = "2025-26", weekF = 1:3, y = c(10, 20, 30), N = 100)
  runner <- function(...) list(
    m2_preds = data.frame(eval_week = c(1, 2, 3), h = 1,
      target_weekF = 2:4, m2_p = c(.2, NA, .4),
      m2_lo = c(.1, NA, .3), m2_hi = c(.3, NA, .5)),
    ign_out = list(ign_week_locked = 1L),
    params_df = data.frame(eval_week = 1:3, peak_weekF = c(3, 3, 3)),
    m1_curves = data.frame(newWeek = 1:3, p_hat = c(.1, .2, .3)))
  out <- PAGe::replay_season_holdout(
    list(m2_production = list(training_seasons = "2024-25")), d, runner = runner)
  expect_equal(out$predictions$p_lo, .1)
  expect_equal(out$predictions$p_hi, .3)
  expect_equal(nrow(out$forecast_ledger), 6)
  expect_true(all(c("scored", "prediction_failed", "target_unavailable", "not_emitted") %in%
    out$forecast_ledger$forecast_status))
  expect_equal(out$stages$m1_parameters$peak_weekF, rep(3, 3))
  expect_equal(nrow(out$stages$m2_predictions), 3)
  expect_identical(out$diagnostics$overall$interval_status, "ok")
})

test_that("no-ignition replay is retained as an explicit failure", {
  d <- data.frame(season = "2025-26", weekF = 1:3, y = 0, N = 100)
  runner <- function(...) list(m2_preds = data.frame(),
    ign_out = list(ign_week_locked = NA_integer_))
  out <- PAGe::replay_season_holdout(
    list(m2_production = list(training_seasons = "2024-25")), d, runner = runner)
  expect_identical(out$status, "unseen_replay_failed")
  expect_identical(out$failure_code, "ignition_unavailable")
  expect_null(out$metrics)
  expect_equal(nrow(out$forecast_ledger), 6)
})

test_that("alignment failures preserve their origin and reason", {
  testthat::local_mocked_bindings(run_alignment_prospective_multi = function(...) {
    stop("alignment solver failed")
  }, .package = "PAGe")
  out <- PAGe::run_m1_alignment(list(M1_PARAMS = list()),
    data.frame(weekF = 1:3),
    list(iWeek_locked = 1L, ign_out = list(ign_week_locked = 1L)),
    walk_start = 1L, verbose = FALSE)
  expect_equal(out$params_df$eval_week, 1:3)
  expect_true(all(out$params_df$state == "alignment_failed"))
  expect_true(all(out$params_df$fallback == "alignment solver failed"))
})
