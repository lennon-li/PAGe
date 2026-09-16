subset_test_selection <- function() {
  structure(list(
    training_seasons = "a", exclude_seasons = character(),
    holdout_seasons = character(), application_seasons = character(),
    data_seasons = "a"
  ), class = "page_season_selection")
}

subset_test_m1 <- function(selection) {
  payload <- list(
    ref = list(anchorWeek = 20, pred_df = data.frame(newWeek = 1:3, fit = .5)),
    hyper = list(), aligned_train = data.frame(),
    m1_params = list(
      temperature = .25, rise_weight = 1, trough_weight = .1,
      peak_decay = .3, slope_weight = 8, slope_window = 6,
      dynamic_temp = FALSE, dynamic_temp_pivot = 10
    ), seasons_used = "a"
  )
  fit <- PAGe:::.new_stage_fit("m1", selection, list(k_ref = 25), payload,
    upstream_ids = list(m0 = "m0"), data_id = "data"
  )
  fit$status <- "frozen"
  fit$artifact_id <- PAGe:::.stage_artifact_id(
    "m1", fit$selection, fit$config, fit$upstream_ids, fit$data_id,
    PAGe:::.stage_fit_payload(fit)
  )
  fit
}

test_that("offset subset family is explicit, opt-in, and all-off is exact at runtime", {
  selection <- subset_test_selection()
  d <- data.frame(
    season = rep("a", 8), lead = rep(c("h1", "h2"), 4),
    m1_logit = seq(-2, 1, length.out = 8), y_lead = 1, N_lead = 10
  )
  config <- PAGe:::m2_subset_config()
  fit_one <- PAGe:::m2_subset_fit(d, config$h1)
  expect_equal(config$family, "offset_subset_v1")
  expect_equal(fit_one$type, "all_off")
  expect_null(fit_one[["fit"]])

  kit <- list(
    ref = list(anchorWeek = 20), hyper = list(), M1_PARAMS = list(
      temperature = .25, rise_weight = 1, trough_weight = .1,
      peak_decay = .3, slope_weight = 8, slope_window = 6,
      dynamic_temp = FALSE, dynamic_temp_pivot = 10
    ), m0_params = list(x = 1), best_spec = config,
    m2_production = list(
      family = PAGe:::m2_subset_family(), spec = config,
      fit = list(h1 = fit_one, h2 = fit_one), feature_ranges = list(h1 = list(), h2 = list())
    )
  )
  m1_result <- list(per_week = list(list(
    ew = 5L, ap = list(
      state = "aligning", iWeek_hat = 3L,
      forecast_df = data.frame(newWeek = 1:30, p_hat = seq(.1, .9, length.out = 30))
    ),
    season_to_ew = data.frame(season = "current", weekF = 1:5, y = 1:5, N = 10)
  )))
  out <- PAGe:::m2_subset_runtime_prediction(kit, m1_result$per_week[[1L]]$season_to_ew,
    m1_result,
    verbose = FALSE
  )
  expect_equal(out$m2_preds$m2_p, out$m2_preds$m1_baseline, tolerance = 0)
  expect_true(all(out$m2_preds$forecast_action == "all_off_exact_m1"))
  expect_error(
    PAGe:::m2_subset_runtime_prediction(
      kit, transform(m1_result$per_week[[1L]]$season_to_ew,
        y = ifelse(weekF == 4L, 9, y)
      ), m1_result,
      verbose = FALSE
    ),
    "does not match"
  )
})

test_that("runtime subset features use validated current data and share training parity", {
  obs <- data.frame(
    season = "current", weekF = 1:5,
    y = c(1, 2, 3, 4, 5), N = 10
  )
  detector <- function(currentSeason, params, start_week) {
    list(
      ign_week_locked = 2L,
      df = data.frame(weekF = currentSeason$weekF, ignite_ok_now = FALSE)
    )
  }
  dec <- PAGe:::m2_subset_prefix_declaration(obs, list(), 5L, detector)
  fs <- PAGe:::m2_subset_observed_features(obs, dec$week, 0.2)
  expected <- fs[fs$weekF == 5L, c("z", "u", "d")]
  runtime_row <- PAGe:::m2_subset_runtime_feature_row(
    obs,
    origin_week = 5L, declaration = dec, m1_p = 0.2, h = 1L,
    alpha_state = 0.2
  )
  expect_equal(as.numeric(runtime_row[c("z", "u", "d")]),
    as.numeric(expected),
    tolerance = 0
  )
  train_obs <- rbind(obs, data.frame(
    season = "current", weekF = 6,
    y = 6, N = 10
  ))
  train_rows <- PAGe:::m2_subset_make_rows(
    train_obs,
    m0 = list(best_params = list()), m1 = list(),
    m1_train_preds = data.frame(
      season = "current", eval_weekF = 5L, target_weekF = 6L,
      h = 1L, m1_p_hat = 0.2
    ), seasons = "current", detector = detector, alpha_state = 0.2
  )$data
  expect_equal(as.numeric(train_rows[1L, c("z", "u", "d")]),
    as.numeric(runtime_row[c("z", "u", "d")]),
    tolerance = 0
  )
})

test_that("subset row preparation computes observed features once per origin", {
  obs <- data.frame(
    season = "current", weekF = 1:6,
    y = c(1, 2, 3, 4, 5, 6), N = 10
  )
  preds <- data.frame(
    season = "current", eval_weekF = 4L,
    target_weekF = c(5L, 6L), h = c(1L, 2L),
    m1_p_hat = c(0.2, 0.25)
  )
  detector <- function(currentSeason, params, start_week) {
    list(
      ign_week_locked = 2L,
      df = data.frame(
        weekF = currentSeason$weekF,
        ignite_ok_now = currentSeason$weekF == 2L
      )
    )
  }
  original <- PAGe:::m2_subset_observed_features
  calls <- 0L
  testthat::local_mocked_bindings(
    m2_subset_observed_features = function(...) {
      calls <<- calls + 1L
      original(...)
    },
    .package = "PAGe"
  )

  rows <- PAGe:::m2_subset_make_rows(
    obs,
    m0 = list(best_params = list()),
    m1 = list(),
    m1_train_preds = preds,
    seasons = "current",
    detector = detector,
    alpha_state = 0.2
  )$data

  expect_equal(nrow(rows), 2L)
  expect_equal(calls, 1L)
  state <- original(obs[obs$weekF <= 4L, , drop = FALSE], 2L, 0.2)
  state <- state[state$weekF == 4L, c("z", "u", "d")]
  expect_equal(rows$m1_logit, PAGe:::m2_subset_logit(preds$m1_p_hat))
  expect_equal(rows$z, rep(state$z, 2L), tolerance = 0)
  expect_equal(rows$u, rep(state$u, 2L), tolerance = 0)
  expect_equal(rows$d, rep(state$d, 2L), tolerance = 0)
})

test_that("subset tuning prepares M1 predictions once for every candidate", {
  obs <- do.call(rbind, lapply(c("a", "b"), function(s) {
    data.frame(
      season = s, weekF = 1:8,
      y = c(1, 2, 3, 4, 5, 4, 3, 2), N = 20, nW_true = 8L
    )
  }))
  preds <- do.call(rbind, lapply(c("a", "b"), function(s) {
    data.frame(
      season = s,
      eval_weekF = rep(3:6, each = 2L),
      target_weekF = rep(3:6, each = 2L) + rep(1:2, 4L),
      h = rep(1:2, 4L), m1_p_hat = 0.2
    )
  }))
  detector <- function(currentSeason, params, start_week) {
    list(
      ign_week_locked = 2L,
      df = data.frame(
        weekF = currentSeason$weekF,
        ignite_ok_now = currentSeason$weekF == 2L
      )
    )
  }
  selection <- structure(list(
    training_seasons = c("a", "b"), exclude_seasons = character(),
    holdout_seasons = character(), application_seasons = character(),
    data_seasons = c("a", "b")
  ), class = "page_season_selection")
  calls <- 0L
  testthat::local_mocked_bindings(
    .m1_heldout_references = function(m1, seasons, timing_mode) {
      stats::setNames(lapply(seasons, function(s) {
        list(
          ref = list(), hyper = list(), training_seasons = setdiff(seasons, s)
        )
      }), seasons)
    },
    m1_walkforward_multi = function(...) {
      calls <<- calls + 1L
      preds
    },
    .package = "PAGe"
  )

  tuning <- PAGe:::m2_subset_tune(
    obs, selection,
    m0 = list(best_params = list()),
    m1 = list(ref = list(), hyper = list(), m1_params = list()),
    grid = PAGe:::m2_subset_grid()[1:2, , drop = FALSE],
    detector = detector
  )

  expect_equal(calls, 1L)
  expect_equal(nrow(tuning$grid), 16L)
})

test_that("train_pipeline exposes an explicit opt-in M2 family", {
  expect_true("m2_family" %in% names(formals(PAGe::train_pipeline)))
  expect_identical(
    eval(formals(PAGe::train_pipeline)$m2_family)[[1L]],
    "offset_subset_v1"
  )
  expect_identical(eval(formals(PAGe::train_pipeline)$allow_legacy), FALSE)
})

test_that("subset frozen artifact serializes and existing provenance guards apply", {
  selection <- structure(list(
    training_seasons = c("a", "b"), exclude_seasons = character(),
    holdout_seasons = character(), application_seasons = character(),
    data_seasons = c("a", "b")
  ), class = "page_season_selection")
  m0_payload <- list(
    aligned = data.frame(), seasons_used = "a", best_params = list(x = 1),
    manual_labels = integer(), flag_args = list()
  )
  m0 <- PAGe:::.new_stage_fit("m0", selection, list(x = 1), m0_payload,
    data_id = "data"
  )
  m0$status <- "frozen"
  m0$artifact_id <- PAGe:::.stage_artifact_id(
    "m0", m0$selection, m0$config, m0$upstream_ids, m0$data_id,
    PAGe:::.stage_fit_payload(m0)
  )
  m1 <- subset_test_m1(selection)
  m1$upstream_ids$m0 <- m0$artifact_id
  m1$artifact_id <- PAGe:::.stage_artifact_id(
    "m1", m1$selection, m1$config, m1$upstream_ids, m1$data_id,
    PAGe:::.stage_fit_payload(m1)
  )
  d <- data.frame(
    season = rep("a", 8), lead = rep(c("h1", "h2"), 4),
    m1_logit = seq(-2, 1, length.out = 8), y_lead = 1, N_lead = 10
  )
  config <- PAGe:::m2_subset_config()
  fit_one <- PAGe:::m2_subset_fit(d, config$h1)
  m2 <- PAGe:::.new_stage_fit("m2", selection, config, list(
    family = PAGe:::m2_subset_family(), fit = list(h1 = fit_one, h2 = fit_one),
    feature_ranges = list(h1 = list(), h2 = list()), m1_train_preds = data.frame(),
    spec = config, training_seasons = "a"
  ), upstream_ids = list(m0 = m0$artifact_id, m1 = m1$artifact_id), data_id = "data")
  frozen <- PAGe::freeze_m2(m2)
  expect_equal(frozen$status, "frozen")
  path <- tempfile(fileext = ".rds")
  saveRDS(frozen, path)
  expect_identical(readRDS(path), frozen)
  tampered <- frozen
  tampered$fit$h1$type <- "gam"
  expect_error(PAGe::assemble_kit(m0, m1, tampered), "integrity")
  wrong_chain <- frozen
  wrong_chain$upstream_ids$m1 <- "other"
  wrong_chain$artifact_id <- PAGe:::.stage_artifact_id(
    "m2", wrong_chain$selection, wrong_chain$config,
    wrong_chain$upstream_ids, wrong_chain$data_id,
    PAGe:::.stage_fit_payload(wrong_chain)
  )
  expect_error(PAGe::assemble_kit(m0, m1, wrong_chain), "identity mismatch")
})

test_that("invalid family and weekly refit are rejected explicitly", {
  expect_error(PAGe:::m2_subset_validate_config(list(family = "legacy")), "offset_subset_v1")
  expect_error(
    PAGe::validate_page_kit(list(
      m0_params = list(x = 1), ref = list(anchorWeek = 20),
      hyper = list(), M1_PARAMS = list(
        temperature = .25, rise_weight = 1,
        trough_weight = .1, peak_decay = .3, slope_weight = 8, slope_window = 6,
        dynamic_temp = FALSE, dynamic_temp_pivot = 10
      ), best_spec = list(family = "bad"),
      m2_production = list(family = "bad", fit = list())
    ), mode = "frozen"),
    "Unsupported M2 model family"
  )
})

test_that("subset tuning selects h1 and h2 by complete inner-season NLL", {
  obs <- do.call(rbind, lapply(c("a", "b"), function(s) {
    data.frame(
      season = s, weekF = 1:8, y = c(1, 2, 3, 4, 5, 4, 3, 2), N = 20,
      nW_true = 8L
    )
  }))
  preds <- do.call(rbind, lapply(c("a", "b"), function(s) {
    data.frame(
      season = s, eval_weekF = 3:6, target_weekF = 4:7,
      h = 1L, m1_p_hat = .2
    )
  }))
  preds2 <- transform(preds, h = 2L, target_weekF = eval_weekF + 2L)
  preds <- rbind(preds, preds2)
  detector <- function(currentSeason, params, start_week) {
    list(
      ign_week_locked = 2L,
      df = data.frame(weekF = currentSeason$weekF, ignite_ok_now = currentSeason$weekF == 2L)
    )
  }
  selection <- structure(list(
    training_seasons = c("a", "b"), exclude_seasons = character(),
    holdout_seasons = character(), application_seasons = character(),
    data_seasons = c("a", "b")
  ), class = "page_season_selection")
  m0 <- list(best_params = list())
  m1 <- list(m1_params = list())
  tuning <- PAGe:::m2_subset_tune(
    obs, selection, m0, m1,
    grid = PAGe:::m2_subset_grid()[1:2, , drop = FALSE],
    m1_train_preds = preds, detector = detector
  )
  expect_silent(PAGe::validate_m2_tuning(tuning))
  expect_true(all(c("h1", "h2") %in% names(tuning$selected_config)))
  expect_true(grepl("^h1:i", tuning$best_spec_id))
})
