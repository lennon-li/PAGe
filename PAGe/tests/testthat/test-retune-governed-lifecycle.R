synthetic_allD <- function() {
  seasons <- c("2012-13", "2013-14", "2014-15", "2025-26")
  do.call(rbind, lapply(seasons, function(s) {
    data.frame(
      season = s, weekF = 1:10,
      y = sample(0:20, 10, replace = TRUE),
      N = rep(100L, 10),
      marker = letters[1:10],
      stringsAsFactors = FALSE
    )
  }))
}

fake_selection <- function(allD, holdout = "2025-26") {
  seasons <- unique(as.character(allD$season))
  training <- setdiff(seasons, holdout)
  validate_season_selection(
    allD,
    training_seasons = training,
    holdout_seasons = if (!is.null(holdout)) holdout else character(0)
  )
}

fake_m0_tuning <- function(selection) {
  structure(
    list(
      best_params = list(cls_thr = 0.26, p_thr = 0.005),
      tuning = list(folds = stats::setNames(
        as.list(selection$training_seasons),
        selection$training_seasons
      )),
      aligned = data.frame(),
      seasons_used = selection$training_seasons,
      manual_labels = c("2012-13" = 15L),
      flag_args = list(),
      selection = selection,
      data_id = "fake_data_id"
    ),
    class = c("page_m0_tuning", "list")
  )
}

fake_m0_fit <- function(selection, status = "frozen") {
  structure(
    list(
      aligned = data.frame(),
      seasons_used = selection$training_seasons,
      best_params = list(cls_thr = 0.26, p_thr = 0.005),
      manual_labels = c("2012-13" = 15L),
      flag_args = list(),
      stage = "m0",
      status = status,
      selection = selection,
      config = list(cls_thr = 0.26, p_thr = 0.005),
      upstream_ids = NULL,
      data_id = "fake_data_id",
      artifact_id = "m0_fake_artifact"
    ),
    class = c("page_m0_fit", "list")
  )
}

fake_m1_tuning <- function(selection) {
  structure(
    list(
      scores = data.frame(
        spec_id = "s1", mae_weibull = 0.5, n_seasons = length(selection$training_seasons),
        stringsAsFactors = FALSE
      ),
      best = data.frame(
        k_ref = 3L, multi_temperature = 0.25,
        align_rise_weight = 1, slope_window = 6L, slope_weight = 8,
        mae_weibull = 0.5,
        stringsAsFactors = FALSE
      ),
      grid = data.frame(
        k_ref = c(2L, 3L, 4L),
        multi_temperature = 0.25,
        align_rise_weight = 1,
        slope_window = 6L,
        slope_weight = c(4, 8, 12),
        stringsAsFactors = FALSE
      ),
      selection = selection,
      data_id = "fake_data_id"
    ),
    class = c("page_m1_tuning", "list")
  )
}

fake_m1_fit <- function(selection, m0_id = "m0_fake_artifact", status = "frozen") {
  structure(
    list(
      ref = list(pred_df = data.frame(newWeek = 1:52, fit = 0)),
      hyper = list(scale = 1),
      aligned_train = data.frame(),
      m1_params = list(k_ref = 3L, temperature = 0.25),
      seasons_used = selection$training_seasons,
      stage = "m1",
      status = status,
      selection = selection,
      config = list(k_ref = 3L, temperature = 0.25),
      upstream_ids = list(m0 = m0_id),
      data_id = "fake_data_id",
      artifact_id = "m1_fake_artifact"
    ),
    class = c("page_m1_fit", "list")
  )
}

fake_m2_tuning <- function(selection) {
  grid <- data.frame(
    delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
    alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
    bias_alpha = 0.05, bias_beta = 0,
    spec_id = "d+0_Kr1_kf4_ke2_as0.15_kr0_kde0_ksp6_ba0.05_bb0",
    provenance = "incumbent:v16",
    stringsAsFactors = FALSE
  )
  structure(
    list(
      grid = grid,
      best_spec_id = grid$spec_id,
      best_spec = as.list(grid[1L, 1:10]),
      summary = data.frame(
        spec_id = grid$spec_id, bernoulli_nll = 0.3,
        n_seasons = length(selection$training_seasons),
        stringsAsFactors = FALSE
      ),
      scores = do.call(rbind, lapply(selection$training_seasons, function(s) {
        data.frame(
          spec_id = grid$spec_id, season = s,
          bernoulli_nll = 0.3, stringsAsFactors = FALSE
        )
      })),
      selection = selection,
      data_id = "fake_data_id"
    ),
    class = c("page_m2_tuning", "list")
  )
}

fake_m2_fit <- function(selection, status = "frozen") {
  structure(
    list(
      fit = structure(list(model = data.frame()), class = "gam"),
      feature_ranges = list(),
      m1_train_preds = data.frame(),
      spec = list(
        delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
        alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
        bias_alpha = 0.05, bias_beta = 0
      ),
      training_seasons = selection$training_seasons,
      stage = "m2",
      status = status,
      selection = selection,
      config = list(
        delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
        alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
        bias_alpha = 0.05, bias_beta = 0
      ),
      upstream_ids = list(m0 = "m0_fake_artifact", m1 = "m1_fake_artifact"),
      data_id = "fake_data_id",
      artifact_id = "m2_fake_artifact"
    ),
    class = c("page_m2_fit", "list")
  )
}

test_that("retune calls governed lifecycle in M0 -> M1 -> M2 order", {
  allD <- synthetic_allD()
  sel <- fake_selection(allD)
  call_log <- character(0)
  m0_boundary_checks <- logical(0)
  m1_boundary_checks <- logical(0)

  local_mocked_bindings(
    prepare_surveillance_data = function(x, ...) x,
    .resolve_holdout_release = function(allD, holdout_season, promotion) {
      list(
        season = holdout_season, present = TRUE, released = FALSE,
        status = "held_out", promotion_pass = NULL
      )
    },
    tune_m0 = function(allD, ..., selection = NULL) {
      call_log <<- c(call_log, "tune_m0")
      fake_m0_tuning(selection)
    },
    validate_m0_tuning = function(x, grid = NULL, check_boundaries = FALSE, ...) {
      call_log <<- c(call_log, "validate_m0_tuning")
      m0_boundary_checks <<- c(m0_boundary_checks, check_boundaries)
      invisible(x)
    },
    fit_m0 = function(data, selection, config, ...) {
      call_log <<- c(call_log, "fit_m0")
      fake_m0_fit(selection, status = "draft")
    },
    freeze_m0 = function(fit, tuning = NULL, ...) {
      force(fit)
      call_log <<- c(call_log, "freeze_m0")
      fit$status <- "frozen"
      fit
    },
    tune_m1 = function(allD, m0, ..., selection = NULL) {
      call_log <<- c(call_log, "tune_m1")
      fake_m1_tuning(selection)
    },
    validate_m1_tuning = function(x, check_boundaries = FALSE, ...) {
      call_log <<- c(call_log, "validate_m1_tuning")
      m1_boundary_checks <<- c(m1_boundary_checks, check_boundaries)
      invisible(x)
    },
    fit_m1 = function(data, selection, m0, config, ...) {
      call_log <<- c(call_log, "fit_m1")
      fake_m1_fit(selection, status = "draft")
    },
    freeze_m1 = function(fit, tuning = NULL, ...) {
      force(fit)
      call_log <<- c(call_log, "freeze_m1")
      fit$status <- "frozen"
      fit
    },
    plan_m2_grid = function(...) {
      call_log <<- c(call_log, "plan_m2_grid")
      data.frame(
        delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
        alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
        bias_alpha = 0.05, bias_beta = 0,
        spec_id = "d+0_Kr1_kf4_ke2_as0.15_kr0_kde0_ksp6_ba0.05_bb0",
        provenance = "incumbent:v16",
        stringsAsFactors = FALSE
      )
    },
    tune_m2 = function(data, selection, m0, m1, grid, ...) {
      call_log <<- c(call_log, "tune_m2")
      fake_m2_tuning(selection)
    },
    validate_m2_tuning = function(x, ...) {
      call_log <<- c(call_log, "validate_m2_tuning")
      invisible(x)
    },
    select_m2_candidate = function(results, method = "min_nll") {
      call_log <<- c(call_log, "select_m2_candidate")
      list(
        method = method,
        selected_spec_id = results$best_spec_id,
        selected_spec = results$best_spec,
        selected = results$summary[1L, , drop = FALSE],
        pareto_set = NULL, one_se_threshold = NULL,
        candidates = results$summary
      )
    },
    fit_m2 = function(data, selection, m0, m1, config, ...) {
      call_log <<- c(call_log, "fit_m2")
      fake_m2_fit(selection, status = "draft")
    },
    freeze_m2 = function(fit, tuning = NULL, ...) {
      force(fit)
      call_log <<- c(call_log, "freeze_m2")
      fit$status <- "frozen"
      fit
    },
    assemble_kit = function(m0, m1, m2_model, ...) {
      call_log <<- c(call_log, "assemble_kit")
      list(kit = TRUE)
    },
    .package = "PAGe"
  )

  result <- PAGe::train_pipeline(
    allD,
    mode = "retune",
    exclude = character(0),
    prospective_holdout = "2025-26",
    n_cores = 1L, verbose = FALSE
  )

  expect_s3_class(result, "page_training_result")
  expect_identical(result$mode, "retune")

  m0_idx <- match(c("tune_m0", "validate_m0_tuning", "fit_m0", "freeze_m0"), call_log)
  m1_idx <- match(c("tune_m1", "validate_m1_tuning", "fit_m1", "freeze_m1"), call_log)
  m2_idx <- match(c("tune_m2", "validate_m2_tuning", "fit_m2", "freeze_m2"), call_log)

  expect_true(all(!is.na(m0_idx)), info = "All M0 lifecycle steps called")
  expect_true(all(!is.na(m1_idx)), info = "All M1 lifecycle steps called")
  expect_true(all(!is.na(m2_idx)), info = "All M2 lifecycle steps called")

  expect_true(max(m0_idx) < min(m1_idx), info = "M0 completes before M1 starts")
  expect_true(max(m1_idx) < min(m2_idx), info = "M1 completes before M2 starts")
  expect_true(max(m2_idx) < match("assemble_kit", call_log),
    info = "M2 completes before assemble_kit"
  )

  expect_true(diff(m0_idx[1:2]) > 0L, info = "tune_m0 before validate_m0_tuning")
  expect_true(diff(m0_idx[2:3]) > 0L, info = "validate before fit_m0")
  expect_true(diff(m0_idx[3:4]) > 0L, info = "fit_m0 before freeze_m0")
  expect_true(all(m0_boundary_checks), info = "M0 boundary gate is enabled")
  expect_true(all(m1_boundary_checks), info = "M1 boundary gate is enabled")
})

test_that("retune excludes holdout season from training selection", {
  allD <- synthetic_allD()
  captured_selection <- NULL

  local_mocked_bindings(
    prepare_surveillance_data = function(x, ...) x,
    .resolve_holdout_release = function(allD, holdout_season, promotion) {
      list(
        season = holdout_season, present = TRUE, released = FALSE,
        status = "held_out", promotion_pass = NULL
      )
    },
    tune_m0 = function(allD, ..., selection = NULL) {
      captured_selection <<- selection
      fake_m0_tuning(selection)
    },
    validate_m0_tuning = function(x, ...) invisible(x),
    fit_m0 = function(data, selection, config, ...) {
      fake_m0_fit(selection, status = "draft")
    },
    freeze_m0 = function(fit, tuning = NULL, ...) {
      fit$status <- "frozen"
      fit
    },
    tune_m1 = function(allD, m0, ..., selection = NULL) {
      fake_m1_tuning(selection)
    },
    validate_m1_tuning = function(x, ...) invisible(x),
    fit_m1 = function(data, selection, m0, config, ...) {
      fake_m1_fit(selection, status = "draft")
    },
    freeze_m1 = function(fit, tuning = NULL, ...) {
      fit$status <- "frozen"
      fit
    },
    plan_m2_grid = function(...) {
      data.frame(
        delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
        alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
        bias_alpha = 0.05, bias_beta = 0,
        spec_id = "d+0_Kr1_kf4_ke2_as0.15_kr0_kde0_ksp6_ba0.05_bb0",
        provenance = "incumbent:v16",
        stringsAsFactors = FALSE
      )
    },
    tune_m2 = function(data, selection, m0, m1, grid, ...) {
      fake_m2_tuning(selection)
    },
    validate_m2_tuning = function(x, ...) invisible(x),
    select_m2_candidate = function(results, method = "min_nll") {
      list(
        method = method,
        selected_spec_id = results$best_spec_id,
        selected_spec = results$best_spec,
        selected = results$summary[1L, , drop = FALSE],
        pareto_set = NULL, one_se_threshold = NULL,
        candidates = results$summary
      )
    },
    fit_m2 = function(data, selection, m0, m1, config, ...) {
      fake_m2_fit(selection, status = "draft")
    },
    freeze_m2 = function(fit, tuning = NULL, ...) {
      fit$status <- "frozen"
      fit
    },
    assemble_kit = function(m0, m1, m2_model, ...) list(kit = TRUE),
    .package = "PAGe"
  )

  result <- PAGe::train_pipeline(
    allD,
    mode = "retune",
    exclude = character(0),
    prospective_holdout = "2025-26",
    n_cores = 1L, verbose = FALSE
  )

  expect_false("2025-26" %in% captured_selection$training_seasons)
  expect_true("2025-26" %in% captured_selection$holdout_seasons)
  expect_identical(result$holdout$status, "held_out")
  expect_true("2025-26" %in% result$holdout$effective_exclude)
})

test_that("retune racing=TRUE routes full_evaluator through governed tune_m2", {
  allD <- synthetic_allD()
  racing_full_eval_calls <- 0L

  local_mocked_bindings(
    prepare_surveillance_data = function(x, ...) x,
    .resolve_holdout_release = function(allD, holdout_season, promotion) {
      list(
        season = holdout_season, present = TRUE, released = FALSE,
        status = "held_out", promotion_pass = NULL
      )
    },
    tune_m0 = function(allD, ..., selection = NULL) fake_m0_tuning(selection),
    validate_m0_tuning = function(x, ...) invisible(x),
    fit_m0 = function(data, selection, config, ...) fake_m0_fit(selection, status = "draft"),
    freeze_m0 = function(fit, tuning = NULL, ...) {
      fit$status <- "frozen"
      fit
    },
    tune_m1 = function(allD, m0, ..., selection = NULL) fake_m1_tuning(selection),
    validate_m1_tuning = function(x, ...) invisible(x),
    fit_m1 = function(data, selection, m0, config, ...) fake_m1_fit(selection, status = "draft"),
    freeze_m1 = function(fit, tuning = NULL, ...) {
      fit$status <- "frozen"
      fit
    },
    plan_m2_grid = function(...) {
      data.frame(
        delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
        alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
        bias_alpha = 0.05, bias_beta = 0,
        spec_id = "d+0_Kr1_kf4_ke2_as0.15_kr0_kde0_ksp6_ba0.05_bb0",
        provenance = "incumbent:v16",
        stringsAsFactors = FALSE
      )
    },
    tune_m2 = function(data, selection, m0, m1, grid, ...) {
      racing_full_eval_calls <<- racing_full_eval_calls + 1L
      fake_m2_tuning(selection)
    },
    validate_m2_tuning = function(x, ...) invisible(x),
    select_m2_candidate = function(results, method = "min_nll") {
      list(
        method = method,
        selected_spec_id = results$best_spec_id,
        selected_spec = results$best_spec,
        selected = results$summary[1L, , drop = FALSE],
        pareto_set = NULL, one_se_threshold = NULL,
        candidates = results$summary
      )
    },
    fit_m2 = function(data, selection, m0, m1, config, ...) fake_m2_fit(selection, status = "draft"),
    freeze_m2 = function(fit, tuning = NULL, ...) {
      fit$status <- "frozen"
      fit
    },
    assemble_kit = function(m0, m1, m2_model, ...) list(kit = TRUE),
    race_m2_candidates = function(grid, evaluator, stages, min_survivors, full_evaluator, ...) {
      partial <- evaluator(grid, stage = stages[1L])
      survivors <- grid
      list(
        stages = list(list(stage = stages[1L], survivors = grid$spec_id)),
        survivors = survivors,
        final = full_evaluator(survivors),
        final_evaluation = "full_nested_loso"
      )
    },
    .package = "PAGe"
  )

  mock_evaluator <- function(grid, stage, ...) {
    data.frame(
      spec_id = grid$spec_id,
      bernoulli_nll = rep(0.3, nrow(grid)),
      stringsAsFactors = FALSE
    )
  }

  result <- PAGe::train_pipeline(
    allD,
    mode = "retune",
    exclude = character(0),
    prospective_holdout = "2025-26",
    n_cores = 1L, verbose = FALSE,
    racing = TRUE,
    racing_evaluator = mock_evaluator
  )

  expect_s3_class(result, "page_training_result")
  expect_true(racing_full_eval_calls > 0L,
    info = "full_evaluator routed through governed tune_m2"
  )
  expect_false(is.null(result$racing))
  expect_identical(result$racing$final_evaluation, "full_nested_loso")
})

test_that("retune preserves page_training_result field shape", {
  allD <- synthetic_allD()

  local_mocked_bindings(
    prepare_surveillance_data = function(x, ...) x,
    .resolve_holdout_release = function(allD, holdout_season, promotion) {
      list(
        season = holdout_season, present = TRUE, released = FALSE,
        status = "held_out", promotion_pass = NULL
      )
    },
    tune_m0 = function(allD, ..., selection = NULL) fake_m0_tuning(selection),
    validate_m0_tuning = function(x, ...) invisible(x),
    fit_m0 = function(data, selection, config, ...) fake_m0_fit(selection, status = "draft"),
    freeze_m0 = function(fit, tuning = NULL, ...) {
      fit$status <- "frozen"
      fit
    },
    tune_m1 = function(allD, m0, ..., selection = NULL) fake_m1_tuning(selection),
    validate_m1_tuning = function(x, ...) invisible(x),
    fit_m1 = function(data, selection, m0, config, ...) fake_m1_fit(selection, status = "draft"),
    freeze_m1 = function(fit, tuning = NULL, ...) {
      fit$status <- "frozen"
      fit
    },
    plan_m2_grid = function(...) {
      data.frame(
        delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L,
        alpha_state = 0.15, k_r = 0L, k_de = 0L, k_sp = 6L,
        bias_alpha = 0.05, bias_beta = 0,
        spec_id = "d+0_Kr1_kf4_ke2_as0.15_kr0_kde0_ksp6_ba0.05_bb0",
        provenance = "incumbent:v16",
        stringsAsFactors = FALSE
      )
    },
    tune_m2 = function(data, selection, m0, m1, grid, ...) fake_m2_tuning(selection),
    validate_m2_tuning = function(x, ...) invisible(x),
    select_m2_candidate = function(results, method = "min_nll") {
      list(
        method = method,
        selected_spec_id = results$best_spec_id,
        selected_spec = results$best_spec,
        selected = results$summary[1L, , drop = FALSE],
        pareto_set = NULL, one_se_threshold = NULL,
        candidates = results$summary
      )
    },
    fit_m2 = function(data, selection, m0, m1, config, ...) fake_m2_fit(selection, status = "draft"),
    freeze_m2 = function(fit, tuning = NULL, ...) {
      fit$status <- "frozen"
      fit
    },
    assemble_kit = function(m0, m1, m2_model, ...) list(kit = TRUE),
    .package = "PAGe"
  )

  result <- PAGe::train_pipeline(
    allD,
    mode = "retune",
    exclude = character(0),
    prospective_holdout = "2025-26",
    n_cores = 1L, verbose = FALSE
  )

  expected_fields <- c(
    "mode", "components", "tuning", "grid", "grid_provenance",
    "selection", "racing", "holdout", "kit"
  )
  expect_true(all(expected_fields %in% names(result)))

  expect_true(all(c("m0", "m1", "m2") %in% names(result$components)))
  expect_false(inherits(result$components$m0, "page_m0_fit"),
    info = "components are unwrapped payloads"
  )
  expect_null(result$components$m0$stage)
  expect_null(result$components$m0$artifact_id)

  expect_true(all(c("m0", "m1", "m2") %in% names(result$tuning)))
  expect_false(is.null(result$grid))
  expect_null(result$racing)
})
