test_that("plan_training is a read-only governed dry run", {
  expect_equal(PAGe::default_m1_hard_caps()$k_ref, c(lower = 10L, upper = 50L))
  data <- data.frame(
    season = rep(c("a", "b"), each = 30),
    weekF = rep(1:30, 2),
    y = 1L,
    N = 10L
  )
  checkpoint <- tempfile()
  plan <- PAGe::plan_training(
    data,
    prospective_holdout = NULL,
    checkpoint_dir = checkpoint,
    n_cores = 1L,
    m0_grid = data.frame(
      cls_thr = 0.26, p_thr = 0.005, prev_thr = 0.001,
      n_consec = 5L, L = 2L, eps = 0, K_sum = 5L,
      p_sum_thr = 0.06, N_req = 4L, w_min = 13L, w_max = 26L
    ),
    m1_grid = data.frame(
      k_ref = c(20L, 25L), multi_temperature = 0.25,
      template_shift = 0L, align_rise_weight = 1,
      slope_window = 6L, slope_weight = c(8, 12)
    ),
    m2_grid = data.frame(
      delta = 0L, Kr = 1L, k_f = 4L, k_e = 0L,
      alpha_state = 0.2, k_r = 0L, k_de = 0L, k_sp = 0L,
      bias_alpha = 0.05, bias_beta = 0
    )
  )
  expect_s3_class(plan, "page_training_plan")
  expect_equal(plan$grid_sizes, c(M0 = 1L, M1 = 2L, M2 = 1L))
  expect_true(plan$support$m0$valid)
  expect_true(plan$support$m1$valid)
  expect_true(plan$support$m2$deferred)
  expect_false(dir.exists(checkpoint))
})

test_that("boundary_action_plan exposes raw/final reports and next grid", {
  tuning <- structure(
    list(
      scores = data.frame(
        spec_id = c("s1", "s2"),
        k_ref = c(20L, 30L), slope_weight = c(8, 12),
        mae_weibull = c(1, 1.2)
      ),
      best = data.frame(
        spec_id = "s1", k_ref = 20L, slope_weight = 8,
        mae_weibull = 1
      ),
      grid = data.frame(
        spec_id = c("s1", "s2"),
        k_ref = c(20L, 30L), slope_weight = c(8, 12)
      )
    ),
    class = "page_m1_tuning"
  )
  action <- PAGe::boundary_action_plan(
    tuning, stage = "M1", steps = c(k_ref = 5, slope_weight = 4)
  )
  expect_s3_class(action, "page_boundary_action_plan")
  expect_true(is.data.frame(action$raw_boundary_report))
  expect_true(is.data.frame(action$final_boundary_report))
  expect_true(any(action$unresolved$parameter == "k_ref"))
  expect_true(any(action$next_grid$k_ref == 15L))
})
