# .nested_gate_select_config() must thread its own n_cores argument into
# .m2_subset_select_core()'s already-working parallel branch, instead of
# silently running the gate's M2 stage-A/B grid serially. Mocks isolate the
# threading change from boundary-detection/provenance logic, which is
# untested here on purpose (covered elsewhere).

test_that(".nested_gate_select_config threads n_cores into the core M2 call", {
  recorded <- new.env()
  fake_core <- function(training_data, row_weights, grid, training_seasons,
                        scored_seasons_by_horizon, nll_primary, mae_primary,
                        alpha_state, gamma, n_cores = 1L, ckpt_dir = NULL,
                        label = "M2 subset tuning", evaluation_label = "cross-fitted") {
    recorded$n_cores <- n_cores
    list(
      grid = grid,
      scores = data.frame(
        id = grid$id, h = 1L, nll_equal_week = 1, mae_equal_week = 1,
        nll_test_count = 1, mae_test_count = 1, rows = 1, trials = 1,
        weight_sum = 1, stringsAsFactors = FALSE
      ),
      summary = data.frame(id = grid$id[1], h = 1L, stringsAsFactors = FALSE),
      selected = stats::setNames(
        list(grid[1, , drop = FALSE], grid[1, , drop = FALSE]), c("h1", "h2")
      ),
      selected_config = list(
        h1 = as.list(grid[1, , drop = FALSE]), h2 = as.list(grid[1, , drop = FALSE]),
        gamma = gamma
      ),
      best_spec_id = as.character(grid$id[1]),
      coverage = data.frame(h = 1L, n = 1L)
    )
  }
  fake_boundary <- function(x, stage, steps, max_specs) list(settled = TRUE, next_grid = NULL)

  testthat::local_mocked_bindings(
    .m2_subset_select_core = fake_core,
    boundary_action_plan = fake_boundary,
    .package = "PAGe"
  )

  grid <- data.frame(id = c("s1", "s2"), stringsAsFactors = FALSE)
  train <- data.frame(season = "2011-12", h = 1L, stringsAsFactors = FALSE)

  out <- .nested_gate_select_config(
    tuning = list(), training_rows = train,
    training_seasons = "2011-12", grid = grid,
    n_cores = 5L
  )
  expect_identical(recorded$n_cores, 5L)
  expect_identical(out$selected_ids[["h1"]], "s1")

  recorded$n_cores <- NULL
  .nested_gate_select_config(
    tuning = list(), training_rows = train,
    training_seasons = "2011-12", grid = grid
  )
  expect_identical(recorded$n_cores, 1L)
})

test_that(".nested_gate_select_config actually installs a parallel future plan for n_cores > 1", {
  # .m2_subset_select_core() parallelizes with furrr::future_map(), which
  # obeys the ACTIVE future plan, not an argument -- passing n_cores
  # through (the fix above) does nothing on its own unless a plan is
  # installed around the call. Capture the plan class live during the
  # mocked core call, not just the n_cores value.
  seen_plan_class <- NULL
  seen_workers <- NULL
  before_class <- class(future::plan())[[1]]

  fake_core <- function(training_data, row_weights, grid, training_seasons,
                        scored_seasons_by_horizon, nll_primary, mae_primary,
                        alpha_state, gamma, n_cores = 1L, ckpt_dir = NULL,
                        label = "M2 subset tuning", evaluation_label = "cross-fitted") {
    seen_plan_class <<- class(future::plan())[[1]]
    seen_workers <<- future::nbrOfWorkers()
    list(
      grid = grid,
      scores = data.frame(
        id = grid$id, h = 1L, nll_equal_week = 1, mae_equal_week = 1,
        nll_test_count = 1, mae_test_count = 1, rows = 1, trials = 1,
        weight_sum = 1, stringsAsFactors = FALSE
      ),
      summary = data.frame(id = grid$id[1], h = 1L, stringsAsFactors = FALSE),
      selected = stats::setNames(
        list(grid[1, , drop = FALSE], grid[1, , drop = FALSE]), c("h1", "h2")
      ),
      selected_config = list(
        h1 = as.list(grid[1, , drop = FALSE]), h2 = as.list(grid[1, , drop = FALSE]),
        gamma = gamma
      ),
      best_spec_id = as.character(grid$id[1]),
      coverage = data.frame(h = 1L, n = 1L)
    )
  }
  fake_boundary <- function(x, stage, steps, max_specs) list(settled = TRUE, next_grid = NULL)

  testthat::local_mocked_bindings(
    .m2_subset_select_core = fake_core,
    boundary_action_plan = fake_boundary,
    .package = "PAGe"
  )

  grid <- data.frame(id = c("s1", "s2"), stringsAsFactors = FALSE)
  train <- data.frame(season = "2011-12", h = 1L, stringsAsFactors = FALSE)

  .nested_gate_select_config(
    tuning = list(), training_rows = train,
    training_seasons = "2011-12", grid = grid,
    n_cores = 2L
  )
  expect_false(identical(seen_plan_class, "sequential"))
  # Not just "a plan" -- the plan must actually be sized to n_cores, or
  # this test would pass identically for a hardcoded worker count.
  expect_equal(seen_workers, 2L)
  # Plan is restored on exit, same as m2_subset_tune()'s own on.exit pattern.
  expect_identical(class(future::plan())[[1]], before_class)
})
