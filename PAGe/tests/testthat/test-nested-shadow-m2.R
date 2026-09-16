# Synthetic orchestration tests: expensive stage fitting/tuning and the replay
# runner are mocked; season selection, row matching and scoring remain real.
shadow_fixture <- function(action = "keep_m1", all_off = FALSE,
                           failure = NULL, .env = parent.frame()) {
  seen <- new.env(parent = emptyenv())
  seen$fits <- list()
  seen$replays <- list()
  config <- PAGe::m2_subset_config(
    h1 = PAGe:::m2_subset_spec(intercept = !all_off),
    h2 = PAGe:::m2_subset_spec(intercept = !all_off)
  )
  data <- data.frame(
    season = rep(c("A", "B", "C"), each = 4),
    weekF = rep(1:4, 3), y = 1L, N = 10L, nW_true = 4L
  )
  tuning <- list(
    selected_config = config,
    best_spec_id = paste0("h1:", config$h1$id, "|h2:", config$h2$id),
    grid = unique(rbind(PAGe:::m2_subset_spec(), config$h1)),
    m1_train_preds = data.frame(season = c("A", "B"), carry = 1)
  )
  testthat::local_mocked_bindings(
    tune_m0 = function(...) list(best_params = list(ok = TRUE)),
    boundary_action_plan = function(...) list(settled = TRUE),
    validate_m0_tuning = function(...) NULL,
    fit_m0 = function(...) list(stage = "m0"),
    freeze_m0 = function(x, ...) x,
    tune_m1 = function(...) list(best = data.frame(k_ref = 25L)),
    select_m1_candidate = function(...) list(selected = data.frame(k_ref = 25L)),
    validate_m1_tuning = function(...) NULL,
    .m1_params_from_tuning = function(...) list(k_ref = 25L),
    fit_m1 = function(...) list(stage = "m1"),
    freeze_m1 = function(x, ...) x,
    tune_m2 = function(...) tuning,
    validate_m2_tuning = function(...) NULL,
    .nested_inner_gate_rows = function(...) data.frame(),
    .nested_m2_decision = function(rows, ...) {
      if (!nrow(rows)) {
        return(list(decision = action, reasons = character()))
      }
      PAGe::decide_m2_vs_m1(
        rows,
        outcome_col = "outcome", m1_col = "m1_prediction",
        m2_col = "m2_prediction", season_col = "season", origin_col = "origin",
        target_col = "target", horizon_col = "horizon", t_since_col = "t_since_target",
        phase_break = list(...)$early_max_t_since,
        phase_weights = c(
          pre_ignition = list(...)$pre_ignition_weight,
          early = list(...)$early_weight, late = list(...)$late_weight
        ),
        denominator_col = list(...)$denominator_col,
        scoring = "legacy_0_12",
        min_gain = list(...)$min_gain,
        min_gain_by_horizon = list(...)$min_gain_by_horizon,
        confidence = list(...)$confidence,
        max_season_degradation = list(...)$max_season_degradation
      )
    },
    fit_m2 = function(data, selection, m0, m1, config, ...) {
      is_shadow <- action == "keep_m1" && config$h1$intercept
      seen$fits[[length(seen$fits) + 1L]] <- list(
        training = PAGe:::.selected_training_data(data, selection),
        selection = selection, config = config, m0 = m0, m1 = m1, args = list(...)
      )
      if (is_shadow) {
        stats::runif(1) # The optional fit must not consume primary RNG.
        if (identical(failure, "fit")) stop("forced shadow fit failure")
      }
      list(config = config, is_shadow = is_shadow)
    },
    freeze_m2 = function(x, tuning, ...) {
      stopifnot(identical(x$config, tuning$selected_config))
      x
    },
    assemble_kit = function(m0, m1, m2, best_spec_id) {
      list(m0 = m0, m1 = m1, m2 = m2, best_spec_id = best_spec_id)
    },
    validate_page_kit = function(x, ...) {
      if (x$m2$is_shadow && identical(failure, "validate")) stop("forced validation failure")
      invisible(x)
    },
    replay_season_holdout = function(kit, allD, season, kit_compatibility, timing_mode) {
      seen$replays[[length(seen$replays) + 1L]] <- list(
        season = season, strict = kit_compatibility, timing_mode = timing_mode,
        fit_count = length(seen$fits)
      )
      is_shadow <- kit$m2$is_shadow
      if (is_shadow && identical(failure, "replay")) stop("forced shadow replay failure")
      p <- if (kit$m2$config$h1$intercept) c(0.11, 0.12) else c(0.2, 0.2)
      predictions <- data.frame(
        season = season, weekF = c(1L, 2L), target_weekF = c(2L, 4L),
        lead = 1:2, p_obs = 0.1, p_hat = p, t_since = c(1L, 2L), N_lead = 10L
      )
      m1 <- data.frame(
        eval_week = c(1L, 2L), target_weekF = c(2L, 4L), h = 1:2, m1_p = 0.2
      )
      if (is_shadow) {
        if (identical(failure, "m1")) m1$m1_p <- 0.3
        if (identical(failure, "keys")) predictions$season <- "wrong"
        if (identical(failure, "missing")) predictions$p_hat[1] <- NA_real_
        predictions <- predictions[2:1, ] # Exercise joining, not row position.
      }
      list(
        status = if (is_shadow && identical(failure, "contract")) "failed" else "unseen_replay_complete",
        predictions = predictions, stages = list(m2_predictions = m1)
      )
    },
    .package = "PAGe", .env = .env
  )
  list(data = data, seen = seen, config = config, args = list(
    exclude = character(), manual_labels = c(A = 1L, B = 1L, C = 1L),
    m0_grid = data.frame(x = 1), m1_grid = data.frame(k_ref = 25L),
    m2_grid = tuning$grid, n_cores = 1L, verbose = FALSE
  ))
}

shadow_run <- function(fixture, directory, enabled = TRUE) {
  do.call(PAGe::run_outer_fold, c(list(
    data = fixture$data, holdout = "C", artifact_dir = directory,
    shadow_m2 = enabled
  ), fixture$args))
}

test_that("rejected tuned M2 is output-only and uses the same training inputs", {
  f <- shadow_fixture()
  off_dir <- withr::local_tempdir()
  on_dir <- withr::local_tempdir()
  set.seed(41)
  off <- shadow_run(f, off_dir, FALSE)
  seed <- .Random.seed
  on <- shadow_run(f, on_dir)
  expect_identical(.Random.seed, seed)
  expect_identical(on$shadow_status, "built")
  expect_true(on$shadow_m1_prediction_equal)
  expect_equal(on$predictions$m2_shadow_prediction, c(0.11, 0.12))
  expect_true(all(on$predictions$m2_shadow_prediction != on$predictions$m1_prediction))
  expect_identical(on$predictions[names(off$predictions)], off$predictions)
  expect_identical(on$metrics, off$metrics)
  expect_identical(on$sensitivity, off$sensitivity)
  expect_identical(on$training$kit, off$training$kit)
  expect_identical(on$training$gate, off$training$gate)
  expect_identical(on$training$tuning, off$training$tuning)
  expect_false("shadow_status" %in% names(off))
  expect_false(any(grepl("shadow", list.files(off_dir))))
  unchanged <- setdiff(
    list.files(off_dir),
    c(
      "outer_fold_result.rds", "outer_predictions.csv",
      "outer_predictions_per_row.csv"
    )
  )
  expect_identical(
    unname(tools::md5sum(file.path(on_dir, unchanged))),
    unname(tools::md5sum(file.path(off_dir, unchanged)))
  )
  csv <- read.csv(file.path(on_dir, "outer_predictions.csv"))
  expect_equal(csv$m2_shadow_prediction, c(0.11, 0.12))
  expect_true(all(csv$shadow_status == "built"))
  expect_identical(readRDS(file.path(on_dir, "outer_shadow_metrics.rds")), on$shadow_metrics)
  expect_true(readRDS(file.path(on_dir, "shadow_m2_status.rds"))$m1_prediction_equal)
  expect_identical(readRDS(file.path(on_dir, "shadow_m2_kit.rds"))$m2$config, f$config)
  expect_identical(f$seen$fits[[2]]$training$season, rep(c("A", "B"), each = 4))
  expect_identical(f$seen$fits[[2]]$args, f$seen$fits[[3]]$args)
  expect_identical(f$seen$fits[[2]]$m0, f$seen$fits[[3]]$m0)
  expect_identical(f$seen$fits[[2]]$m1, f$seen$fits[[3]]$m1)
  expect_identical(f$seen$replays[[2]], f$seen$replays[[3]])
  expect_identical(f$seen$replays[[2]]$strict, "strict")
  expect_equal(f$seen$replays[[2]]$fit_count, 3L)
})

test_that("accepted and all-off candidates reuse primary predictions", {
  for (action in c("use_m2", "keep_m1")) {
    f <- shadow_fixture(action, all_off = action == "keep_m1")
    directory <- withr::local_tempdir()
    result <- shadow_run(f, directory)
    expected <- if (action == "use_m2") "not_needed_use_m2" else "not_needed_tuned_all_off"
    expect_identical(result$shadow_status, expected)
    expect_identical(result$predictions$m2_shadow_prediction, result$predictions$m2_prediction)
    expect_identical(result$shadow_metrics, result$metrics)
    expect_length(f$seen$fits, 1L)
    expect_length(f$seen$replays, 1L)
    expect_false(file.exists(file.path(directory, "shadow_m2_kit.rds")))
  }
})

test_that("final all-season training never builds a shadow", {
  f <- shadow_fixture()
  directory <- withr::local_tempdir()
  result <- do.call(PAGe::train_outer_fold, c(list(
    data = f$data, holdout = NULL, artifact_dir = directory
  ), f$args))
  expect_identical(result$shadow_m2$status, "final_fit_no_shadow")
  expect_identical(readRDS(file.path(directory, "shadow_m2_status.rds"))$status, "final_fit_no_shadow")
  expect_length(f$seen$fits, 1L)
  expect_length(f$seen$replays, 0L)
  expect_false(file.exists(file.path(directory, "shadow_m2_kit.rds")))
})

test_that("shadow failures cannot prevent primary fold completion", {
  for (failure in c("fit", "validate", "replay", "contract", "m1", "keys", "missing")) {
    f <- shadow_fixture(failure = failure)
    directory <- withr::local_tempdir()
    off <- shadow_run(f, withr::local_tempdir(), FALSE)
    result <- shadow_run(f, directory)
    expect_match(result$shadow_status, "^failed:", info = failure)
    expect_identical(result$metrics, off$metrics)
    expect_identical(result$predictions[names(off$predictions)], off$predictions)
    expect_true(all(is.na(result$predictions$m2_shadow_prediction)))
    expect_null(result$shadow_metrics)
    expect_identical(readRDS(file.path(directory, "outer_fold_result.rds")), result)
    expect_identical(readRDS(file.path(directory, "shadow_m2_status.rds"))$status, result$shadow_status)
    expect_true(file.exists(file.path(directory, "outer_shadow_metrics.rds")))
  }
})

test_that("legacy completed folds resume as absent alongside new shadows", {
  f <- shadow_fixture()
  directory <- withr::local_tempdir()
  args <- c(list(data = f$data, holdouts = c("B", "C"), artifact_dir = directory), f$args)
  first <- do.call(PAGe::nested_season_evaluation, args)
  path <- file.path(directory, "B", "outer_fold_result.rds")
  old <- readRDS(path)
  old[c("shadow_status", "shadow_metrics", "shadow_m1_prediction_equal")] <- NULL
  old$training$shadow_m2 <- NULL
  old$predictions[c("m2_shadow_prediction", "shadow_status")] <- NULL
  saveRDS(old, path)
  hash <- tools::md5sum(path)
  count <- length(f$seen$fits)
  resumed <- do.call(PAGe::nested_season_evaluation, args)
  expect_identical(length(f$seen$fits), count)
  expect_identical(tools::md5sum(path), hash)
  expect_identical(resumed$folds$B$shadow_status, "absent")
  expect_null(resumed$folds$B$shadow_metrics)
  expect_true(all(is.na(resumed$folds$B$predictions$m2_shadow_prediction)))
  expect_identical(resumed$primary, first$primary)
  expect_identical(resumed$folds$C$shadow_status, "built")
})
