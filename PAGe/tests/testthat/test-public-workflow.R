test_that("surveillance preparation derives the canonical count fields", {
  from_neg <- data.frame(
    season = "2025-26", weekF = 1:2, y = c(2L, 0L),
    neg = c(8L, 0L), extra = c("a", "b")
  )
  prepared <- PAGe::prepare_surveillance_data(from_neg)

  expect_identical(
    names(prepared)[seq_len(6L)],
    c("season", "weekF", "y", "N", "p", "neg")
  )
  expect_equal(prepared$N, c(10, 0))
  expect_equal(prepared$p, c(0.2, NA_real_))
  expect_identical(prepared$extra, from_neg$extra)

  from_total <- data.frame(weekF = 3L, y = 3L, N = 12L)
  assigned <- PAGe::prepare_surveillance_data(from_total, season = "2025-26")
  expect_equal(assigned$neg, 9)
  expect_equal(assigned$p, 0.25)
  expect_identical(PAGe::validate_surveillance_data(assigned), assigned)
})

test_that("surveillance preparation rejects invalid and inconsistent rows", {
  duplicate <- data.frame(
    season = "2025-26", weekF = c(1L, 1L), y = 1L, N = 10L
  )
  expect_error(PAGe::prepare_surveillance_data(duplicate), "one row")
  expect_error(
    PAGe::prepare_surveillance_data(data.frame(
      season = "2025-26", weekF = 1L, y = 1.5, N = 10L
    )),
    "whole"
  )
  expect_error(
    PAGe::prepare_surveillance_data(data.frame(
      season = "2025-26", weekF = 1L, y = 11L, N = 10L
    )),
    "cannot exceed"
  )
  expect_error(
    PAGe::prepare_surveillance_data(data.frame(
      season = "2025-26", weekF = 1L, y = 1L, N = 10L, p = 0.5
    )),
    "inconsistent"
  )
  expect_error(
    PAGe::prepare_surveillance_data(data.frame(
      season = "", weekF = 1L, y = 1L, N = 10L
    )),
    "season"
  )
  expect_error(
    PAGe::prepare_surveillance_data(data.frame(
      season = "2025-26", weekF = 0L, y = 1L, N = 10L
    )),
    "weekF"
  )
})

test_that("training validates before filtering and returns a stable class", {
  calls <- new.env(parent = emptyenv())
  local_mocked_bindings(
    build_m0 = function(allD, ...) {
      calls$columns <- names(allD)
      list(best_params = list(ok = TRUE))
    },
    build_m1 = function(...) list(ref = list(), hyper = list()),
    train_m2 = function(..., best_spec) list(spec = best_spec, fit = "fit"),
    assemble_kit = function(...) list(ready = TRUE),
    .package = "PAGe"
  )

  result <- PAGe::train_pipeline(
    workflow_surveillance("2024-25", 1L),
    mode = "refresh", prospective_holdout = NULL, verbose = FALSE
  )
  expect_s3_class(result, "page_training_result")
  expect_true(all(c("N", "p", "neg") %in% calls$columns))
  expect_output(print(result), "PAGe training result")

  expect_error(
    PAGe::train_pipeline(
      workflow_surveillance(c("2024-25", "2024-25"), c(1L, 1L)),
      mode = "refresh", verbose = FALSE
    ),
    "one row"
  )
})

test_that("prospective workflow assigns only an unambiguous season", {
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    run_m0_detection = function(kit, current_data, ...) {
      seen$data <- current_data
      list(ign_out = list())
    },
    run_m1_alignment = function(...) {
      list(params_df = data.frame(), m1_curves = data.frame())
    },
    run_m2_forecast = function(...) list(m2_preds = data.frame()),
    .package = "PAGe"
  )

  current <- data.frame(weekF = 1L, y = 2L, N = 10L)
  result <- PAGe::run_prospective_pipeline(
    workflow_kit(), current,
    season = "2025-26", verbose = FALSE
  )
  expect_s3_class(result, "page_forecast")
  expect_identical(seen$data$season, "2025-26")
  expect_equal(seen$data$p, 0.2)
  expect_error(
    PAGe::run_prospective_pipeline(workflow_kit(), current, verbose = FALSE),
    "season"
  )
  expect_no_error(PAGe::run_prospective_pipeline(
    workflow_kit("2025-26"), current,
    verbose = FALSE
  ))
})

test_that("kit validation reports mode-appropriate missing fields", {
  expect_identical(PAGe::validate_page_kit(workflow_kit()), workflow_kit())
  expect_error(PAGe::validate_page_kit(list()), "m0_params")

  broken <- workflow_kit()
  broken$M1_PARAMS$slope_window <- NULL
  expect_error(PAGe::validate_page_kit(broken), "slope_window")

  malformed <- workflow_kit()
  malformed$best_spec <- 4L
  expect_error(PAGe::validate_page_kit(malformed), "specification list")

  expect_error(
    PAGe::validate_page_kit(workflow_kit(), mode = "weekly_refit"),
    "hist_data"
  )
})

test_that("v16 kits without an unused log-N feature remain valid", {
  kit <- workflow_kit()
  expect_false("logN_now" %in% names(kit$m2_production$fit$model))
  expect_no_error(PAGe::validate_page_kit(kit, mode = "frozen"))

  local_mocked_bindings(
    make_soft_cap_fn = function(...) function(x) x,
    stage2_exclude_newseason = function(...) character(),
    .package = "PAGe"
  )
  expect_no_warning(PAGe::run_m2_forecast(
    kit,
    workflow_surveillance("2025-26", 1L),
    m1_result = list(per_week = list()),
    verbose = FALSE
  ))
})

test_that("forecast summaries and printing expose stable essentials", {
  forecast <- structure(list(
    pred_df = data.frame(
      newWeek = c(10L, 11L, 12L),
      p_hat = c(0.1, 0.2, 0.3),
      p_lo = c(NA, 0.15, 0.25),
      p_hi = c(NA, 0.25, 0.35),
      kind = c("observed", "forecast", "forecast")
    ),
    last_obs = 10L,
    m2_preds = data.frame(h = c(1L, 2L))
  ), class = c("page_forecast", "list"))

  info <- summary(forecast)
  expect_identical(info$last_observation, 10L)
  expect_identical(info$n_forecasts, 2L)
  expect_identical(info$horizons, c(1L, 2L))
  expect_equal(info$forecast_range, c(0.2, 0.3))
  expect_output(print(forecast), "PAGe forecast")
})

test_that("forecast plotting handles normal and empty compatible blocks", {
  normal <- list(
    pred_df = data.frame(
      newWeek = c(1L, 2L), p_hat = c(0.1, 0.2),
      p_lo = c(NA, 0.15), p_hi = c(NA, 0.25),
      kind = c("observed", "forecast")
    ),
    last_obs = 1L
  )
  history <- data.frame(
    season = c("2024-25", "2024-25"), newWeek = 1:2,
    y = c(1L, 2L), neg = c(9L, 8L)
  )
  plot <- PAGe::plot_forecast(normal, history)
  expect_s3_class(plot, "ggplot")
  expect_identical(plot$labels$title, "PAGe forecast")

  empty <- list(
    pred_df = data.frame(
      newWeek = integer(), p_hat = numeric(), kind = character()
    ),
    last_obs = NA_integer_
  )
  expect_s3_class(PAGe::plot_forecast(empty), "ggplot")
  expect_error(PAGe::plot_forecast(list(pred_df = data.frame())), "newWeek")
})

test_that("getCurrentD-compatible data satisfies the public contract", {
  current <- data.frame(
    season = "2025-26", weekF = 1:2, y = c(2L, 4L), N = c(20L, 20L),
    neg = c(18L, 16L), p = c(0.1, 0.2), newWeek = 1:2
  )
  expect_no_error(PAGe::prepare_surveillance_data(current))
})
