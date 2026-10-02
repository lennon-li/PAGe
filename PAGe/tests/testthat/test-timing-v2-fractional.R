test_that("timing-v2 exposes midpoint ignition and explicit peak truth", {
  labels <- PAGe:::validate_timing_labels(
    season = "demo", ignition = c(18L, 19L), peak = c(27L, 28L),
    peak_observed = 27L
  )
  targets <- PAGe::as_timing_targets_v2(labels)

  expect_equal(targets$ignition_target_weekF, 18.5)
  expect_equal(targets$peak_observed_weekF, 27)
  expect_equal(targets$peak_second_weekF, 28)
  expect_equal(targets$peak_target_weekF, 27)
})

test_that("timing-v2 application propagates decimal ignition coordinates", {
  raw <- data.frame(
    season = "demo", weekF = 1:4, y = 1:4, N = rep(10L, 4)
  )
  review <- PAGe::review_season_timing_v2(raw)
  labels <- PAGe::finalize_season_timing_v2(
    review, ignition = c(2L, 3L), peak = c(3L, 4L), n_weeks = 4L
  )
  out <- PAGe::apply_timing_labels_v2(raw, labels, anchor_week = 2.5)

  expect_equal(unique(out$iWeekF), 2.5)
  expect_type(out$newWeek, "double")
  expect_equal(out$peak_weekF, rep(4, 4))
  expect_equal(out$peak_second_weekF, rep(3, 4))
})

test_that("fractional M0 training passes midpoint targets and phase inputs", {
  labels <- PAGe:::validate_timing_labels(
    season = "demo", ignition = c(2L, 3L), peak = c(4L, 5L),
    peak_observed = 4L, n_weeks = 6L
  )
  data <- data.frame(
    season = "demo", weekF = 1:6, y = 1:6, N = rep(10L, 6), p = (1:6) / 10
  )
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    fitIgnition = function(dat, timing_truth, ...) {
      seen$data <- dat
      seen$truth <- timing_truth
      list(data = dat, fits = list())
    },
    .package = "PAGe"
  )

  fit <- PAGe::fitIgnition_timing_v2(data, labels, verbose = FALSE)
  expect_equal(seen$truth$ignition_target_weekF, 2.5)
  expect_equal(seen$data$phase, as.integer(seen$data$weekF >= 2.5))
  expect_equal(fit$timing$target, "ignition_target_weekF")
})

test_that("standalone fractional M0 supplies the detector classifier input", {
  data <- data.frame(
    season = "demo", weekF = 1:12, y = 1:12, N = rep(100L, 12),
    p = (1:12) / 100, p_cls_p = (1:12) / 100
  )
  params <- list(
    cls_thr = 0.05, p_thr = 0.01, prev_thr = 0.001, p_sum_thr = 0.02,
    eps = 0, n_consec = 2L, L = 2L, K_sum = 2L, N_req = 3L,
    w_min = 2L, w_max = 12L
  )
  out <- PAGe::run_ignition_weekly_timing_v2(data, params, start_week = 2L)
  expect_true(is.data.frame(out$df))
  expect_true("iWeek_hat_dynamicF" %in% names(out$df))
})

test_that("fractional M2 snapshots retain decimal aligned coordinates", {
  current <- data.frame(
    season = "demo", weekF = 1:6, y = 1:6, N = rep(10L, 6)
  )
  template <- data.frame(newWeek = 1:52, fit = seq(0.1, 0.9, length.out = 52))
  out <- PAGe:::build_stage2_pseudo_prospective_list(
    current, template, list(delta = 0L, K = 3L, leads = c(1L, 2L)),
    iWeek_hat = 2.5, anchorWeek = 5L, n_weeks = 52L,
    timing_mode = "fractional"
  )
  first <- out$df[[1L]]
  expect_true(any(abs(first$newWeek - round(first$newWeek)) > 0))
  expect_true(any(is.finite(first$template_fit)))
  expect_equal(out$meta$iWeek_hatF, 2.5)
})

test_that("fractional M2 newdata retains the decimal aligned week", {
  seen <- new.env(parent = emptyenv())
  fake <- structure(
    list(model = data.frame(
      lead = factor("h1"), season = factor("demo")
    )),
    class = "page_fake_gam"
  )
  predict.page_fake_gam <- function(object, newdata, ...) {
    seen$newWeek <- newdata$newWeek
    list(fit = 0, se.fit = 0)
  }
  assign("predict.page_fake_gam", predict.page_fake_gam, envir = .GlobalEnv)
  on.exit(rm("predict.page_fake_gam", envir = .GlobalEnv), add = TRUE)

  PAGe:::m2_predict_one(
    fake, ew = 10L, h = 1L, iWeek = 2.5, anchorWeek = 20,
    logit_f_eff = 0, z_ema = 0, logN_now = 1,
    return_ci = TRUE, timing_mode = "fractional"
  )
  expect_equal(seen$newWeek, 27.5)
})

test_that("run_pipeline exposes the opt-in timing mode to every stage", {
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    run_m0_detection = function(..., timing_mode) {
      seen$m0 <- timing_mode
      list(ign_out = list())
    },
    run_m1_alignment = function(..., timing_mode) {
      seen$m1 <- timing_mode
      list(params_df = data.frame(), m1_curves = data.frame())
    },
    run_m2_forecast = function(..., timing_mode) {
      seen$m2 <- timing_mode
      list(m2_preds = data.frame())
    },
    .package = "PAGe"
  )
  PAGe::run_pipeline(
    workflow_kit(), workflow_surveillance("2025-26", 1:2),
    timing_mode = "fractional", verbose = FALSE
  )
  expect_identical(seen$m0, "fractional")
  expect_identical(seen$m1, "fractional")
  expect_identical(seen$m2, "fractional")
  expect_identical(eval(formals(PAGe::run_pipeline)$timing_mode)[[1L]], "legacy")
})
