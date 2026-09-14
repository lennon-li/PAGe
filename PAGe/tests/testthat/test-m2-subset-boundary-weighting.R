make_subset_scores <- function(grid, seasons, nll_fun) {
  rows <- list()
  for (i in seq_len(nrow(grid))) {
    for (s in seasons) {
      for (h in 1:2) {
        rows[[length(rows) + 1L]] <- data.frame(
          spec_id = as.character(grid$id[i]), season = s, horizon = h,
          bernoulli_nll = nll_fun(grid[i, , drop = FALSE], s, h),
          mae = 0.01,
          bernoulli_nll_test_count = nll_fun(grid[i, , drop = FALSE], s, h),
          bernoulli_nll_equal_week = nll_fun(grid[i, , drop = FALSE], s, h),
          mae_test_count = 0.01, mae_equal_week = 0.01,
          rows = 10, trials = 100, weight_sum = 15,
          status = "ok", stringsAsFactors = FALSE
        )
      }
    }
  }
  do.call(rbind, rows)
}

make_subset_tuning <- function(row, nll_fun, seasons = c("2017-18", "2018-19")) {
  grid <- m2_subset_grid(k_values = c(0L, 3L, 4L))
  sel <- m2_subset_spec(row)
  structure(
    list(
      family = m2_subset_family(), grid = grid,
      scores = make_subset_scores(grid, seasons, nll_fun),
      selected_config = m2_subset_config(h1 = sel, h2 = sel),
      best_spec_id = paste0("h1:", sel$id, "|h2:", sel$id),
      min_nll_gain = NULL
    ),
    class = c("page_m2_subset_tuning", "page_m2_tuning", "list")
  )
}

test_that("phase weights follow the declared target t_since policy", {
  d <- data.frame(u = c(-2, 0, 5, 11, 12, 13, 30), h = c(1, 1, 1, 1, 1, 1, 2))
  w <- PAGe:::.m2_subset_phase_weights(d, early_weight = 2, early_max_t_since = 12)
  expect_equal(w, c(0, 2, 2, 2, 1, 1, 1))
  custom <- PAGe:::.m2_subset_phase_weights(
    d,
    early_weight = 3,
    early_max_t_since = 12,
    pre_ignition_weight = 0.5,
    late_weight = 1.5
  )
  expect_equal(custom, c(0.5, 3, 3, 3, 1.5, 1.5, 1.5))
  expect_error(PAGe:::.m2_subset_phase_weights(d, -1, 12), "early_weight")
  expect_error(PAGe:::.m2_subset_phase_weights(d, 2, -1), "early_max_t_since")
  expect_error(
    PAGe:::.m2_subset_phase_weights(d, 2, 12, -1, 1),
    "pre_ignition_weight"
  )
  expect_error(
    PAGe:::.m2_subset_phase_weights(d, 2, 12, 0, -1),
    "late_weight"
  )
})

test_that("m2_subset_score reports both weighting scales", {
  d <- data.frame(y_lead = c(2, 10), N_lead = c(10, 100))
  p <- c(0.3, 0.05)
  sc <- m2_subset_score(d, p)
  p_obs <- d$y_lead / d$N_lead
  nll_counts <- -d$y_lead * log(p) - (d$N_lead - d$y_lead) * log1p(-p)
  nll_rate <- -(p_obs * log(p) + (1 - p_obs) * log1p(-p))
  expect_equal(unname(sc[["nll_test_count"]]), sum(nll_counts) / sum(d$N_lead))
  expect_equal(unname(sc[["nll_equal_week"]]), mean(nll_rate))
  sc_w <- m2_subset_score(d, p, weights = c(2, 1))
  expect_equal(
    unname(sc_w[["nll_equal_week"]]),
    sum(c(2, 1) * nll_rate) / 3
  )
  expect_equal(unname(sc_w[["nll_test_count"]]), sum(c(2, 1) * nll_counts) / sum(c(2, 1) * d$N_lead))
  empty <- m2_subset_score(d[0, , drop = FALSE], numeric(0))
  expect_true(is.na(empty[["nll_equal_week"]]))
  expect_error(m2_subset_score(d, p, weights = c(1, -1)), "non-negative")
})

test_that("subset boundary report flags non-null edges and accepts nulls", {
  strong <- function(row, s, h) 0.5 - 0.01 * (row$k_z + row$k_u + row$k_d) - 0.005 * as.integer(row$intercept)
  edge <- make_subset_tuning(
    list(intercept = TRUE, k_z = 4L, k_u = 4L, k_d = 4L), strong
  )
  expect_warning(
    report <- inspect_tuning_boundaries(edge, stage = "M2", warn = TRUE),
    class = "page_boundary_warning"
  )
  expect_true(all(c("horizon", "parameter", "decision") %in% names(report)))
  unresolved <- report[report$decision == "expand_required", ]
  expect_equal(sort(unique(unresolved$parameter)), c("k_d", "k_u", "k_z"))
  expect_equal(nrow(unresolved), 6L)
  expect_true(all(report$decision[report$parameter == "intercept"] == "stop_hard_cap"))

  off <- make_subset_tuning(
    list(intercept = FALSE, k_z = 0L, k_u = 0L, k_d = 0L), strong
  )
  off_report <- inspect_tuning_boundaries(off, stage = "M2", warn = FALSE)
  expect_true(all(off_report$decision %in% c("accept_null_drop", "stop_bracketed")))
  expect_false(any(off_report$decision == "expand_required"))
})

test_that("subset small-gain cap stops a matched adjacent edge", {
  tiny <- function(row, s, h) 0.5 - 0.0001 * (row$k_z + row$k_u + row$k_d)
  edge <- make_subset_tuning(
    list(intercept = FALSE, k_z = 4L, k_u = 0L, k_d = 0L), tiny
  )
  report <- inspect_tuning_boundaries(edge, stage = "M2", warn = FALSE)
  kz <- report[report$parameter == "k_z", ]
  expect_true(all(kz$decision == "stop_small_gain"))
  expect_true(all(is.finite(kz$nll_gain)))
  plan <- boundary_action_plan(edge, stage = "M2")
  expect_true(plan$settled)
  expect_null(plan$next_grid)
})

test_that("subset expansion is additive and preserves IDs", {
  strong <- function(row, s, h) 0.5 - 0.01 * (row$k_z + row$k_u + row$k_d)
  edge <- make_subset_tuning(
    list(intercept = TRUE, k_z = 4L, k_u = 4L, k_d = 4L), strong
  )
  next_grid <- suppressWarnings(expand_tuning_grid(edge, stage = "M2"))
  expect_true(all(as.character(edge$grid$id) %in% as.character(next_grid$id)))
  new_ids <- setdiff(as.character(next_grid$id), as.character(edge$grid$id))
  expect_setequal(new_ids, c("i1_kz5_ku4_kd4", "i1_kz4_ku5_kd4", "i1_kz4_ku4_kd5"))
  expect_error(
    suppressWarnings(expand_tuning_grid(edge, stage = "M2", max_specs = 10L)),
    "max_specs"
  )
  plan <- suppressWarnings(boundary_action_plan(edge, stage = "M2"))
  expect_false(plan$settled)
  expect_equal(nrow(plan$unresolved), 6L)
  expect_identical(plan$next_grid, next_grid)
})

test_that("default M2 gain caps cover every subset axis", {
  caps <- default_m2_nll_gain_caps()
  expect_true(all(c("k_z", "k_u", "k_d", "intercept") %in% names(caps)))
  expect_true(all(caps >= 0))
})
