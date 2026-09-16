# Focused regressions for the round-5 review fixes.

test_that("selection lifecycle counts the initial selection and hard-stops", {
  tune_calls <- 0L
  plan_calls <- 0L
  expect_error(
    PAGe:::.nested_selection_lifecycle(
      stage = "M0", initial_grid = data.frame(x = 1), max_rounds = 2L,
      tune = function(grid, attempt, previous) {
        tune_calls <<- tune_calls + 1L
        list(best_params = list(x = grid$x[1L]))
      },
      plan = function(x, grid, attempt) {
        plan_calls <<- plan_calls + 1L
        list(settled = FALSE, next_grid = grid)
      },
      validate = identity
    ),
    "unresolved after 2 selection"
  )
  expect_identical(tune_calls, 2L)
  expect_identical(plan_calls, 2L)
})

test_that("alignment uses one common support with dilation as parameter three", {
  t <- 5:40
  g <- function(x) -3 + 3 * exp(-((x - 25) / 8)^2)
  y <- round(1000 * stats::plogis(g((t - 3) / 1.1)))
  d <- data.frame(newWeek = t, y = y, neg = 1000 - y)
  support_calls <- 0L
  real_support <- PAGe:::.page_alignment_common_support
  testthat::local_mocked_bindings(
    .page_alignment_common_support = function(...) {
      support_calls <<- support_calls + 1L
      real_support(...)
    },
    .package = "PAGe"
  )
  fit <- PAGe:::fit_tau_delta(
    d, g, c(-2, 2), c(-.2, .2),
    allow_scale = FALSE,
    week_threshold_delta = 1, lam_delta = 0, curvature_ratio = 0
  )
  expect_identical(support_calls, 1L)
  expect_equal(fit$support_delta_bounds, c(-.2, .2))
  expect_length(fit$support, nrow(d))
})

test_that("unscaled M2 correction retains the centered factor-by offset basis", {
  d <- expand.grid(
    z = seq(-2, 2, length.out = 30),
    lead = factor(c("h1", "h2"), levels = c("h1", "h2")),
    season = c("A", "B", "C")
  )
  d$m1_logit <- stats::qlogis(.2)
  d$y_lead <- 40
  d$N_lead <- 100
  spec <- PAGe:::m2_subset_spec(
    intercept = FALSE, k_z = 3L, k_u = 0L, k_d = 0L, k_tau = 0L,
    conf_scale = "none"
  )
  fit <- PAGe:::m2_subset_fit(d, spec)
  prediction <- PAGe:::m2_subset_predict(fit, d)$p_hat
  expect_equal(mean(prediction), .2, tolerance = 1e-8)
  expect_identical(fit$confidence_basis, "centered_factor_by")
  expect_match(
    paste(deparse(PAGe:::m2_subset_formula(spec)), collapse = " "),
    "by = lead"
  )
})

test_that("shadow export keeps both public shadow prediction names", {
  data <- data.frame(
    season = rep("A", 8), weekF = 1:8,
    y = c(1, 2, 3, 4, 5, 4, 3, 2), N = 20
  )
  rows <- data.frame(
    season = "A", origin = 3, target = 4, horizon = 1,
    outcome = .2, N_lead = 20, m1_prediction = .2,
    m2_prediction = .21, m2_shadow_prediction = .19,
    t_since_target = 1
  )
  out <- PAGe:::.nested_scoring_export(rows, data)
  expect_equal(out$shadow_m2_p, .19)
  expect_equal(out$m2_shadow_prediction, .19)
})

test_that("ordinary M2 selection scores are labelled cross-fitted", {
  d <- expand.grid(
    season = c("A", "B"), h = 1:2, row = 1:2
  )
  d$y_lead <- 20
  d$N_lead <- 100
  d$lead <- factor(ifelse(d$h == 1, "h1", "h2"), levels = c("h1", "h2"))
  d$m1_logit <- stats::qlogis(.2)
  grid <- PAGe:::m2_subset_grid(k_values = 0L)
  out <- PAGe:::.m2_subset_select_core(
    training_data = d, row_weights = rep(1, nrow(d)), grid = grid,
    training_seasons = c("A", "B"),
    scored_seasons_by_horizon = list(`1` = c("A", "B"), `2` = c("A", "B")),
    nll_primary = "nll_equal_week", mae_primary = "mae_equal_week",
    alpha_state = .2, gamma = 1.4
  )
  expect_true(all(out$scores$evaluation_label == "cross-fitted"))
})
