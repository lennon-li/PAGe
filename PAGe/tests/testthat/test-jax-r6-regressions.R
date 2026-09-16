# Focused regressions for the round-6 review fixes.

.r6_m2_boundary_fixture <- function() {
  g0 <- PAGe:::m2_subset_grid(
    k_z_values = c(0, 3, 4, 5),
    k_u_values = c(0, 7, 8, 9),
    k_d_values = c(0, 3, 4, 5, 6, 7)
  )
  summary <- data.frame(
    spec_id = g0$id,
    bernoulli_nll = seq_len(nrow(g0))
  )
  gx <- PAGe:::.m2_subset_stage_b_grid(g0, summary)
  win <- gx[which.max(gx$k_tau), ]
  scores <- expand.grid(
    spec_id = gx$id, season = c("A", "B", "C"), horizon = 1:2,
    stringsAsFactors = FALSE
  )
  scores$bernoulli_nll <- 1 - .01 * gx$k_tau[match(scores$spec_id, gx$id)]
  scores$status <- "ok"
  tuning <- structure(
    list(
      family = PAGe:::m2_subset_family(), grid = gx, scores = scores,
      selected_config = PAGe:::m2_subset_config(win, win)
    ),
    class = c("page_m2_subset_tuning", "page_m2_tuning", "list")
  )
  list(initial = g0, actual = gx, tuning = tuning)
}

test_that("M2 nested callers charge expansion from the tuner's returned grid", {
  fx <- .r6_m2_boundary_fixture()
  expect_error(
    PAGe::boundary_action_plan(
      fx$tuning,
      stage = "M2", max_specs = nrow(fx$initial) + 12L
    ),
    "exceeds max_specs"
  )
  plan <- PAGe::boundary_action_plan(
    fx$tuning,
    stage = "M2", max_specs = nrow(fx$actual) + 12L
  )
  expect_false(plan$settled)
  expect_equal(nrow(plan$next_grid), 207L)

  outer_body <- paste(deparse(body(PAGe:::train_outer_fold)), collapse = " ")
  gate_body <- paste(deparse(body(PAGe:::.nested_gate_select_config)), collapse = " ")
  expect_false(grepl("max_specs = nrow(current_grid)", outer_body, fixed = TRUE))
  expect_false(grepl("max_specs = nrow(current_grid)", gate_body, fixed = TRUE))
})

test_that("tau profiling and amplitude fitting retain the saved common support", {
  g <- function(u) qlogis(.008 + .22 * exp(-.5 * ((u - 27) / 5.5)^2))
  t <- 1:35
  y <- round(1000 * plogis(g(t)))
  d <- data.frame(newWeek = t, y = y, neg = 1000 - y)
  fit <- PAGe:::fit_tau_delta(
    d, g, c(-6, 6), c(0, 0),
    allow_scale = FALSE,
    week_threshold_delta = Inf, lam_delta = 0
  )
  expect_equal(sum(fit$support), 29L)

  counts <- integer()
  g_profile <- function(u) {
    z <- PAGe:::.page_alignment_eval(g, u)
    counts <<- c(counts, sum(is.finite(z)))
    z
  }
  PAGe:::tau_profile_se(
    d, g_profile,
    allow_scale = FALSE, tau0 = fit$tau,
    tau_bounds = c(-6, 6), support = fit$support, weights = fit$w
  )
  expect_true(length(counts) > 0L)
  expect_true(all(counts == 29L))

  out <- PAGe:::align_forecast_pipeline_dilate(
    d, g, function(u) list(mu = g(u), se = rep(.05, length(u))),
    list(
      TAU_BOUNDS = c(-6, 6), DELTA_BOUNDS = c(0, 0),
      WEEK_THRESHOLD_DELTA = Inf, LAMBDA_DELTA = 0
    ),
    allow_scale = FALSE, future_weeks = integer()
  )
  expect_equal(out$n_admissible, 29L)
})

.r6_alignment_failure_fixture <- function() {
  g <- function(u) qlogis(.008 + .22 * exp(-.5 * ((u - 27) / 5.5)^2))
  week <- 1:18
  y <- round(1500 * plogis(g(week - 3)))
  current <- data.frame(weekF = week, y = y, neg = 1500 - y)
  hyper <- list(
    TAU_BOUNDS = c(-9.006965, 12.76346),
    DELTA_BOUNDS = c(-.0962749, .05133914),
    WEEK_THRESHOLD_DELTA = 12, LAMBDA_DELTA = .1
  )
  ref <- list(
    anchorWeek = 15L,
    eta_mat = matrix(g(1:52), 52, 3),
    g_ref_fun = g,
    g_ref_mu_se = function(u) list(mu = g(u), se = rep(.05, length(u)))
  )
  ign <- list(
    ign_week_locked = 18L, iWeek_hat_locked = 18L,
    iWeek_hat_lockedF = 18
  )
  list(g = g, current = current, hyper = hyper, ref = ref, ign = ign)
}

test_that("post-ignition support failures stay distinct and reach the ledger", {
  fx <- .r6_alignment_failure_fixture()
  out <- suppressWarnings(PAGe:::run_alignment_prospective_multi(
    fx$current, fx$ref, fx$hyper, fx$ign,
    allow_scale = FALSE
  ))
  expect_identical(out$state, "alignment_failed")
  expect_match(out$fallback_reason, "support")
  expect_identical(out$ign_week_locked, 18L)

  batch <- suppressWarnings(PAGe:::run_alignment_prospective_multi_weights(
    fx$current, fx$ref, fx$hyper, fx$ign,
    weight_sets = list(
      a = list(
        temperature = .25, slope_weight = 8, slope_window = 6L,
        dynamic_temp = FALSE, dynamic_temp_pivot = 10L
      )
    ),
    allow_scale = FALSE
  ))
  expect_identical(batch[[1L]]$state, "alignment_failed")
  expect_identical(batch[[1L]]$fallback_reason, out$fallback_reason)

  ledger <- suppressWarnings(PAGe:::m1_walkforward_predictions(
    data.frame(
      season = "S", weekF = fx$current$weekF,
      y = fx$current$y, neg = fx$current$neg
    ),
    fx$ref, fx$hyper,
    ign_out = fx$ign,
    horizons = 1:2, eval_weeks = 18L, allow_scale = FALSE,
    temperature = .25, slope_weight = 8, dynamic_temp = FALSE
  ))
  expect_equal(nrow(ledger), 2L)
  expect_true(all(!ledger$forecast_available))
  expect_true(all(ledger$m1_state == "alignment_failed"))
  expect_identical(unique(ledger$unavailable_reason), out$fallback_reason)
})
