test_that("the initial M2 plan is bounded, deterministic, and contains v16", {
  first <- PAGe::plan_m2_grid(max_specs = 24L)
  second <- PAGe::plan_m2_grid(max_specs = 24L)

  expect_identical(first, second)
  expect_lte(nrow(first), 24L)
  expect_false(anyDuplicated(first$spec_id) > 0L)
  expect_true(all(nzchar(first$provenance)))

  incumbent <- subset(
    first,
    delta == 0L & Kr == 1L & k_f == 4L & k_e == 2L &
      alpha_state == 0.15 & k_r == 0L & k_de == 0L & k_sp == 6L &
      bias_alpha == 0.05 & bias_beta == 0
  )
  expect_equal(nrow(incumbent), 1L)
  expect_match(incumbent$provenance, "incumbent", fixed = TRUE)
})

test_that("the adaptive M2 plan retains diverse finalists and expands boundaries", {
  prior_grid <- data.frame(
    delta = 0L,
    Kr = 1L,
    k_f = c(4L, 5L, 4L, 3L),
    k_e = 2L,
    alpha_state = c(0.20, 0.15, 0.10, 0.15),
    k_r = 0L,
    k_de = 0L,
    k_sp = c(6L, 6L, 10L, 2L),
    bias_alpha = 0.05,
    bias_beta = 0
  )
  prior_grid$spec_id <- PAGe:::.m2_spec_ids(prior_grid)
  prior_summary <- data.frame(
    spec_id = prior_grid$spec_id,
    bernoulli_nll = c(0.40, 0.401, 0.402, 0.403)
  )
  previous <- list(grid = prior_grid, summary = prior_summary)

  planned <- PAGe::plan_m2_grid(
    previous_results = previous,
    max_finalists = 3L,
    max_specs = 30L
  )

  expect_lte(nrow(planned), 30L)
  expect_false(anyDuplicated(planned$spec_id) > 0L)
  expect_true(all(planned$delta >= 0L))
  expect_true(all(planned$Kr >= 1L))
  expect_true(all(planned$k_f >= 2L & planned$k_e >= 2L))
  expect_true(all(planned$alpha_state >= 0 & planned$alpha_state <= 1))
  expect_true(all(planned$bias_alpha >= 0 & planned$bias_alpha <= 1))
  expect_true(all(planned$bias_beta >= 0 & planned$bias_beta <= 1))

  retained_ids <- planned$spec_id[grepl("prior_finalist", planned$provenance)]
  expect_true(prior_grid$spec_id[1L] %in% retained_ids)
  expect_true(prior_grid$spec_id[3L] %in% retained_ids)
  expect_true(any(abs(planned$alpha_state - 0.25) < 1e-8))
  expect_true(any(grepl("boundary:alpha_state", planned$provenance, fixed = TRUE)))
})

test_that("M2 grid conversion uses row-specific bias values and unique IDs", {
  grid <- data.frame(
    delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
    alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
    bias_alpha = c(0.05, 0.20), bias_beta = c(0, 0.10)
  )

  converted <- PAGe:::.m2_specs_from_grid(
    grid,
    bias_alpha = 0.4,
    bias_beta = 0
  )

  expect_equal(
    unname(vapply(converted$specs, `[[`, numeric(1), "bias_alpha")),
    c(0.05, 0.20)
  )
  expect_equal(
    unname(vapply(converted$specs, `[[`, numeric(1), "bias_beta")),
    c(0, 0.10)
  )
  expect_false(anyDuplicated(converted$grid$spec_id) > 0L)
  expect_match(converted$grid$spec_id[1L], "_ba0.05_bb0", fixed = TRUE)
  expect_match(converted$grid$spec_id[2L], "_ba0.2_bb0.1", fixed = TRUE)

  legacy <- grid[1L, setdiff(names(grid), c("bias_alpha", "bias_beta"))]
  legacy_converted <- PAGe:::.m2_specs_from_grid(
    legacy,
    bias_alpha = 0.4,
    bias_beta = 0.2
  )
  expect_equal(legacy_converted$specs[[1L]]$bias_alpha, 0.4)
  expect_equal(legacy_converted$specs[[1L]]$bias_beta, 0.2)
})

test_that("refresh training uses a compatible prior best and skips tuning", {
  prior_spec <- PAGe:::.default_m2_spec()
  prior_spec$k_f <- 5L
  calls <- new.env(parent = emptyenv())

  local_mocked_bindings(
    build_m0 = function(...) list(best_params = list(ok = TRUE)),
    build_m1 = function(...) list(ref = list(), hyper = list()),
    tune_m0 = function(...) stop("refresh must not tune M0"),
    tune_m1 = function(...) stop("refresh must not tune M1"),
    build_m2 = function(...) stop("refresh must not tune M2"),
    train_m2 = function(allD, m0, m1, best_spec, exclude, verbose) {
      calls$best_spec <- best_spec
      calls$exclude <- exclude
      list(spec = best_spec, fit = "fit")
    },
    assemble_kit = function(...) list(ready = TRUE),
    .package = "PAGe"
  )

  result <- PAGe::train_pipeline(
    workflow_surveillance("2025-26", 1L),
    mode = "refresh",
    previous_results = list(best_spec = prior_spec),
    n_cores = 1L,
    verbose = FALSE
  )

  expect_identical(result$mode, "refresh")
  expect_null(result$tuning)
  expect_null(result$grid)
  expect_true(result$kit$ready)
  expect_identical(calls$best_spec, prior_spec)
  expect_true("2025-26" %in% calls$exclude)
  expect_false(result$holdout$released)
  expect_identical(result$holdout$status, "held_out")

  failed <- PAGe::check_promotion(
    list(
      overall = data.frame(bernoulli_nll = 0.50),
      horizon = data.frame(lead = c("1", "2"), mae = c(0.10, 0.10)),
      phase = data.frame(phase = c("early", "late"), mae = c(0.10, 0.10))
    ),
    list(
      overall = data.frame(bernoulli_nll = 0.50),
      horizon = data.frame(lead = c("1", "2"), mae = c(0.10, 0.10)),
      phase = data.frame(phase = c("early", "late"), mae = c(0.10, 0.10))
    )
  )
  failed_result <- PAGe::train_pipeline(
    workflow_surveillance("2025-26", 1L),
    mode = "refresh", previous_results = list(best_spec = prior_spec),
    promotion = failed, n_cores = 1L, verbose = FALSE
  )
  expect_true("2025-26" %in% calls$exclude)
  expect_false(failed_result$holdout$released)
  expect_identical(failed_result$holdout$status, "promotion_failed")
})

test_that("refresh falls back to locked v16 for an incompatible prior best", {
  calls <- new.env(parent = emptyenv())

  local_mocked_bindings(
    build_m0 = function(...) list(best_params = list(ok = TRUE)),
    build_m1 = function(...) list(ref = list(), hyper = list()),
    train_m2 = function(allD, m0, m1, best_spec, exclude, verbose) {
      calls$best_spec <- best_spec
      list(spec = best_spec, fit = "fit")
    },
    assemble_kit = function(...) list(ready = TRUE),
    .package = "PAGe"
  )

  PAGe::train_pipeline(
    workflow_surveillance("2025-26", 1L),
    mode = "refresh",
    previous_results = list(best_spec = list(k_f = 99L)),
    n_cores = 1L,
    verbose = FALSE
  )

  expect_equal(calls$best_spec$k_f, 4L)
  expect_equal(calls$best_spec$alpha_state, 0.15)
  expect_equal(calls$best_spec$bias_alpha, 0.05)
})

test_that("retune training runs all tuning stages and fits the winning M2 spec", {
  calls <- new.env(parent = emptyenv())
  calls$build_m1 <- 0L
  winner <- PAGe:::.default_m2_spec()
  winner$k_f <- 5L

  local_mocked_bindings(
    tune_m0 = function(allD, ...) {
      calls$m0_seasons <- allD$season
      list(best_params = list(ok = TRUE), tuning = list(stage = "m0"))
    },
    build_m1 = function(allD, m0, exclude, m1_params, ...) {
      calls$build_m1 <- calls$build_m1 + 1L
      calls$m1_seasons <- c(calls$m1_seasons, list(allD$season))
      calls$m1_params <- m1_params
      list(ref = list(), hyper = list(), m1_params = m1_params)
    },
    tune_m1 = function(allD, ...) {
      calls$m1_tune_seasons <- allD$season
      list(
        best = data.frame(
          k_ref = 30L, multi_temperature = 0.20,
          align_rise_weight = 1, slope_window = 6L,
          slope_weight = 12, mae_weibull = 1
        ),
        scores = data.frame(), grid = data.frame()
      )
    },
    build_m2 = function(allD, m0, m1, grid, holdout_season, ...) {
      calls$m2_grid <- grid
      calls$m2_seasons <- allD$season
      calls$m2_holdout <- holdout_season
      list(
        best_spec = winner,
        best_spec_id = "winner",
        summary = data.frame(spec_id = "winner", bernoulli_nll = 0.4),
        grid = grid
      )
    },
    train_m2 = function(allD, m0, m1, best_spec, exclude, verbose) {
      calls$best_spec <- best_spec
      calls$seasons <- allD$season
      calls$exclude <- exclude
      list(spec = best_spec, fit = "fit")
    },
    assemble_kit = function(...) list(ready = TRUE),
    .package = "PAGe"
  )

  passing_promotion <- PAGe::check_promotion(
    list(
      overall = data.frame(bernoulli_nll = 0.48),
      horizon = data.frame(lead = c("1", "2"), mae = c(0.103, 0.103)),
      phase = data.frame(phase = c("early", "late"), mae = c(0.105, 0.105))
    ),
    list(
      overall = data.frame(bernoulli_nll = 0.50),
      horizon = data.frame(lead = c("1", "2"), mae = c(0.10, 0.10)),
      phase = data.frame(phase = c("early", "late"), mae = c(0.10, 0.10))
    )
  )

  result <- PAGe::train_pipeline(
    workflow_surveillance(c("2024-25", "2025-26"), c(1L, 1L)),
    mode = "retune",
    promotion = passing_promotion,
    loso_seasons = "alternating",
    n_cores = 1L,
    verbose = FALSE,
    m0_grid = data.frame(p_thr = 0.005),
    m1_grid = data.frame(k_ref = 25L)
  )

  expect_identical(result$mode, "retune")
  expect_equal(calls$build_m1, 2L)
  expect_equal(calls$m1_params$k_ref, 30L)
  expect_equal(calls$m1_params$slope_weight, 12)
  expect_identical(calls$best_spec, winner)
  expect_true("2025-26" %in% calls$m0_seasons)
  expect_true(all(vapply(calls$m1_seasons, function(x) "2025-26" %in% x, logical(1))))
  expect_true("2025-26" %in% calls$m1_tune_seasons)
  expect_true("2025-26" %in% calls$m2_seasons)
  expect_null(calls$m2_holdout)
  expect_true("2025-26" %in% calls$seasons)
  expect_false("2025-26" %in% calls$exclude)
  expect_true(result$holdout$released)
  expect_identical(result$holdout$status, "released")
  expect_identical(result$grid, calls$m2_grid)
  expect_named(result$tuning, c("m0", "m1", "m2"))
  expect_identical(result$selection$method, "min_nll")
  expect_null(result$racing)
  expect_true(result$kit$ready)
})

test_that("retune keeps the prospective holdout out of every stage by default", {
  seen <- new.env(parent = emptyenv())
  winner <- PAGe:::.default_m2_spec()

  local_mocked_bindings(
    tune_m0 = function(allD, exclude, ...) {
      seen$m0 <- allD$season
      seen$m0_exclude <- exclude
      list(best_params = list(ok = TRUE), tuning = list())
    },
    build_m1 = function(allD, ...) {
      seen$m1 <- c(seen$m1, list(allD$season))
      list(ref = list(), hyper = list(), m1_params = list())
    },
    tune_m1 = function(allD, ...) {
      seen$m1_tune <- allD$season
      list(best = data.frame(), scores = data.frame(), grid = data.frame())
    },
    build_m2 = function(allD, grid, holdout_season, ...) {
      seen$m2 <- allD$season
      seen$m2_holdout <- holdout_season
      list(
        best_spec = winner, best_spec_id = "winner",
        summary = data.frame(spec_id = "winner", bernoulli_nll = .4),
        grid = grid
      )
    },
    train_m2 = function(allD, best_spec, exclude, ...) {
      seen$final <- allD$season
      seen$final_exclude <- exclude
      list(spec = best_spec, fit = "fit")
    },
    assemble_kit = function(...) list(ready = TRUE),
    .package = "PAGe"
  )

  result <- PAGe::train_pipeline(
    workflow_surveillance(c("2024-25", "2025-26"), c(1L, 1L)),
    mode = "retune", n_cores = 1L, verbose = FALSE,
    m0_grid = data.frame(p_thr = .005),
    m1_grid = data.frame(k_ref = 25L)
  )

  expect_false("2025-26" %in% seen$m0)
  expect_false(any(vapply(seen$m1, function(x) "2025-26" %in% x, logical(1))))
  expect_false("2025-26" %in% seen$m1_tune)
  expect_false("2025-26" %in% seen$m2)
  expect_false("2025-26" %in% seen$final)
  expect_true("2025-26" %in% seen$m0_exclude)
  expect_true("2025-26" %in% seen$final_exclude)
  expect_identical(seen$m2_holdout, "2025-26")
  expect_false(result$holdout$released)
})

test_that("malformed promotion reports fail closed", {
  expect_error(
    PAGe::train_pipeline(
      workflow_surveillance("2025-26", 1L), mode = "refresh",
      promotion = list(pass = TRUE), verbose = FALSE
    ),
    "promotion"
  )
})

test_that("holdout release requires the locked canonical promotion contract", {
  allD <- workflow_surveillance("2025-26", 1L)
  candidate <- list(
    overall = data.frame(bernoulli_nll = 0.48),
    horizon = data.frame(lead = c("1", "2"), mae = c(0.103, 0.103)),
    phase = data.frame(phase = c("early", "late"), mae = c(0.105, 0.105))
  )
  incumbent <- list(
    overall = data.frame(bernoulli_nll = 0.50),
    horizon = data.frame(lead = c("1", "2"), mae = c(0.10, 0.10)),
    phase = data.frame(phase = c("early", "late"), mae = c(0.10, 0.10))
  )
  genuine <- PAGe::check_promotion(candidate, incumbent)

  released <- PAGe:::.resolve_holdout_release(allD, "2025-26", genuine)
  expect_true(released$released)

  fabricated <- list(
    pass = TRUE,
    gates = data.frame(
      gate = c("nll", "horizon", "phase"), pass = TRUE
    )
  )
  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", fabricated),
    "canonical check_promotion"
  )

  lenient <- genuine
  lenient$thresholds$min_nll_improvement <- 0.01
  lenient$gates$threshold[lenient$gates$gate == "nll"] <- 0.01
  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", lenient),
    "canonical check_promotion"
  )

  wrong_direction <- genuine
  wrong_direction$gates$direction[wrong_direction$gates$gate == "nll"] <- "at_most"
  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", wrong_direction),
    "canonical check_promotion"
  )

  wrong_gate <- genuine
  wrong_gate$gates$gate[wrong_gate$gates$gate == "phase"] <- "overall"
  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", wrong_gate),
    "canonical check_promotion"
  )

  inconsistent_value <- genuine
  inconsistent_value$gates$value[inconsistent_value$gates$gate == "nll"] <- 0.01
  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", inconsistent_value),
    "canonical check_promotion"
  )

  inconsistent_overall <- genuine
  inconsistent_overall$pass <- FALSE
  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", inconsistent_overall),
    "canonical check_promotion"
  )
})

test_that("retune exposes every approved final selection method", {
  expect_identical(
    eval(formals(PAGe::train_pipeline)$selection_method),
    c("min_nll", "one_se", "pareto")
  )
  expect_false(eval(formals(PAGe::train_pipeline)$racing))
  expect_identical(eval(formals(PAGe::build_m2)$holdout_season), "2025-26")
})

test_that("malformed prior tuning objects fail clearly", {
  expect_error(
    PAGe::plan_m2_grid(list(summary = data.frame(spec_id = "x"))),
    "both `summary` and `grid`"
  )
  expect_error(
    PAGe::plan_m2_grid(list(summary = "bad", grid = data.frame())),
    "data frames"
  )
})
