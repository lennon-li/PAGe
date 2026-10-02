test_that("M2 boundary action keeps raw and governed selections distinct", {
  grid <- data.frame(
    spec_id = c("s1", "s2"),
    delta = c(0L, 0L), Kr = c(1L, 1L), k_f = c(4L, 4L),
    k_e = c(2L, 2L), alpha_state = c(0.2, 0.2), k_r = c(0L, 0L),
    k_de = c(0L, 0L), k_sp = c(0L, 2L),
    bias_alpha = c(0.05, 0.05), bias_beta = c(0, 0)
  )
  tuning <- structure(
    list(
      summary = data.frame(
        spec_id = c("s1", "s2"),
        bernoulli_nll = c(1.0, 0.9),
        horizon_mae = c(1.0, 1.0), phase_mae = c(1.0, 1.0)
      ),
      scores = data.frame(
        spec_id = c("s2", "s2"),
        bernoulli_nll = c(0.9, 1.3)
      ),
      grid = grid,
      best_spec = as.list(grid[2L, , drop = FALSE]),
      best_spec_id = "s2",
      specs = list(
        s1 = as.list(grid[1L, , drop = FALSE]),
        s2 = as.list(grid[2L, , drop = FALSE])
      )
    ),
    class = "page_m2_tuning"
  )

  action <- PAGe::boundary_action_plan(
    tuning,
    stage = "M2", selection_method = "one_se"
  )

  raw <- action$raw_boundary_report[
    action$raw_boundary_report$parameter == "k_sp", ,
    drop = FALSE
  ]
  final <- action$final_boundary_report[
    action$final_boundary_report$parameter == "k_sp", ,
    drop = FALSE
  ]
  expect_equal(raw$selected_value, 2)
  expect_equal(raw$decision, "expand_required")
  expect_equal(final$selected_value, 0)
  expect_equal(final$decision, "accept_null_drop")
  expect_false(nrow(action$unresolved) > 0L)
  expect_true(action$settled)
  expect_null(action$next_grid)
})
