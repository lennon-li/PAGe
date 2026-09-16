test_that("subset train_m2 applies exclusions before delegating", {
  captured <- NULL
  local_mocked_bindings(
    m2_subset_train = function(data, ...) {
      captured <<- data
      list(ok = TRUE)
    },
    .package = "PAGe"
  )
  data <- data.frame(
    season = c("keep", "drop"), weekF = 1:2, y = 1, N = 10
  )
  out <- PAGe::train_m2(
    data,
    m0 = list(), m1 = list(),
    best_spec = list(family = PAGe:::m2_subset_family()),
    exclude = "drop"
  )
  expect_true(out$ok)
  expect_identical(as.character(captured$season), "keep")
})

.audit_selection <- function(seasons = c("a", "b")) {
  structure(list(
    training_seasons = seasons, exclude_seasons = character(),
    holdout_seasons = character(), application_seasons = character(),
    data_seasons = seasons
  ), class = "page_season_selection")
}

.audit_subset_tuning <- function() {
  seasons <- c("a", "b")
  grid <- PAGe:::m2_subset_grid()[1:2, , drop = FALSE]
  scores <- expand.grid(
    spec_id = grid$id, season = seasons, horizon = 1:2,
    stringsAsFactors = FALSE
  )
  scores$bernoulli_nll <- 0.4
  scores$mae <- 0.1
  scores$rows <- 2
  scores$trials <- 20
  scores$scheduled_rows <- 2
  scores$available_rows <- 2
  scores$unavailable_rows <- 0
  scores$coverage_key <- "a"
  scores$status <- "ok"
  summary <- expand.grid(
    spec_id = grid$id, horizon = 1:2, stringsAsFactors = FALSE
  )
  summary$bernoulli_nll <- 0.4
  summary$n_seasons <- length(seasons)
  training_rows <- data.frame(
    season = rep(seasons, each = 2), eval_weekF = 1:4,
    target_weekF = 2:5, h = 1L, lead = factor("h1", levels = c("h1", "h2")),
    m1_p = 0.2, m1_logit = 0, z = 0, u = 1, d = 0,
    tau = 0, peak_weekF_origin = 3, peak_ci_width = 1,
    ignition_weekF = 2, observed_peak_weekF = 3,
    phase = "turning", weight_page_v2 = 3, weight_legacy = 2,
    y_lead = 1, N_lead = 10,
    forecast_available = TRUE, unavailable_reason = NA_character_
  )
  preds <- data.frame(
    season = rep(seasons, each = 2), eval_weekF = 1:4,
    target_weekF = 2:5, h = 1L, m1_p_hat = 0.2,
    peak_weekF_origin = 3, peak_ci_width = 1,
    forecast_available = TRUE, unavailable_reason = NA_character_
  )
  config <- PAGe:::m2_subset_config(h1 = grid[1, ], h2 = grid[1, ])
  out <- list(
    family = PAGe:::m2_subset_family(), grid = grid, scores = scores,
    summary = summary, selected = list(grid[1, ], grid[1, ]),
    selected_config = config,
    best_spec_id = paste0("h1:", grid$id[1], "|h2:", grid$id[1]),
    selection = .audit_selection(seasons), data_id = "data-id",
    training_rows = training_rows, m1_train_preds = preds,
    declaration_provenance = "prefix-safe declarations", alpha_state = 0.2
  )
  structure(out, class = c("page_m2_subset_tuning", "page_m2_tuning", "list"))
}

test_that("subset tuning rejects incomplete, non-finite, or non-ok folds", {
  tuning <- .audit_subset_tuning()
  expect_silent(PAGe::validate_m2_tuning(tuning))

  incomplete <- tuning
  incomplete$scores <- incomplete$scores[-1L, , drop = FALSE]
  expect_error(PAGe::validate_m2_tuning(incomplete), "complete")

  duplicate <- tuning
  duplicate$scores <- rbind(duplicate$scores, duplicate$scores[1L, ])
  expect_error(PAGe::validate_m2_tuning(duplicate), "duplicated")

  nonfinite <- tuning
  nonfinite$scores$bernoulli_nll[1L] <- NA_real_
  expect_error(PAGe::validate_m2_tuning(nonfinite), "finite")

  failed <- tuning
  failed$scores$status[1L] <- "failed"
  expect_error(PAGe::validate_m2_tuning(failed), "successful")
})

test_that("subset tuning checks selected/grid identity and provenance", {
  tuning <- .audit_subset_tuning()
  bad_switch <- tuning
  bad_switch$selected[[1L]]$k_z <- 3L
  expect_error(PAGe::validate_m2_tuning(bad_switch), "identity")

  bad_config_switch <- tuning
  bad_config_switch$selected_config$h1$k_z <- 3L
  expect_error(PAGe::validate_m2_tuning(bad_config_switch), "identity")

  bad_config_count <- tuning
  bad_config_count$selected_config$h1$enabled_count <- 1L
  expect_error(PAGe::validate_m2_tuning(bad_config_count), "identity")

  bad_selected_id <- tuning
  bad_selected_id$selected[[1L]]$id <- "i0_kz3_ku0_kd0"
  expect_error(PAGe::validate_m2_tuning(bad_selected_id), "identity")

  bad_selected_count <- tuning
  bad_selected_count$selected[[1L]]$enabled_count <- 1L
  expect_error(PAGe::validate_m2_tuning(bad_selected_count), "identity")

  bad_provenance <- tuning
  bad_provenance$declaration_provenance <- NULL
  expect_error(PAGe::validate_m2_tuning(bad_provenance), "provenance")
})

test_that("subset tuning permits omitted unselected failed candidates", {
  tuning <- .audit_subset_tuning()
  failed_id <- tuning$grid$id[2L]
  failed <- tuning$scores$spec_id == failed_id
  tuning$scores$status[failed] <- "failed"
  tuning$scores$bernoulli_nll[failed] <- NA_real_
  tuning$scores$mae[failed] <- NA_real_
  tuning$scores$rows[failed] <- 0
  tuning$scores$trials[failed] <- 0
  tuning$summary <- tuning$summary[tuning$summary$spec_id != failed_id, , drop = FALSE]
  expect_silent(PAGe::validate_m2_tuning(tuning))
})

test_that("subset freeze rejects non-subset tuning evidence", {
  selection <- .audit_selection("a")
  config <- PAGe:::m2_subset_config()
  fit <- PAGe:::.new_stage_fit(
    "m2", selection, config,
    payload = list(
      family = PAGe:::m2_subset_family(), fit = list(),
      feature_ranges = list(), m1_train_preds = data.frame(),
      spec = config, training_seasons = "a"
    ),
    data_id = "data-id"
  )
  expect_error(
    PAGe::freeze_m2(fit, tuning = structure(list(), class = "page_m2_tuning")),
    "wrong class"
  )
  expect_silent(PAGe::freeze_m2(fit))
})

test_that("subset runtime preserves point forecasts and interval columns", {
  config <- PAGe:::m2_subset_config()
  fit_one <- PAGe:::m2_subset_fit(data.frame(
    season = rep("a", 4), lead = rep(c("h1", "h2"), 2),
    m1_logit = 0, y_lead = 1, N_lead = 10
  ), config$h1)
  kit <- list(
    ref = list(anchorWeek = 20), m0_params = list(), best_spec = config,
    m2_production = list(family = config$family, fit = list(h1 = fit_one, h2 = fit_one))
  )
  per_week <- list(list(
    ew = 5L, ap = list(
      state = "aligning", iWeek_hat = 3L,
      forecast_df = data.frame(
        newWeek = 1:52, p_hat = seq(.1, .9, length.out = 52)
      )
    ),
    season_to_ew = data.frame(season = "current", weekF = 1:5, y = 1:5, N = 10)
  ))
  result <- PAGe:::m2_subset_runtime_prediction(
    kit, per_week[[1L]]$season_to_ew, list(per_week = per_week),
    verbose = FALSE
  )
  expect_true(all(c("m2_p", "m2_lo", "m2_hi") %in% names(result$m2_preds)))
  expect_true(all(is.finite(result$m2_preds$m2_p)))
  expect_true(all(is.na(result$m2_preds$m2_lo)))
  plot_data <- PAGe:::.as_forecast_plot_data(
    result$m2_preds, per_week[[1L]]$season_to_ew
  )
  expect_true(any(plot_data$pred_df$kind == "forecast"))

  empty <- PAGe:::m2_subset_runtime_prediction(
    kit, per_week[[1L]]$season_to_ew, list(per_week = list()),
    verbose = FALSE
  )
  expect_equal(nrow(empty$m2_preds), 0L)
  expect_true(all(c("m2_p", "m2_lo", "m2_hi") %in% names(empty$m2_preds)))
})

test_that("prepare_page_data validates MMWR week 53 by implied year", {
  make_data <- function(season, week) {
    data.frame(season = season, week = week, y = 1, N = 10)
  }
  valid <- PAGe::prepare_page_data(
    make_data("2025-26", 53L), "y", "week", "season", "N",
    week_type = "mmwr"
  )
  expect_equal(valid$weekF, 27)
  expect_error(
    PAGe::prepare_page_data(
      make_data("2023-24", 53L), "y", "week", "season", "N",
      week_type = "mmwr"
    ),
    "invalid"
  )
  start_one <- PAGe::prepare_page_data(
    make_data("2025-26", 53L), "y", "week", "season", "N",
    week_type = "mmwr", start_week = 1L
  )
  expect_equal(start_one$weekF, 53)
  rollover <- PAGe::prepare_page_data(
    make_data("2025-26", 1L), "y", "week", "season", "N",
    week_type = "mmwr", start_week = 27L
  )
  expect_equal(rollover$weekF, 28)
})

test_that("subset config and switches reject unsupported or malformed values", {
  expect_error(PAGe:::m2_subset_config(bs = "tp"), "only")
  expect_error(PAGe:::m2_subset_spec(z = 1), "logical")
  expect_error(PAGe:::m2_subset_spec(z = NA), "logical")
  expect_error(PAGe:::m2_subset_spec(z = "TRUE"), "logical")

  bad_grid <- PAGe:::m2_subset_grid()[1:2, , drop = FALSE]
  bad_grid$k_z <- 1
  expect_error(
    PAGe:::m2_subset_tune(
      data.frame(season = "a", weekF = 1, y = 1, N = 10),
      .audit_selection("a"), list(best_params = list()), list(),
      grid = bad_grid
    ),
    "integer"
  )
})
