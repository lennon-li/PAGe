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
    fit_m0 = function(data, selection, config, ...) {
      calls$m0_config <- config
      list(stage = "m0", status = "draft", config = config)
    },
    freeze_m0 = function(fit, ...) {
      fit$status <- "frozen"
      fit
    },
    fit_m1 = function(data, selection, m0, config, ...) {
      calls$m1_config <- config
      list(stage = "m1", status = "draft", config = config)
    },
    freeze_m1 = function(fit, ...) {
      fit$status <- "frozen"
      fit
    },
    fit_m2 = function(data, selection, m0, m1, config, ...) {
      calls$best_spec <- config
      list(stage = "m2", status = "draft", config = config, spec = config)
    },
    freeze_m2 = function(fit, ...) {
      fit$status <- "frozen"
      fit
    },
    tune_m0 = function(...) stop("refresh must not tune M0"),
    tune_m1 = function(...) stop("refresh must not tune M1"),
    build_m2 = function(...) stop("refresh must not tune M2"),
    assemble_kit = function(...) list(ready = TRUE),
    .package = "PAGe"
  )

  result <- PAGe::train_pipeline(
    workflow_surveillance(c("2024-25", "2025-26"), c(1L, 1L)),
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
  expect_error(
    PAGe::train_pipeline(
      workflow_surveillance(c("2024-25", "2025-26"), c(1L, 1L)),
      mode = "refresh", previous_results = list(best_spec = prior_spec),
      promotion = failed, n_cores = 1L, verbose = FALSE
    ),
    "verified promotion evidence"
  )
})

test_that("refresh falls back to locked v16 for an incompatible prior best", {
  calls <- new.env(parent = emptyenv())

  local_mocked_bindings(
    fit_m0 = function(data, selection, config, ...) {
      list(stage = "m0", status = "draft", config = config)
    },
    freeze_m0 = function(fit, ...) {
      fit$status <- "frozen"
      fit
    },
    fit_m1 = function(data, selection, m0, config, ...) {
      list(stage = "m1", status = "draft", config = config)
    },
    freeze_m1 = function(fit, ...) {
      fit$status <- "frozen"
      fit
    },
    fit_m2 = function(data, selection, m0, m1, config, ...) {
      calls$best_spec <- config
      list(stage = "m2", status = "draft", config = config, spec = config)
    },
    freeze_m2 = function(fit, ...) {
      fit$status <- "frozen"
      fit
    },
    assemble_kit = function(...) list(ready = TRUE),
    .package = "PAGe"
  )

  PAGe::train_pipeline(
    workflow_surveillance(c("2024-25", "2025-26"), c(1L, 1L)),
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
  winner <- PAGe:::.default_m2_spec()
  winner$k_f <- 5L

  local_mocked_bindings(
    tune_m0 = function(allD, ..., selection = NULL) {
      calls$m0_seasons <- selection$training_seasons
      structure(
        list(
          best_params = list(ok = TRUE),
          tuning = list(folds = stats::setNames(
            as.list(selection$training_seasons),
            selection$training_seasons
          )),
          aligned = data.frame(),
          seasons_used = selection$training_seasons,
          manual_labels = c("2024-25" = 15L),
          flag_args = list(),
          selection = selection,
          data_id = "x"
        ),
        class = c("page_m0_tuning", "list")
      )
    },
    validate_m0_tuning = function(x, ...) invisible(x),
    fit_m0 = function(data, selection, config, ...) {
      structure(
        list(
          aligned = data.frame(),
          seasons_used = selection$training_seasons,
          best_params = config,
          manual_labels = c("2024-25" = 15L),
          flag_args = list(),
          stage = "m0", status = "draft",
          selection = selection, config = config,
          upstream_ids = NULL, data_id = "x",
          artifact_id = "m0_a"
        ),
        class = c("page_m0_fit", "list")
      )
    },
    freeze_m0 = function(fit, tuning = NULL, ...) {
      force(fit)
      fit$status <- "frozen"
      fit
    },
    tune_m1 = function(allD, m0, ..., selection = NULL) {
      calls$m1_tune_seasons <- selection$training_seasons
      structure(
        list(
          scores = data.frame(
            spec_id = "s1", mae_weibull = 1,
            n_seasons = length(selection$training_seasons)
          ),
          best = data.frame(
            k_ref = 30L, multi_temperature = 0.20,
            align_rise_weight = 1, slope_window = 6L,
            slope_weight = 12, mae_weibull = 1
          ),
          selection = selection, data_id = "x"
        ),
        class = c("page_m1_tuning", "list")
      )
    },
    validate_m1_tuning = function(x, ...) invisible(x),
    fit_m1 = function(data, selection, m0, config, ...) {
      calls$m1_params <- config
      structure(
        list(
          ref = list(pred_df = data.frame(newWeek = 1:52, fit = 0)),
          hyper = list(scale = 1),
          aligned_train = data.frame(),
          m1_params = config,
          seasons_used = selection$training_seasons,
          stage = "m1", status = "draft",
          selection = selection, config = config,
          upstream_ids = list(m0 = "m0_a"),
          data_id = "x", artifact_id = "m1_a"
        ),
        class = c("page_m1_fit", "list")
      )
    },
    freeze_m1 = function(fit, tuning = NULL, ...) {
      force(fit)
      fit$status <- "frozen"
      fit
    },
    plan_m2_grid = function(...) {
      grid <- data.frame(
        delta = 0L, Kr = 1L, k_f = 5L, k_e = 2L,
        alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
        bias_alpha = 0.05, bias_beta = 0,
        spec_id = "winner", provenance = "incumbent:v16",
        stringsAsFactors = FALSE
      )
      calls$m2_grid <- grid
      grid
    },
    tune_m2 = function(data, selection, m0, m1, grid, ...) {
      calls$m2_seasons <- selection$training_seasons
      structure(
        list(
          grid = grid,
          best_spec_id = "winner",
          best_spec = winner,
          summary = data.frame(
            spec_id = "winner", bernoulli_nll = 0.4,
            n_seasons = length(selection$training_seasons)
          ),
          scores = do.call(rbind, lapply(selection$training_seasons, function(s) {
            data.frame(spec_id = "winner", season = s, bernoulli_nll = 0.4)
          })),
          selection = selection, data_id = "x"
        ),
        class = c("page_m2_tuning", "list")
      )
    },
    validate_m2_tuning = function(x, ...) invisible(x),
    select_m2_candidate = function(results, method = "min_nll") {
      list(
        method = method,
        selected_spec_id = "winner",
        selected_spec = winner,
        selected = results$summary[1L, , drop = FALSE],
        pareto_set = NULL, one_se_threshold = NULL,
        candidates = results$summary
      )
    },
    fit_m2 = function(data, selection, m0, m1, config, ...) {
      calls$best_spec <- config
      calls$seasons <- selection$training_seasons
      structure(
        list(
          fit = structure(list(model = data.frame()), class = "gam"),
          feature_ranges = list(),
          m1_train_preds = data.frame(),
          spec = config,
          training_seasons = selection$training_seasons,
          stage = "m2", status = "draft",
          selection = selection, config = config,
          upstream_ids = list(m0 = "m0_a", m1 = "m1_a"),
          data_id = "x", artifact_id = "m2_a"
        ),
        class = c("page_m2_fit", "list")
      )
    },
    freeze_m2 = function(fit, tuning = NULL, ...) {
      force(fit)
      fit$status <- "frozen"
      fit
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

  training_data <- workflow_surveillance(c("2024-25", "2025-26"), c(1L, 1L))
  evidence <- training_promotion_evidence(training_data, passing_promotion)
  result <- PAGe::train_pipeline(
    training_data,
    mode = "retune",
    promotion = evidence,
    loso_seasons = "alternating",
    n_cores = 1L,
    verbose = FALSE,
    m0_grid = data.frame(p_thr = 0.005),
    m1_grid = data.frame(k_ref = 25L)
  )

  expect_identical(result$mode, "retune")
  expect_equal(calls$m1_params$k_ref, 30L)
  expect_equal(calls$m1_params$slope_weight, 12)
  expect_identical(calls$best_spec, winner)
  expect_false("2025-26" %in% calls$m0_seasons)
  expect_false("2025-26" %in% calls$m1_tune_seasons)
  expect_false("2025-26" %in% calls$m2_seasons)
  expect_false("2025-26" %in% calls$seasons)
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
    tune_m0 = function(allD, ..., selection = NULL) {
      seen$m0 <- selection$training_seasons
      structure(
        list(
          best_params = list(ok = TRUE),
          tuning = list(folds = stats::setNames(
            as.list(selection$training_seasons),
            selection$training_seasons
          )),
          aligned = data.frame(),
          seasons_used = selection$training_seasons,
          manual_labels = c("2024-25" = 15L),
          flag_args = list(),
          selection = selection, data_id = "x"
        ),
        class = c("page_m0_tuning", "list")
      )
    },
    validate_m0_tuning = function(x, ...) invisible(x),
    fit_m0 = function(data, selection, config, ...) {
      structure(
        list(
          aligned = data.frame(),
          seasons_used = selection$training_seasons,
          best_params = config,
          manual_labels = c("2024-25" = 15L),
          flag_args = list(),
          stage = "m0", status = "draft",
          selection = selection, config = config,
          upstream_ids = NULL, data_id = "x",
          artifact_id = "m0_a"
        ),
        class = c("page_m0_fit", "list")
      )
    },
    freeze_m0 = function(fit, tuning = NULL, ...) {
      force(fit)
      fit$status <- "frozen"
      fit
    },
    tune_m1 = function(allD, m0, ..., selection = NULL) {
      seen$m1_tune <- selection$training_seasons
      structure(
        list(
          scores = data.frame(
            spec_id = "s1", mae_weibull = 0.5,
            n_seasons = length(selection$training_seasons)
          ),
          best = data.frame(
            k_ref = 3L, multi_temperature = 0.25,
            align_rise_weight = 1, slope_window = 6L,
            slope_weight = 8, mae_weibull = 0.5
          ),
          selection = selection, data_id = "x"
        ),
        class = c("page_m1_tuning", "list")
      )
    },
    validate_m1_tuning = function(x, ...) invisible(x),
    fit_m1 = function(data, selection, m0, config, ...) {
      structure(
        list(
          ref = list(pred_df = data.frame(newWeek = 1:52, fit = 0)),
          hyper = list(scale = 1),
          aligned_train = data.frame(),
          m1_params = config,
          seasons_used = selection$training_seasons,
          stage = "m1", status = "draft",
          selection = selection, config = config,
          upstream_ids = list(m0 = "m0_a"),
          data_id = "x", artifact_id = "m1_a"
        ),
        class = c("page_m1_fit", "list")
      )
    },
    freeze_m1 = function(fit, tuning = NULL, ...) {
      force(fit)
      fit$status <- "frozen"
      fit
    },
    plan_m2_grid = function(...) {
      data.frame(
        delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
        alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
        bias_alpha = 0.05, bias_beta = 0,
        spec_id = "sp1", provenance = "inc",
        stringsAsFactors = FALSE
      )
    },
    tune_m2 = function(data, selection, m0, m1, grid, ...) {
      seen$m2 <- selection$training_seasons
      structure(
        list(
          grid = grid,
          best_spec_id = "sp1",
          best_spec = winner,
          summary = data.frame(
            spec_id = "sp1", bernoulli_nll = 0.4,
            n_seasons = length(selection$training_seasons)
          ),
          scores = do.call(rbind, lapply(selection$training_seasons, function(s) {
            data.frame(spec_id = "sp1", season = s, bernoulli_nll = 0.4)
          })),
          selection = selection, data_id = "x"
        ),
        class = c("page_m2_tuning", "list")
      )
    },
    validate_m2_tuning = function(x, ...) invisible(x),
    select_m2_candidate = function(results, method = "min_nll") {
      list(
        method = method,
        selected_spec_id = "sp1",
        selected_spec = winner,
        selected = results$summary[1L, , drop = FALSE],
        pareto_set = NULL, one_se_threshold = NULL,
        candidates = results$summary
      )
    },
    fit_m2 = function(data, selection, m0, m1, config, ...) {
      seen$final <- selection$training_seasons
      structure(
        list(
          fit = structure(list(model = data.frame()), class = "gam"),
          feature_ranges = list(),
          m1_train_preds = data.frame(),
          spec = config,
          training_seasons = selection$training_seasons,
          stage = "m2", status = "draft",
          selection = selection, config = config,
          upstream_ids = list(m0 = "m0_a", m1 = "m1_a"),
          data_id = "x", artifact_id = "m2_a"
        ),
        class = c("page_m2_fit", "list")
      )
    },
    freeze_m2 = function(fit, tuning = NULL, ...) {
      force(fit)
      fit$status <- "frozen"
      fit
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
  expect_false("2025-26" %in% seen$m1_tune)
  expect_false("2025-26" %in% seen$m2)
  expect_false("2025-26" %in% seen$final)
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

  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", genuine),
    "verified promotion evidence"
  )
  evidence <- training_promotion_evidence(allD, genuine)
  released <- PAGe:::.resolve_holdout_release(allD, "2025-26", evidence)
  expect_true(released$released)

  fabricated <- list(
    pass = TRUE,
    gates = data.frame(
      gate = c("nll", "horizon", "phase"), pass = TRUE
    )
  )
  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", fabricated),
    "verified promotion evidence"
  )

  lenient <- genuine
  lenient$thresholds$min_nll_improvement <- 0.01
  lenient$gates$threshold[lenient$gates$gate == "nll"] <- 0.01
  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", lenient),
    "verified promotion evidence"
  )

  wrong_direction <- genuine
  wrong_direction$gates$direction[wrong_direction$gates$gate == "nll"] <- "at_most"
  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", wrong_direction),
    "verified promotion evidence"
  )

  wrong_gate <- genuine
  wrong_gate$gates$gate[wrong_gate$gates$gate == "phase"] <- "overall"
  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", wrong_gate),
    "verified promotion evidence"
  )

  inconsistent_value <- genuine
  inconsistent_value$gates$value[inconsistent_value$gates$gate == "nll"] <- 0.01
  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", inconsistent_value),
    "verified promotion evidence"
  )

  inconsistent_overall <- genuine
  inconsistent_overall$pass <- FALSE
  expect_error(
    PAGe:::.resolve_holdout_release(allD, "2025-26", inconsistent_overall),
    "verified promotion evidence"
  )
})

test_that("promotion evidence verifies every bound artifact hash", {
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
  fixture <- training_promotion_fixture(allD, PAGe::check_promotion(candidate, incumbent))
  withr::defer(unlink(fixture$root, recursive = TRUE))

  evidence <- do.call(PAGe::verify_promotion_evidence, fixture$args)
  expect_s3_class(evidence, "page_verified_promotion_evidence")

  saveRDS(list(tampered = TRUE), fixture$args$candidate_path)
  expect_error(
    do.call(PAGe::verify_promotion_evidence, fixture$args),
    "candidate.*SHA-256"
  )
})

test_that("promotion evidence verifies kit identity and pre-holdout training", {
  allD <- workflow_surveillance("2025-26", 1L)
  report <- PAGe::check_promotion(
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

  leaked <- training_promotion_fixture(allD, report)
  withr::defer(unlink(leaked$root, recursive = TRUE))
  candidate <- readRDS(leaked$args$candidate_path)
  candidate$m2_production$training_seasons <- c("2024-25", "2025-26")
  saveRDS(candidate, leaked$args$candidate_path)
  leaked <- training_rebind_fixture(leaked)
  expect_error(
    do.call(PAGe::verify_promotion_evidence, leaked$args),
    "includes the holdout"
  )

  mismatched <- training_promotion_fixture(allD, report)
  withr::defer(unlink(mismatched$root, recursive = TRUE))
  candidate <- readRDS(mismatched$args$candidate_path)
  candidate$m2_production$best_spec_id <- "different-candidate"
  saveRDS(candidate, mismatched$args$candidate_path)
  mismatched <- training_rebind_fixture(mismatched)
  expect_error(
    do.call(PAGe::verify_promotion_evidence, mismatched$args),
    "spec identity"
  )
})

test_that("legacy incumbent identity requires an explicit compatibility option", {
  allD <- workflow_surveillance("2025-26", 1L)
  report <- PAGe::check_promotion(
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
  fixture <- training_promotion_fixture(allD, report)
  withr::defer(unlink(fixture$root, recursive = TRUE))
  saveRDS(
    list(m2 = list(
      best_spec_id = "incumbent",
      training_seasons = "2024-25"
    )),
    fixture$args$incumbent_path
  )
  fixture <- training_rebind_fixture(fixture)

  expect_error(
    do.call(PAGe::verify_promotion_evidence, fixture$args),
    "legacy `m2`"
  )
  fixture$args$kit_compatibility <- "legacy_m2"
  expect_warning(
    evidence <- do.call(PAGe::verify_promotion_evidence, fixture$args),
    "legacy `m2` identity"
  )
  expect_s3_class(evidence, "page_verified_promotion_evidence")
})

test_that("retune exposes every approved final selection method", {
  expect_identical(
    eval(formals(PAGe::train_pipeline)$selection_method),
    c("min_nll", "one_se", "pareto")
  )
  expect_false(eval(formals(PAGe::train_pipeline)$racing))
  expect_identical(eval(formals(PAGe::build_m2)$holdout_season), "2025-26")
  expect_identical(eval(formals(PAGe::build_m2)$bias_alpha), 0.05)
  expect_identical(eval(formals(PAGe::stage2_make_spec)$bias_alpha), 0.05)
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

test_that("refresh governed path produces frozen chain and governed kit", {
  allD <- workflow_surveillance(c("2023-24", "2024-25", "2025-26"), c(1L, 1L, 1L))
  calls <- new.env(parent = emptyenv())

  local_mocked_bindings(
    build_m0 = function(data, ...) {
      calls$m0_seasons <- unique(as.character(data$season))
      list(
        aligned = data, seasons_used = calls$m0_seasons,
        best_params = PAGe:::.default_m0_params(),
        manual_labels = stats::setNames(
          rep(20L, length(calls$m0_seasons)), calls$m0_seasons
        ),
        flag_args = list(p_thresh = 0.01)
      )
    },
    build_m1 = function(data, m0, ...) {
      calls$m1_seasons <- unique(as.character(data$season))
      list(
        ref = list(anchorWeek = 20L, pred_df = data.frame(newWeek = 1:52, fit = 0)),
        hyper = list(scale = 1),
        aligned_train = data,
        m1_params = PAGe:::.default_m1_params(),
        seasons_used = calls$m1_seasons
      )
    },
    train_m2 = function(data, m0, m1, best_spec, ...) {
      calls$m2_seasons <- unique(as.character(data$season))
      calls$m2_spec <- best_spec
      list(
        fit = structure(list(model = data.frame(
          logit_f_eff = 0, z_ema = 0, lead = factor("h1")
        )), class = "gam"),
        feature_ranges = list(),
        m1_train_preds = data.frame(),
        spec = best_spec,
        training_seasons = calls$m2_seasons
      )
    },
    tune_m0 = function(...) stop("refresh must not tune M0"),
    tune_m1 = function(...) stop("refresh must not tune M1"),
    build_m2 = function(...) stop("refresh must not tune M2"),
    .package = "PAGe"
  )

  result <- PAGe::train_pipeline(
    allD,
    mode = "refresh",
    prospective_holdout = "2025-26",
    n_cores = 1L,
    verbose = FALSE
  )

  expect_identical(result$mode, "refresh")
  expect_null(result$tuning)
  expect_false(result$holdout$released)
  expect_false("2025-26" %in% calls$m0_seasons)
  expect_false("2025-26" %in% calls$m1_seasons)
  expect_false("2025-26" %in% calls$m2_seasons)
  expect_true(is.list(result$kit))
  expect_s3_class(result$kit$season_selection, "page_season_selection")
  expect_named(result$kit$stage_artifact_ids, c("m0", "m1", "m2"))
  expect_false("2025-26" %in% result$kit$season_selection$training_seasons)
  expect_true("2025-26" %in% result$kit$season_selection$holdout_seasons)
  expect_true(is.list(result$components$m0))
  expect_false(inherits(result$components$m0, "page_m0_fit"))
})

test_that("refresh governed path rejects overlapping season sets", {
  allD <- workflow_surveillance(c("2024-25", "2025-26"), c(1L, 1L))

  expect_error(
    PAGe::train_pipeline(
      allD,
      mode = "refresh",
      exclude = "2024-25",
      prospective_holdout = "2025-26",
      n_cores = 1L,
      verbose = FALSE
    ),
    "at least one trainable season"
  )
})
