make_metric_predictions <- function(scale = 1, spec_id = NULL) {
  out <- data.frame(
    season = rep(c("2022-23", "2023-24"), each = 4),
    weekF = rep(1:4, 2),
    lead = rep(c(1L, 2L), 4),
    t_since = rep(c(-1, 1, 5, 8), 2),
    p_hat = c(.10, .20, .30, .40, .12, .22, .32, .42) * scale,
    p_obs = c(.11, .18, .33, .38, .13, .20, .35, .40),
    N_lead = 100L
  )
  out$y_lead <- round(out$p_obs * out$N_lead)
  if (!is.null(spec_id)) out$spec_id <- spec_id
  out
}

test_that("forecast metrics are deterministic and promotion gates are transparent", {
  incumbent <- PAGe::summarize_forecast_metrics(make_metric_predictions(1.08))
  candidate <- PAGe::summarize_forecast_metrics(make_metric_predictions(1.00))

  expect_named(candidate, c("overall", "horizon", "phase"))
  expect_named(candidate$overall, c("bernoulli_nll", "mae", "n_trials", "n_predictions"))
  expect_setequal(candidate$phase$phase, c("pre_ignition", "early", "late"))

  report <- PAGe::check_promotion(candidate, incumbent)
  expect_s3_class(report, "page_promotion_report")
  expect_named(
    report,
    c(
      "schema", "schema_version", "pass", "gates", "reasons",
      "thresholds", "details"
    )
  )
  expect_identical(report$schema, "page_promotion_report")
  expect_identical(report$schema_version, 1L)
  expect_type(report$pass, "logical")
  expect_true(all(c("nll", "horizon", "phase") %in% report$gates$gate))
  expect_named(report$details, c("horizon", "phase"))

  identical_metrics <- PAGe::check_promotion(candidate, candidate)
  expect_false(identical_metrics$pass)
  expect_match(paste(identical_metrics$reasons, collapse = " "), "NLL")
})

test_that("M2 candidate selection supports min-NLL, one-SE, and Pareto", {
  grid <- data.frame(
    spec_id = c("simple", "middle", "complex"),
    k_f = c(2L, 4L, 8L), k_e = 2L, k_r = 0L, k_de = 0L, k_sp = 0L, Kr = 1L
  )
  scores <- data.frame(
    spec_id = rep(grid$spec_id, each = 4), season = rep(letters[1:4], 3),
    bernoulli_nll = c(.405, .415, .40, .42, .36, .44, .36, .44, .39, .41, .40, .40)
  )
  summary <- data.frame(
    spec_id = grid$spec_id,
    bernoulli_nll = c(.410, .400, .400),
    horizon_mae = c(.08, .07, .09), phase_mae = c(.09, .07, .08)
  )
  result <- list(summary = summary, scores = scores, grid = grid)

  expect_identical(PAGe::select_m2_candidate(result)$selected_spec_id, "middle")
  one_se <- PAGe::select_m2_candidate(result, method = "one_se")
  expect_identical(one_se$selected_spec_id, "simple")
  pareto <- PAGe::select_m2_candidate(result, method = "pareto")
  expect_identical(pareto$selected_spec_id, "middle")
  expect_setequal(pareto$pareto_set$spec_id, "middle")
  expect_error(
    PAGe::select_m2_candidate(list(summary = summary[1:2], grid = grid), "pareto"),
    "horizon.*phase"
  )
})

test_that("racing retains uncertainty-overlapping candidates and requires full evaluation", {
  grid <- data.frame(spec_id = letters[1:5], value = 1:5)
  evaluator <- function(grid, stage, ...) {
    means <- c(a = .40, b = .405, c = .44, d = .60, e = .80)[grid$spec_id]
    data.frame(
      spec_id = rep(grid$spec_id, each = 3),
      fold = rep(1:3, times = nrow(grid)),
      bernoulli_nll = rep(means, each = 3) + rep(c(-.01, 0, .01), nrow(grid))
    )
  }
  full <- function(grid, ...) list(grid = grid, fully_evaluated = TRUE)

  raced <- PAGe::race_m2_candidates(
    grid, evaluator, stages = c(3L, 6L), min_survivors = 2L,
    full_evaluator = full
  )
  expect_true(all(c("a", "b") %in% raced$survivors$spec_id))
  expect_true(raced$final$fully_evaluated)
  expect_identical(raced$final$grid, raced$survivors)
  expect_error(
    PAGe::race_m2_candidates(grid, evaluator, full_evaluator = NULL),
    "full_evaluator"
  )
})

test_that("unseen replay rejects leakage and returns standardized metrics", {
  allD <- workflow_surveillance(
    c("2024-25", "2025-26", "2025-26"), c(1L, 1L, 2L)
  )
  leaking <- list(m2 = list(training_seasons = c("2024-25", "2025-26")))
  expect_error(PAGe::replay_season_holdout(leaking, allD), "leakage")

  clean <- list(m2 = list(training_seasons = "2024-25"))
  runner <- function(kit, current_data, mode, verbose) {
    expect_identical(mode, "frozen")
    list(predictions = make_metric_predictions())
  }
  replay <- PAGe::replay_season_holdout(clean, allD, runner = runner)
  expect_identical(replay$season, "2025-26")
  expect_identical(replay$status, "unseen_replay_complete")
  expect_false(replay$eligible_for_refresh)
  expect_named(replay$metrics, c("overall", "horizon", "phase"))

  raw_runner <- function(kit, current_data, mode, verbose) {
    list(
      m2_preds = data.frame(
        eval_week = 1L, h = 1L, target_weekF = 2L, m2_p = .2
      ),
      ign_out = list(ign_week_locked = 1L)
    )
  }
  raw_data <- data.frame(
    season = c("2025-26", "2025-26"), weekF = 1:2,
    y = c(10, 20), N = 100, p = c(.1, .2)
  )
  raw_replay <- PAGe::replay_season_holdout(clean, raw_data, runner = raw_runner)
  expect_equal(raw_replay$predictions$p_obs, .2)
  expect_equal(raw_replay$predictions$t_since, 0)
})
