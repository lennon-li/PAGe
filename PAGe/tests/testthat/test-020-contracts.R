find_named_call <- function(expr, target) {
  if (!is.call(expr)) {
    return(list())
  }

  found <- if (is.symbol(expr[[1L]]) && identical(as.character(expr[[1L]]), target)) {
    list(expr)
  } else {
    list()
  }
  children <- lapply(as.list(expr)[-1L], find_named_call, target = target)
  c(found, unlist(children, recursive = FALSE))
}

test_that("run_pipeline output is consumable by plot_forecast", {
  local_mocked_bindings(
    run_m0_detection = function(...) list(ign_out = list()),
    run_m1_alignment = function(...) {
      list(params_df = data.frame(), m1_curves = list())
    },
    run_m2_forecast = function(...) {
      list(m2_preds = data.frame(
        newWeek = c(10, 11),
        p_hat = c(0.10, 0.12),
        p_lo = c(0.08, 0.09),
        p_hi = c(0.13, 0.15),
        kind = c("observed", "forecast")
      ))
    },
    .package = "PAGe"
  )

  result <- PAGe::run_pipeline(
    kit = workflow_kit(),
    current_data = data.frame(
      season = "2025-26", weekF = c(9L, 10L),
      y = c(10L, 12L), N = c(100L, 100L)
    ),
    verbose = FALSE
  )

  expect_no_error(PAGe::plot_forecast(result))
})

test_that("the production runtime defaults to frozen evaluation semantics", {
  mode_default <- eval(formals(PAGe::run_prospective_pipeline)$mode)

  expect_identical(mode_default[[1L]], "frozen")
})

test_that("nested LOSO fold evaluation passes only supported arguments", {
  calls <- find_named_call(
    body(PAGe:::nested_loso_run_fold),
    "nested_loso_m2_eval_frozen_bias"
  )
  expect_length(calls, 1L)

  passed <- names(as.list(calls[[1L]])[-1L])
  passed <- passed[nzchar(passed)]
  supported <- names(formals(PAGe:::nested_loso_m2_eval_frozen_bias))
  unsupported <- setdiff(passed, supported)

  expect_true(
    length(unsupported) == 0L,
    info = paste("Unsupported arguments:", paste(unsupported, collapse = ", "))
  )
})

test_that("locked refresh training has complete M0 and M2 inputs", {
  build_m0_body <- body(PAGe::build_m0)
  return_call <- build_m0_body[[length(build_m0_body)]]
  build_m0_fields <- names(as.list(return_call)[-1L])

  expect_true(
    "best_params" %in% build_m0_fields,
    info = "build_m0() must supply the best_params consumed by train_m2()"
  )

  train_m2_body <- paste(deparse(body(PAGe::train_m2)), collapse = " ")
  handles_null_spec <- grepl("is.null\\(best_spec\\)", train_m2_body)

  expect_true(
    handles_null_spec,
    info = "train_m2() must resolve a locked best_spec when NULL is supplied"
  )
})

test_that("locked refresh defaults match the deployed production settings", {
  expect_equal(
    PAGe:::.default_m0_params(),
    list(
      cls_thr = 0.26, p_thr = 0.005, prev_thr = 0.001,
      p_sum_thr = 0.06, eps = 0, n_consec = 5L, L = 2L,
      K_sum = 5L, N_req = 4L, w_min = 13L, w_max = 26L
    )
  )

  spec <- PAGe:::.default_m2_spec()
  expect_equal(
    spec[c(
      "delta", "Kr", "T", "k_f", "k_e", "alpha_state", "k_r",
      "k_de", "k_sp", "k_n", "k_w", "k_s", "lambda_w", "w_floor",
      "bias_alpha", "bias_beta"
    )],
    list(
      delta = 0L, Kr = 1L, T = "S", k_f = 4L, k_e = 2L,
      alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
      k_n = 0L, k_w = 0L, k_s = 0L, lambda_w = 0, w_floor = 0.05,
      bias_alpha = 0.05, bias_beta = 0
    )
  )
})

test_that("pipeline plot adapter uses latest forecasts and observed positivity", {
  m2_preds <- data.frame(
    eval_week = c(9L, 9L, 10L, 10L),
    h = c(1L, 2L, 1L, 2L),
    target_weekF = c(10L, 11L, 11L, 12L),
    m2_p = c(0.10, 0.11, 0.12, 0.13),
    m2_lo = c(0.08, 0.09, 0.10, 0.11),
    m2_hi = c(0.12, 0.13, 0.14, 0.15)
  )
  current_data <- data.frame(
    weekF = c(9L, 10L), y = c(10, 12), neg = c(90, 88)
  )

  plot_data <- PAGe:::.as_forecast_plot_data(m2_preds, current_data)

  expect_identical(plot_data$last_obs, 10L)
  expect_equal(
    subset(plot_data$pred_df, kind == "forecast")$newWeek,
    c(11L, 12L)
  )
  expect_equal(
    subset(plot_data$pred_df, kind == "forecast")$p_hat,
    c(0.12, 0.13)
  )
  expect_equal(
    subset(plot_data$pred_df, kind == "observed")$p_hat,
    c(0.10, 0.12)
  )
  expect_false(anyDuplicated(plot_data$pred_df[c("newWeek", "kind")]) > 0L)
})

test_that("pipeline plot adapter supports all observation shapes", {
  empty_preds <- data.frame()

  from_p <- PAGe:::.as_forecast_plot_data(
    empty_preds,
    data.frame(weekF = 1:2, p = c(0.20, 0.30))
  )
  expect_equal(from_p$pred_df$p_hat, c(0.20, 0.30))

  from_y_n <- PAGe:::.as_forecast_plot_data(
    empty_preds,
    data.frame(weekF = 1:2, y = c(2, 6), N = c(10, 20))
  )
  expect_equal(from_y_n$pred_df$p_hat, c(0.20, 0.30))

  shaped <- data.frame(
    newWeek = c(10L, 11L, 11L),
    p_hat = c(0.10, 0.12, 0.12),
    p_lo = c(NA, 0.09, 0.09),
    p_hi = c(NA, 0.15, 0.15),
    kind = c("observed", "forecast", "forecast")
  )
  preserved <- PAGe:::.as_forecast_plot_data(
    shaped,
    data.frame(weekF = 10L)
  )
  expect_equal(preserved$pred_df, shaped[c(1L, 2L), ])
})

test_that("getCurrentD honors a requested season from a local CSV", {
  csv <- tempfile(fileext = ".csv")
  on.exit(unlink(csv), add = TRUE)
  utils::write.csv(
    data.frame(
      Surveillance.week = c(40L, 40L),
      Surveillance.period = c("2024-25", "2025-26"),
      Total...of.tests = c(100L, 200L),
      X..of.positive.tests = c(10L, 40L),
      Public.health.unit = c("A", "A"),
      Virus = c("Influenza A", "Influenza A")
    ),
    csv,
    row.names = FALSE
  )

  result <- PAGe::getCurrentD(data = csv, season = "2024-25")

  expect_true("2024-25" %in% result$season)
  expect_false("2025-26" %in% result$season)
})

test_that("functions used by the documented workflow are exported", {
  workflow_functions <- c(
    "load_flu_hist", "build_m0", "build_m1", "train_m2", "assemble_kit",
    "getCurrentD", "run_pipeline", "plot_forecast"
  )

  expect_setequal(
    intersect(workflow_functions, getNamespaceExports("PAGe")),
    workflow_functions
  )
})
