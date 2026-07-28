adaptive_grid_fixture <- function() {
  grid <- data.frame(
    delta = 0L,
    Kr = 1L,
    k_f = c(4L, 5L, 6L),
    k_e = 2L,
    alpha_state = c(0.10, 0.20, 0.21),
    k_r = 0L,
    k_de = 0L,
    k_sp = 6L,
    bias_alpha = 0.05,
    bias_beta = 0
  )
  grid$spec_id <- PAGe:::.m2_spec_ids(grid)
  grid
}

test_that("previous M2 ranking consolidates duplicate summaries deterministically", {
  grid <- adaptive_grid_fixture()
  previous <- list(
    grid = grid,
    summary = data.frame(
      spec_id = grid$spec_id[c(1L, 2L, 1L, 3L)],
      bernoulli_nll = c(0.10, 0.30, 0.70, Inf)
    )
  )

  ranked <- PAGe:::.rank_previous_m2(previous)
  expect_equal(ranked$k_f, c(5L, 4L))
  expect_equal(ranked$.metric, c(0.30, 0.40))

  reordered <- previous
  reordered$grid <- grid[c(3L, 1L, 2L), ]
  reordered$summary <- previous$summary[c(4L, 3L, 2L, 1L), ]
  expect_identical(
    PAGe::plan_m2_grid(previous, max_specs = 30L),
    PAGe::plan_m2_grid(reordered, max_specs = 30L)
  )
})

test_that("previous M2 ranking fills non-finite summaries from fold scores", {
  grid <- adaptive_grid_fixture()
  previous <- list(
    grid = grid,
    summary = data.frame(
      spec_id = grid$spec_id,
      bernoulli_nll = c(NA_real_, Inf, NA_real_)
    ),
    scores = data.frame(
      spec_id = rep(grid$spec_id, each = 2L),
      bernoulli_nll = c(0.41, 0.39, 0.31, 0.29, NA, Inf)
    )
  )

  ranked <- PAGe:::.rank_previous_m2(previous)
  expect_equal(ranked$k_f, c(5L, 4L))
  expect_equal(ranked$.metric, c(0.30, 0.40))
  expect_equal(ranked$.metric_source, c("scores", "scores"))
})

test_that("previous M2 grid rejects ambiguous source identifiers", {
  grid <- adaptive_grid_fixture()
  grid$spec_id[2L] <- grid$spec_id[1L]
  previous <- list(
    grid = grid,
    summary = data.frame(
      spec_id = grid$spec_id[c(1L, 3L)],
      bernoulli_nll = c(0.30, 0.40)
    )
  )

  expect_error(
    PAGe::plan_m2_grid(previous),
    "must exactly match"
  )
})

test_that("boundary expansion uses the spacing adjacent to the winning boundary", {
  grid <- adaptive_grid_fixture()
  previous <- list(
    grid = grid,
    summary = data.frame(
      spec_id = grid$spec_id,
      bernoulli_nll = c(0.20, 0.30, 0.40)
    )
  )

  planned <- PAGe::plan_m2_grid(previous, max_specs = 30L)
  alpha_boundary <- planned[
    grepl("boundary:alpha_state", planned$provenance, fixed = TRUE), ,
    drop = FALSE
  ]

  expect_equal(alpha_boundary$alpha_state, 0)
  expect_false(any(abs(alpha_boundary$alpha_state - 0.09) < 1e-10))
})

test_that("adaptive M2 caps preserve the incumbent and best prior specification", {
  grid <- adaptive_grid_fixture()
  previous <- list(
    grid = grid,
    summary = data.frame(
      spec_id = grid$spec_id,
      bernoulli_nll = c(0.30, 0.20, 0.40)
    )
  )

  planned <- PAGe::plan_m2_grid(previous, max_finalists = 3L, max_specs = 2L)
  winner_id <- PAGe:::.m2_spec_ids(grid[2L, ])

  expect_equal(nrow(planned), 2L)
  expect_match(planned$provenance[1L], "incumbent:v16", fixed = TRUE)
  expect_true(winner_id %in% planned$spec_id)
  expect_error(PAGe::plan_m2_grid(max_finalists = 1.5), "positive integer")
  expect_error(PAGe::plan_m2_grid(max_specs = 2.5), "positive integer")
})

test_that("all documented M2 selection methods remain explicit options", {
  expect_identical(
    eval(formals(PAGe::select_m2_candidate)$method),
    c("min_nll", "one_se", "pareto")
  )
  expect_identical(
    eval(formals(PAGe::train_pipeline)$selection_method),
    c("min_nll", "one_se", "pareto")
  )
})
