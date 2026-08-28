test_that("NLL sensitivity extraction reports values and adjacent gains", {
  grid <- data.frame(
    spec_id = paste0("s", 1:4),
    alpha_state = c(0.1, 0.2, 0.3, 0.2),
    k_sp = c(4, 4, 4, 8),
    stringsAsFactors = FALSE
  )
  summary <- data.frame(
    spec_id = grid$spec_id,
    bernoulli_nll = c(0.50, 0.45, 0.46, 0.44),
    stringsAsFactors = FALSE
  )
  scores <- data.frame(
    spec_id = rep(grid$spec_id, each = 2),
    season = rep(c("a", "b"), 4),
    bernoulli_nll = rep(summary$bernoulli_nll, each = 2) +
      rep(c(-0.01, 0.01), 4),
    stringsAsFactors = FALSE
  )
  tuning <- structure(
    list(grid = grid, summary = summary, scores = scores),
    class = "page_m2_tuning"
  )

  out <- PAGe::extract_nll_sensitivity(tuning)
  expect_s3_class(out, "page_nll_sensitivity")
  expect_true(all(c("overall", "by_season", "gains") %in% names(out)))
  expect_setequal(unique(out$overall$parameter), c("alpha_state", "k_sp"))
  expect_equal(
    out$overall$best_metric[out$overall$parameter == "alpha_state"],
    c(0.50, 0.44, 0.46)
  )
  alpha_gain <- out$gains[out$gains$parameter == "alpha_state", ]
  expect_equal(alpha_gain$adjacent_gain, c(NA_real_, 0.06, -0.02))
  expect_equal(alpha_gain$step, c(NA_real_, 0.1, 0.1))
  expect_equal(alpha_gain$gain_per_unit, c(NA_real_, 0.6, -0.2))
  expect_equal(unique(out$gains$global_best[out$gains$parameter == "alpha_state"]), 0.44)
  expect_true(all(c("season", "best_metric") %in% names(out$by_season)))
  matched_alpha <- out$matched_gains[
    out$matched_gains$parameter == "alpha_state", ,
    drop = FALSE
  ]
  expect_equal(matched_alpha$adjacent_gain, c(0.05, -0.01))
  expect_true(nrow(out$matched_gains) >= nrow(matched_alpha))
})

test_that("NLL sensitivity accepts named result collections", {
  make_result <- function(offset) {
    grid <- data.frame(
      spec_id = c("s1", "s2"), alpha_state = c(0.1, 0.2),
      stringsAsFactors = FALSE
    )
    structure(
      list(
        grid = grid,
        summary = data.frame(
          spec_id = grid$spec_id,
          bernoulli_nll = c(0.5, 0.4) + offset
        )
      ),
      class = "page_m2_tuning"
    )
  }
  out <- PAGe::extract_nll_sensitivity(
    list(`2017-18` = make_result(0), `2018-19` = make_result(0.02))
  )
  expect_setequal(unique(out$overall$run), c("2017-18", "2018-19"))
  expect_equal(nrow(out$gains), 4L)
})

test_that("NLL sensitivity validates metrics and parameters", {
  bad <- list(
    grid = data.frame(spec_id = "s1", alpha_state = 0.2),
    summary = data.frame(spec_id = "s1", bernoulli_nll = 0.4)
  )
  expect_error(
    PAGe::extract_nll_sensitivity(bad, parameters = "missing"),
    "No requested parameter"
  )
  expect_error(
    PAGe::extract_nll_sensitivity(bad, metric = "missing"),
    "metric"
  )
})

test_that("NLL sensitivity plot is a ggplot and exposes all parameters", {
  tuning <- structure(
    list(
      grid = data.frame(
        spec_id = c("s1", "s2"), alpha_state = c(0.1, 0.2),
        stringsAsFactors = FALSE
      ),
      summary = data.frame(
        spec_id = c("s1", "s2"), bernoulli_nll = c(0.5, 0.4)
      )
    ),
    class = "page_m2_tuning"
  )
  p <- PAGe::plot_nll_sensitivity(tuning)
  expect_s3_class(p, "ggplot")
  expect_true(any(vapply(p$layers, function(layer) {
    inherits(layer$geom, "GeomPoint")
  }, logical(1))))
})

test_that("M2 boundary gate accepts a matched small outward NLL gain", {
  grid <- data.frame(
    spec_id = c("s1", "s2"), delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
    alpha_state = c(0.10, 0.20), k_r = 0L, k_de = 0L, k_sp = 0L,
    bias_alpha = 0.05, bias_beta = 0
  )
  tuning <- structure(
    list(
      grid = grid,
      summary = data.frame(
        spec_id = grid$spec_id, bernoulli_nll = c(0.40, 0.41)
      ),
      scores = data.frame(
        spec_id = grid$spec_id, season = c("a", "a"),
        bernoulli_nll = c(0.40, 0.41)
      ),
      best_spec_id = "s1", best_spec = grid[1L, , drop = FALSE]
    ),
    class = "page_m2_tuning"
  )
  report <- PAGe::inspect_tuning_boundaries(
    tuning, stage = "M2", warn = FALSE,
    min_nll_gain = c(alpha_state = 0.01)
  )
  expect_equal(report$decision, "stop_small_gain")
  expect_equal(report$nll_gain, 0.01)

  default_report <- PAGe::inspect_tuning_boundaries(
    tuning, stage = "M2", warn = FALSE
  )
  expect_equal(default_report$min_nll_gain, 0.001)
  expect_equal(default_report$decision, "expand_required")
})

test_that("M2 boundary gate does not hide missing matched evidence", {
  grid <- data.frame(
    spec_id = c("s1", "s2"), delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
    alpha_state = c(0.10, 0.20), k_r = c(0L, 2L), k_de = 0L, k_sp = 0L,
    bias_alpha = 0.05, bias_beta = 0
  )
  tuning <- structure(
    list(
      grid = grid,
      summary = data.frame(
        spec_id = grid$spec_id, bernoulli_nll = c(0.40, 0.41)
      ),
      scores = data.frame(
        spec_id = grid$spec_id, season = c("a", "a"),
        bernoulli_nll = c(0.40, 0.41)
      ),
      best_spec_id = "s1", best_spec = grid[1L, , drop = FALSE]
    ),
    class = "page_m2_tuning"
  )
  report <- PAGe::inspect_tuning_boundaries(
    tuning, stage = "M2", warn = FALSE,
    min_nll_gain = c(alpha_state = 0.01)
  )
  expect_equal(report$decision[report$parameter == "alpha_state"],
               "expand_required")
  expect_match(report$reason[report$parameter == "alpha_state"],
               "no matched adjacent")
})
