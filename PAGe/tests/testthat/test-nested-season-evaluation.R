local_mocked_bindings <- function(..., .package = "PAGe") {
  bindings <- rlang::list2(...)
  frame <- parent.frame()
  ns_env <- rlang::ns_env(.package)
  if (!all(rlang::env_has(ns_env, names(bindings)))) {
    stop("Can't find binding for ", paste(names(bindings)[!rlang::env_has(ns_env, names(bindings))], collapse = ", "), call. = FALSE)
  }
  old_bindings <- mget(names(bindings), ns_env, inherits = FALSE)
  was_locked <- vapply(names(bindings), bindingIsLocked, logical(1), env = ns_env)
  unlock_names <- names(bindings)[was_locked]
  for (name in unlock_names) unlockBinding(name, ns_env)
  list2env(bindings, envir = ns_env)
  for (name in unlock_names) lockBinding(name, ns_env)
  restore <- function() {
    for (name in unlock_names) unlockBinding(name, ns_env)
    list2env(old_bindings, envir = ns_env)
    for (name in unlock_names) lockBinding(name, ns_env)
  }
  withr::defer(restore(), envir = frame)
  invisible(NULL)
}

nested_test_data <- function(seasons = c("A", "B", "C")) {
  data.frame(
    season = rep(seasons, each = 4L),
    weekF = rep(seq_len(4L), length(seasons)),
    y = rep(c(1, 2, 3, 4), length(seasons)),
    N = 10, nW_true = 4L
  )
}

nested_test_predictions <- function(season, m2 = 0.1) {
  data.frame(
    season = season,
    origin = c(1L, 1L, 2L, 2L),
    target = c(2L, 3L, 3L, 4L),
    horizon = c(1L, 2L, 1L, 2L),
    outcome = 0,
    m1_prediction = 0.2,
    m2_prediction = m2,
    t_since_target = c(1, 2, 13, 14),
    N_lead = 10
  )
}

nested_test_replay_predictions <- function(season, m2 = 0.1) {
  data.frame(
    season = season,
    weekF = c(1L, 1L, 2L, 2L),
    target_weekF = c(2L, 3L, 3L, 4L),
    lead = c(1L, 2L, 1L, 2L),
    p_obs = 0.2,
    p_hat = m2,
    t_since = c(0, 0, 1, 1),
    N_lead = 10
  )
}

test_that("nested evaluation rotates outer holdouts and aggregates seasons", {
  calls <- character()
  protocol <- list(
    weighting = list(
      early = 2, early_max_t_since = 12,
      pre_ignition = 0, late = 1, scoring = "legacy_0_12"
    ),
    adoption = list(
      min_gain = 0,
      min_gain_by_horizon = c("2" = 0),
      confidence = 0.5,
      max_season_degradation = 0
    )
  )
  local_mocked_bindings(
    run_outer_fold = function(data, holdout, exclude, ...) {
      calls <<- c(calls, holdout)
      structure(list(
        holdout = holdout,
        training = list(protocol = protocol),
        predictions = nested_test_predictions(holdout)
      ), class = c("page_outer_fold_result", "list"))
    }
  )

  directory <- tempfile("nested-evaluation-")
  result <- PAGe::nested_season_evaluation(
    nested_test_data(),
    holdouts = c("A", "B", "C"),
    exclude = character(),
    artifact_dir = directory,
    resume = FALSE
  )

  expect_s3_class(result, "page_nested_season_evaluation")
  expect_equal(calls, c("A", "B", "C"))
  expect_equal(result$primary$overall$n_seasons, 3L)
  expect_equal(unique(result$predictions$season), c("A", "B", "C"))
  expect_true(file.exists(file.path(
    directory, "outer_predictions_all_seasons.csv"
  )))
  expect_true(file.exists(file.path(
    directory, "nested_season_evaluation.rds"
  )))
})

test_that("outer training isolates labels and forwards primary weighting", {
  calls <- new.env(parent = emptyenv())
  calls$m2_round <- 0L
  selection_stub <- NULL
  settled_plan <- function(stage) {
    structure(list(
      stage = stage,
      final_boundary_report = data.frame(
        parameter = character(), decision = character()
      ),
      unresolved = data.frame(),
      next_grid = NULL,
      settled = TRUE
    ), class = "page_boundary_action_plan")
  }
  inner_rows <- do.call(rbind, lapply(c("A", "B"), function(season) {
    nested_test_predictions(season)
  }))

  local_mocked_bindings(
    tune_m0 = function(..., manual_labels, selection) {
      calls$m0_labels <- names(manual_labels)
      selection_stub <<- selection
      structure(list(
        best_params = list(ok = TRUE),
        tuning = list(best_params = list(ok = TRUE)),
        grid = data.frame(x = 1)
      ), class = "page_m0_tuning")
    },
    boundary_action_plan = function(tuning, stage, ...) {
      if (stage != "M2") {
        return(settled_plan(stage))
      }
      calls$m2_round <- calls$m2_round + 1L
      if (calls$m2_round == 1L) {
        return(structure(list(
          stage = "M2",
          final_boundary_report = data.frame(
            parameter = "k_z", decision = "expand_required"
          ),
          unresolved = data.frame(
            parameter = "k_z", decision = "expand_required"
          ),
          next_grid = data.frame(id = c("off", "expanded")),
          settled = FALSE
        ), class = "page_boundary_action_plan"))
      }
      settled_plan("M2")
    },
    validate_m0_tuning = function(x, ...) invisible(x),
    fit_m0 = function(...) list(stage = "m0"),
    freeze_m0 = function(x, ...) x,
    tune_m1 = function(..., manual_labels) {
      calls$m1_labels <- names(manual_labels)
      structure(list(
        best = data.frame(k_ref = 25L),
        grid = data.frame(k_ref = 25L)
      ), class = "page_m1_tuning")
    },
    select_m1_candidate = function(...) {
      list(
        selected = data.frame(k_ref = 25L)
      )
    },
    validate_m1_tuning = function(x, ...) invisible(x),
    .m1_params_from_tuning = function(...) list(k_ref = 25L),
    fit_m1 = function(...) list(stage = "m1"),
    freeze_m1 = function(x, ...) x,
    tune_m2 = function(..., grid, early_weight, early_max_t_since,
                       pre_ignition_weight, late_weight, score_scale,
                       m1_train_preds) {
      calls$early_weight <- early_weight
      calls$early_max <- early_max_t_since
      calls$pre_ignition_weight <- pre_ignition_weight
      calls$late_weight <- late_weight
      calls$score_scale <- score_scale
      prior_grids <- if (is.null(calls$m2_grids)) list() else calls$m2_grids
      calls$m2_grids <- c(prior_grids, list(grid))
      structure(list(
        grid = grid,
        scores = data.frame(),
        summary = data.frame(),
        training_rows = data.frame(),
        selected_config = list(
          h1 = list(id = "candidate"),
          h2 = list(id = "candidate"),
          alpha_state = 0.2,
          gamma = 1.4
        ),
        best_spec_id = "candidate",
        m1_train_preds = data.frame(carry = 1)
      ), class = c("page_m2_subset_tuning", "page_m2_tuning", "list"))
    },
    validate_m2_tuning = function(x, ...) invisible(x),
    .nested_inner_gate_rows = function(...) inner_rows,
    .nested_m2_decision = function(..., denominator_col = NULL) {
      list(
        decision = "use_m2",
        reasons = character(),
        denominator_col = denominator_col
      )
    },
    fit_m2 = function(...) list(stage = "m2"),
    freeze_m2 = function(x, ...) x,
    assemble_kit = function(...) list(ok = TRUE),
    validate_page_kit = function(x, ...) invisible(x)
  )

  labels <- lapply(c("A", "B", "C"), function(season) {
    PAGe:::label_season_timing(
      season = season,
      ignition = c(1L, 2L),
      peak = c(2L, 3L),
      n_weeks = 4L
    )
  })
  artifact_dir <- tempfile("timing-v2-outer-artifacts-")
  result <- PAGe::train_outer_fold(
    nested_test_data(),
    holdout = "C",
    exclude = character(),
    timing_labels = labels,
    artifact_dir = artifact_dir,
    m0_grid = data.frame(x = 1),
    m1_grid = data.frame(k_ref = 25L),
    m2_grid = data.frame(id = "off"),
    early_weight = 2,
    early_max_t_since = 12,
    score_scale = "equal_week",
    max_boundary_rounds = c(M0 = 1L, M1 = 1L, M2 = 2L),
    n_cores = 1L,
    verbose = FALSE
  )

  expect_s3_class(result, "page_outer_training")
  expect_false("C" %in% calls$m0_labels)
  expect_false("C" %in% calls$m1_labels)
  expect_equal(
    vapply(result$protocol$timing_labels_v2, `[[`, character(1L), "season"),
    c("A", "B", "C")
  )
  expect_equal(
    vapply(result$protocol$timing_labels_v2_training, `[[`, character(1L), "season"),
    c("A", "B")
  )
  expect_equal(
    vapply(result$timing_labels_v2, `[[`, character(1L), "season"),
    c("A", "B", "C")
  )
  expect_true(file.exists(file.path(artifact_dir, "timing_labels_v2.rds")))
  expect_equal(
    readRDS(file.path(artifact_dir, "timing_labels_v2.rds")), labels
  )
  expect_equal(selection_stub$training_seasons, c("A", "B"))
  expect_equal(calls$early_weight, 2)
  expect_equal(calls$early_max, 12)
  expect_equal(calls$pre_ignition_weight, 0)
  expect_equal(calls$late_weight, 1)
  expect_equal(calls$score_scale, "equal_week")
  expect_equal(calls$m2_round, 2L)
  expect_equal(nrow(calls$m2_grids[[2L]]), 2L)
  expect_equal(result$gate$applied$action, "use_m2")
})

test_that("train_outer_fold forwards every control override and derives the fallback id", {
  calls <- new.env(parent = emptyenv())
  off_id <- PAGe::m2_subset_config()$h1$id
  settled_plan <- function(stage) {
    structure(list(
      stage = stage,
      final_boundary_report = data.frame(
        parameter = character(), decision = character()
      ),
      unresolved = data.frame(),
      next_grid = NULL,
      settled = TRUE
    ), class = "page_boundary_action_plan")
  }
  inner_rows <- nested_test_predictions("A")

  local_mocked_bindings(
    tune_m0 = function(..., manual_labels, selection, flag_args) {
      calls$tune_m0_flag_args <- flag_args
      structure(list(
        best_params = list(ok = TRUE),
        tuning = list(best_params = list(ok = TRUE)),
        grid = data.frame(x = 1)
      ), class = "page_m0_tuning")
    },
    fit_m0 = function(..., flag_args) {
      calls$fit_m0_flag_args <- flag_args
      list(stage = "m0")
    },
    freeze_m0 = function(x, ...) x,
    validate_m0_tuning = function(x, ...) invisible(x),
    boundary_action_plan = function(tuning, stage, ...) {
      extra <- list(...)
      if (stage == "M0") calls$m0_steps <- extra$steps
      if (stage == "M1") {
        calls$m1_steps <- extra$steps
        calls$m1_boundary_min_gain <- extra$m1_min_gain
        calls$m1_boundary_prefer_simpler <- extra$m1_prefer_simpler
      }
      if (stage == "M2") {
        calls$m2_steps <- extra$steps
        calls$m2_max_specs <- extra$max_specs
      }
      settled_plan(stage)
    },
    tune_m1 = function(..., m1, manual_labels) {
      calls$tune_m1_params <- m1$m1_params
      structure(list(
        best = data.frame(k_ref = 25L),
        grid = data.frame(k_ref = 25L)
      ), class = "page_m1_tuning")
    },
    select_m1_candidate = function(tuning, ...) {
      extra <- list(...)
      calls$prefer_simpler <- extra$prefer_simpler
      list(selected = data.frame(k_ref = 25L))
    },
    validate_m1_tuning = function(x, ...) invisible(x),
    .m1_params_from_tuning = function(m1_params, tuning) {
      calls$fit_m1_params <- m1_params
      list(k_ref = 25L)
    },
    fit_m1 = function(...) list(stage = "m1"),
    freeze_m1 = function(x, ...) x,
    tune_m2 = function(..., grid, family, early_weight, early_max_t_since,
                       pre_ignition_weight, late_weight, score_scale,
                       m1_train_preds) {
      calls$tune_m2_family <- family
      calls$tune_m2_pre_ignition_weight <- pre_ignition_weight
      calls$tune_m2_late_weight <- late_weight
      structure(list(
        grid = data.frame(
          id = c(off_id, "i1_kz3_ku0_kd0"),
          stringsAsFactors = FALSE
        ),
        scores = data.frame(),
        summary = data.frame(),
        training_rows = data.frame(),
        selected_config = PAGe::m2_subset_config(
          h1 = PAGe:::m2_subset_spec(intercept = TRUE, k_z = 3L),
          h2 = PAGe:::m2_subset_spec(intercept = TRUE, k_z = 3L),
          alpha_state = 0.3,
          gamma = 1.7
        ),
        best_spec_id = "i1_kz3_ku0_kd0",
        m1_train_preds = data.frame(carry = 1)
      ), class = c("page_m2_subset_tuning", "page_m2_tuning", "list"))
    },
    validate_m2_tuning = function(x, ...) invisible(x),
    .nested_inner_gate_rows = function(...) inner_rows,
    .nested_m2_decision = function(..., denominator_col = NULL) {
      extra <- list(...)
      calls$pre_ignition_weight <- extra$pre_ignition_weight
      calls$late_weight <- extra$late_weight
      list(
        decision = "keep_m1",
        reasons = character(),
        denominator_col = denominator_col
      )
    },
    fit_m2 = function(..., config, family) {
      calls$fit_m2_family <- family
      calls$fit_m2_config <- config
      list(stage = "m2")
    },
    freeze_m2 = function(x, ...) x,
    assemble_kit = function(...) list(ok = TRUE),
    validate_page_kit = function(x, ...) invisible(x)
  )

  result <- PAGe::train_outer_fold(
    nested_test_data(),
    holdout = "C",
    exclude = character(),
    manual_labels = c(A = 1L, B = 1L),
    m0_grid = data.frame(x = 1),
    m0_flag_args = list(p_thresh = 0.5),
    m1_grid = data.frame(k_ref = 25L),
    m1_params = list(k_ref = 25L, slope_weight = 8),
    m2_grid = data.frame(id = c(off_id, "i1_kz3_ku0_kd0")),
    pre_ignition_weight = 0.5,
    late_weight = 3,
    m1_prefer_simpler = FALSE,
    m0_expansion_steps = c(p_thr = 0.001),
    m1_expansion_steps = c(k_ref = 7, slope_weight = 2),
    m1_min_gain = 0.125,
    m2_expansion_steps = c(k_z = 1),
    m2_expansion_increment = 3L,
    max_boundary_rounds = c(M0 = 1L, M1 = 1L, M2 = 1L),
    n_cores = 1L,
    verbose = FALSE
  )

  expect_equal(calls$tune_m0_flag_args, list(p_thresh = 0.5))
  expect_equal(calls$fit_m0_flag_args, list(p_thresh = 0.5))
  expect_equal(calls$tune_m1_params, list(k_ref = 25L, slope_weight = 8))
  expect_equal(calls$fit_m1_params, list(k_ref = 25L, slope_weight = 8))
  expect_equal(calls$m0_steps, c(p_thr = 0.001))
  expect_equal(calls$m1_steps, c(k_ref = 7, slope_weight = 2))
  expect_equal(calls$m1_boundary_min_gain, 0.125)
  expect_false(calls$m1_boundary_prefer_simpler)
  expect_equal(calls$m2_steps, c(k_z = 1))
  expect_equal(calls$m2_max_specs, 5L)
  expect_equal(calls$tune_m2_family, PAGe:::m2_subset_family())
  expect_equal(calls$tune_m2_pre_ignition_weight, 0.5)
  expect_equal(calls$tune_m2_late_weight, 3)
  expect_equal(calls$fit_m2_family, PAGe:::m2_subset_family())
  expect_false(calls$prefer_simpler)
  expect_equal(calls$pre_ignition_weight, 0.5)
  expect_equal(calls$late_weight, 3)
  expect_equal(result$protocol$weighting$pre_ignition, 0.5)
  expect_equal(result$protocol$weighting$late, 3)
  expect_equal(result$protocol$model$m2_family, PAGe:::m2_subset_family())
  expect_equal(result$protocol$expansion$m0_steps, c(p_thr = 0.001))
  expect_equal(result$protocol$expansion$m2_steps, c(k_z = 1))
  expect_equal(result$protocol$expansion$m2_increment, 3L)

  expect_equal(result$gate$applied$action, "keep_m1")
  expect_equal(
    result$gate$applied$applied_spec_id,
    paste0("h1:", off_id, "|h2:", off_id)
  )
  expect_equal(calls$fit_m2_config$alpha_state, 0.3)
  expect_equal(calls$fit_m2_config$gamma, 1.7)
  expect_equal(
    calls$fit_m2_config$h1[, c("id", "intercept", "k_z", "k_u", "k_d")],
    PAGe:::m2_subset_spec()[, c("id", "intercept", "k_z", "k_u", "k_d")]
  )
})

test_that("all-off fallback identifier is derived from the subset constructor", {
  off_id <- PAGe::m2_subset_config()$h1$id
  expect_identical(off_id, "i0_kz0_ku0_kd0")
  tuning <- list(
    grid = data.frame(id = c("other", off_id), stringsAsFactors = FALSE),
    selected_config = PAGe::m2_subset_config(alpha_state = 0.3, gamma = 1.7)
  )
  fallback <- PAGe:::.nested_all_off_config(tuning$selected_config, tuning)
  expect_identical(as.character(fallback$row$id), off_id)
  expect_true(PAGe:::m2_subset_is_family(fallback$config))
  expect_equal(fallback$config$alpha_state, 0.3)
  expect_equal(fallback$config$gamma, 1.7)
  tuning$grid <- tuning$grid[tuning$grid$id != off_id, , drop = FALSE]
  expect_error(
    PAGe:::.nested_all_off_config(tuning$selected_config, tuning),
    "all-off fallback"
  )
})

test_that("run_outer_fold enforces strict compatibility and protocol weights", {
  protocol <- list(
    weighting = list(
      early = 2, early_max_t_since = 12, pre_ignition = 0.5, late = 3,
      score_scale = "equal_week"
    ),
    adoption = list(
      min_gain = 0,
      min_gain_by_horizon = c("2" = 0),
      confidence = 0.5,
      max_season_degradation = 0
    )
  )
  seen_compat <- NULL
  seen_timing <- NULL
  seen_weights <- new.env(parent = emptyenv())
  local_mocked_bindings(
    train_outer_fold = function(data, holdout, timing_labels = NULL, ...) {
      seen_timing <<- timing_labels
      structure(list(
        protocol = protocol,
        kit = list(ok = TRUE)
      ), class = c("page_outer_training", "list"))
    },
    replay_season_holdout = function(kit, allD, season, kit_compatibility,
                                     ...) {
      seen_compat <<- kit_compatibility
      list(
        status = "unseen_replay_complete",
        predictions = data.frame(
          season = season,
          lead = c("h1", "h2"),
          weekF = c(1L, 2L),
          target_weekF = c(2L, 4L),
          p_obs = 0.1,
          p_hat = 0.2,
          t_since = c(1, 2),
          N_lead = 10
        ),
        stages = list(
          m2_predictions = data.frame(
            h = c("h1", "h2"), eval_week = c(1L, 2L),
            target_weekF = c(2L, 4L), m1_p = 0.15
          )
        )
      )
    },
    .nested_m2_decision = function(..., denominator_col = NULL) {
      extra <- list(...)
      seen_weights$pre_ignition <- extra$pre_ignition_weight
      seen_weights$late <- extra$late_weight
      list(decision = "use_m2", reasons = character())
    }
  )

  timing <- PAGe:::label_season_timing(
    season = "C", ignition = c(1L, 2L), peak = c(2L, 3L), n_weeks = 4L
  )
  result <- PAGe::run_outer_fold(
    nested_test_data(),
    holdout = "C",
    timing_labels = timing
  )
  expect_equal(seen_compat, "strict")
  expect_s3_class(seen_timing, "page_timing_labels_v2")
  expect_identical(seen_timing$season, "C")
  expect_equal(seen_weights$pre_ignition, 0.5)
  expect_equal(seen_weights$late, 3)
  expect_s3_class(result, "page_outer_fold_result")
  expect_equal(nrow(result$predictions), 2L)
  expect_identical(result$sensitivity_scale, "test_count")
})

test_that("score_scale controls primary and sensitivity denominators", {
  equal <- PAGe:::.nested_score_denominators("equal_week")
  expect_null(equal$primary)
  expect_identical(equal$sensitivity, "N_lead")
  expect_identical(equal$sensitivity_scale, "test_count")

  count <- PAGe:::.nested_score_denominators("test_count")
  expect_identical(count$primary, "N_lead")
  expect_null(count$sensitivity)
  expect_identical(count$sensitivity_scale, "equal_week")
})

test_that("min_training_seasons and control validation are enforced", {
  expect_error(
    PAGe::train_outer_fold(
      nested_test_data(),
      holdout = "C",
      exclude = character(),
      min_training_seasons = 3L,
      n_cores = 1L,
      verbose = FALSE
    ),
    "At least 3 outer-training seasons"
  )
  expect_error(
    PAGe::train_outer_fold(
      nested_test_data(),
      holdout = "C",
      exclude = character(),
      m1_expansion_steps = c(5, 4),
      n_cores = 1L,
      verbose = FALSE
    ),
    "named vector of positive steps"
  )
  expect_error(
    PAGe::train_outer_fold(
      nested_test_data(),
      holdout = "C",
      exclude = character(),
      m2_family = c("a", "b"),
      n_cores = 1L,
      verbose = FALSE
    ),
    "supports only M2 family"
  )
  expect_error(
    PAGe::train_outer_fold(
      nested_test_data(),
      holdout = "C",
      exclude = character(),
      m2_expansion_increment = 2.5,
      n_cores = 1L,
      verbose = FALSE
    ),
    "must be an integer"
  )
  expect_error(
    PAGe::train_outer_fold(
      nested_test_data(),
      holdout = "C",
      exclude = character(),
      m1_expansion_steps = c(k_ref = 0, slope_weight = 0.5),
      n_cores = 1L,
      verbose = FALSE
    ),
    "positive steps"
  )
})

test_that("nested evaluation rejects excluded or absent outer seasons", {
  data <- nested_test_data()
  expect_error(
    PAGe::nested_season_evaluation(
      data,
      holdouts = "Z", exclude = character()
    ),
    "absent"
  )
  expect_error(
    PAGe::nested_season_evaluation(data, holdouts = "A", exclude = "A"),
    "fixed exclusion"
  )
})

test_that("final fit uses all eligible seasons without an outer holdout", {
  seen_holdout <- "not-called"
  local_mocked_bindings(
    train_outer_fold = function(data, holdout, exclude, ...) {
      seen_holdout <<- holdout
      structure(list(
        protocol = list(
          analysis_role = "final_fit",
          training_seasons = setdiff(unique(data$season), exclude)
        ),
        kit = list(ok = TRUE)
      ), class = c("page_outer_training", "list"))
    }
  )

  result <- PAGe::fit_final_pipeline(
    nested_test_data(),
    exclude = character()
  )

  expect_s3_class(result, "page_final_training")
  expect_null(seen_holdout)
  expect_equal(result$protocol$training_seasons, c("A", "B", "C"))
})

test_that("timing-v2 is explicit on every nested training entry point", {
  expect_true("timing_labels" %in% names(formals(PAGe::train_outer_fold)))
  expect_true("timing_labels" %in% names(formals(PAGe::run_outer_fold)))
  expect_true("timing_labels" %in% names(formals(PAGe::nested_season_evaluation)))
})

test_that("replay paths reject missing, duplicated, and unmatched forecast keys", {
  predictions <- nested_test_replay_predictions("C")
  m2_predictions <- data.frame(
    eval_week = predictions$weekF,
    h = predictions$lead,
    target_weekF = predictions$target_weekF,
    m1_p = 0.15
  )
  replay <- function(preds = predictions, m1 = m2_predictions,
                     ledger = NULL) {
    list(
      predictions = preds,
      stages = list(m2_predictions = m1),
      forecast_ledger = ledger
    )
  }

  expect_silent(PAGe:::.nested_replay_rows(replay()))

  duplicated_predictions <- rbind(predictions, predictions[1L, , drop = FALSE])
  expect_error(
    PAGe:::.nested_replay_rows(replay(preds = duplicated_predictions)),
    "duplicated forecast keys"
  )

  unmatched_m1 <- m2_predictions
  unmatched_m1$eval_week <- unmatched_m1$eval_week + 100L
  unmatched_m1$target_weekF <- unmatched_m1$target_weekF + 100L
  expect_error(
    PAGe:::.nested_replay_rows(replay(m1 = unmatched_m1)),
    "no matched M1 prediction"
  )

  ledger <- data.frame(
    weekF = c(predictions$origin, 99L),
    lead = c(predictions$horizon, 1L),
    scorable = TRUE
  )
  expect_error(
    PAGe:::.nested_replay_rows(replay(ledger = ledger)),
    "missing .* expected forecast key"
  )

  current_data <- data.frame(weekF = 1:4, y = c(0, 1, 2, 3), N = 10)
  expect_error(
    PAGe:::.replay_forecast_ledger(
      data.frame(weekF = c(1L, 1L), lead = c(1L, 1L), p_hat = c(0.1, 0.2)),
      current_data, "C", 1
    ),
    "duplicated forecast keys"
  )
  expect_error(
    PAGe:::.replay_forecast_ledger(
      data.frame(weekF = 99L, lead = 1L, p_hat = 0.1),
      current_data, "C", 1
    ),
    "outside the expected season ledger"
  )
})
