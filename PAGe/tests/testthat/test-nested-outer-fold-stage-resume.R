# train_outer_fold() previously redid its entire M0/M1/and top-level-M2 tune
# on every invocation, even when a prior attempt into the SAME artifact_dir
# had already frozen those stages -- a crash deep in the nested inner-gate
# loop (the expensive part) meant redoing hours of already-completed M0/M1
# work on every restart. It now checks for m0_frozen.rds/m1_frozen.rds/
# m2_tuning_settled.rds first and skips straight past a stage that already
# has one, exactly mirroring the pattern used elsewhere in the pipeline.
#
# Self-contained fixtures (not shared with test-nested-season-evaluation.R):
# testthat sources test files in name order and runs each file's top-level
# code immediately as part of sourcing it, so relying on another file's
# top-level helper functions is order-dependent and fragile.
stage_resume_test_data <- function(seasons = c("A", "B", "C")) {
  data.frame(
    season = rep(seasons, each = 4L),
    weekF = rep(seq_len(4L), length(seasons)),
    y = rep(c(1, 2, 3, 4), length(seasons)),
    N = 10, nW_true = 4L
  )
}
stage_resume_test_predictions <- function(season, m2 = 0.1) {
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

test_that("train_outer_fold skips M0/M1/top-level-M2 on a second call into the same artifact_dir", {
  calls <- new.env(parent = emptyenv())
  calls$m0_n <- 0L
  calls$m1_n <- 0L
  calls$m2_n <- 0L
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
    stage_resume_test_predictions(season)
  }))

  local_mocked_bindings(
    tune_m0 = function(..., manual_labels, selection) {
      calls$m0_n <- calls$m0_n + 1L
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
      settled_plan("M2")
    },
    validate_m0_tuning = function(x, ...) invisible(x),
    fit_m0 = function(...) list(stage = "m0"),
    freeze_m0 = function(x, ...) x,
    tune_m1 = function(..., manual_labels) {
      calls$m1_n <- calls$m1_n + 1L
      structure(list(
        best = data.frame(k_ref = 25L),
        grid = data.frame(k_ref = 25L)
      ), class = "page_m1_tuning")
    },
    select_m1_candidate = function(...) {
      list(selected = data.frame(k_ref = 25L))
    },
    validate_m1_tuning = function(x, ...) invisible(x),
    .m1_params_from_tuning = function(...) list(k_ref = 25L),
    fit_m1 = function(...) list(stage = "m1"),
    freeze_m1 = function(x, ...) x,
    tune_m2 = function(..., grid, early_weight, early_max_t_since,
                       pre_ignition_weight, late_weight, score_scale,
                       m1_train_preds) {
      calls$m2_n <- calls$m2_n + 1L
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
  args <- list(
    data = stage_resume_test_data(),
    holdout = "C",
    exclude = character(),
    timing_labels = labels,
    artifact_dir = tempfile("stage-resume-outer-artifacts-"),
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

  first <- do.call(PAGe::train_outer_fold, args)
  expect_equal(calls$m0_n, 1L)
  expect_equal(calls$m1_n, 1L)
  expect_equal(calls$m2_n, 1L)
  expect_true(file.exists(file.path(args$artifact_dir, "m0_frozen.rds")))
  expect_true(file.exists(file.path(args$artifact_dir, "m1_frozen.rds")))
  expect_true(file.exists(file.path(args$artifact_dir, "m2_tuning_settled.rds")))

  # Second call into the SAME artifact_dir: M0/M1/top-level-M2 must not be
  # retuned -- only the (mocked) nested inner-gate step and final freeze run.
  second <- do.call(PAGe::train_outer_fold, args)
  expect_equal(calls$m0_n, 1L)
  expect_equal(calls$m1_n, 1L)
  expect_equal(calls$m2_n, 1L)
  expect_equal(second$gate$applied$action, first$gate$applied$action)
})
