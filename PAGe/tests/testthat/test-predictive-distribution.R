make_distribution_calibration_rows <- function() {
  data.frame(
    season = rep(c("s1", "s2", "s3"), each = 3),
    lead = "h1", eval_week = rep(5:7, 3),
    p_hat = rep(c(0.1, 0.2, 0.3), 3),
    y_lead = c(0, 2, 4, 1, 2, 7, 1, 3, 20),
    N_lead = c(100, 10, 10, 10, 8, 20, 20, 20, 20)
  ) |>
    transform(p_obs = y_lead / N_lead)
}

test_that("sample-based predictive distributions answer strict threshold queries", {
  d <- new_page_predictive_distribution(
    c(0.01, 0.02, 0.02, 0.04),
    outcome = "positivity_observed"
  )

  expect_equal(as.numeric(probability_above(d, 0.02)), 0.25)
  expect_equal(as.numeric(probability_above(d, 0.02, inclusive = TRUE)), 0.75)
  expect_equal(as.numeric(probability_below(d, 0.02)), 0.25)
  expect_equal(as.numeric(probability_below(d, 0.02, inclusive = TRUE)), 0.75)
  expect_equal(distribution_cdf(d, c(0.01, 0.02)), c(0.25, 0.75))
  expect_equal(distribution_quantile(d, c(0.25, 0.5)), c(0.01, 0.02))
  expect_equal(
    attr(probability_above(d, 0.02), "mc_se"),
    sqrt(0.25 * 0.75 / 4)
  )
  expect_length(attr(probability_above(d, 0.99), "mc_interval"), 2L)
  expect_true(is.na(attr(probability_above(d, 0.99), "mc_se")))
})

test_that("weighted distributions calculate exact weighted summaries", {
  d <- new_page_predictive_distribution(
    c(1, 2, 3),
    outcome = "season_peak_week", scale = "weekF",
    support = c(1, 3), weights = c(1, 2, 1),
    target = list(n_weeks = 3), status = "experimental"
  )
  expect_equal(distribution_cdf(d, c(1, 2, 3)), c(0.25, 0.75, 1))
  expect_equal(as.numeric(probability_below(d, 2)), 0.25)
  expect_equal(as.numeric(probability_below(d, 2, inclusive = TRUE)), 0.75)
  expect_true(is.na(attr(probability_below(d, 2), "mc_se")))
  expect_true(all(is.na(attr(probability_below(d, 2), "mc_interval"))))
  expect_equal(distribution_quantile(d, 0.5), 2)
  expect_equal(distribution_quantile(d, 0.6), 2)
  expect_equal(distribution_weights(d), c(0.25, 0.5, 0.25))
  expect_error(
    new_page_predictive_distribution(c(1, 2), "x", support = c(1, 2), weights = c(0, 0)),
    "positive sum"
  )
})

test_that("peak-week API uses exact weighted atoms and explicit origin semantics", {
  forecast <- structure(list(
    season = "s1",
    m1_peak_ensemble = tibble::tibble(
      eval_week = c(10L, 11L), season = "s1", latest_data_week = 11L,
      iWeek_hat = 5L, anchorWeek = 10L, nW_true = 52L,
      timing_mode = "legacy", alignment_config_id = "fixture-v1",
      status = c("available", "unavailable"),
      fallback_reason = c(NA_character_, "alignment_failed"),
      template = list(c("a", "b"), character()),
      t_peak = list(c(10, 12), numeric()),
      weight = list(c(0.5, 0.5), numeric())
    )
  ), class = c("page_forecast", "list"))

  d <- peak_week_distribution(forecast, origin_week = 10L)
  expect_identical(d$status, "experimental")
  expect_equal(d$draws, c(5, 7))
  expect_equal(d$weights, c(0.5, 0.5))
  expect_equal(as.numeric(probability_peak_before(d, 7)), 0.5)
  expect_equal(as.numeric(probability_peak_before(d, 7, inclusive = TRUE)), 1)
  p <- probability_peak_before(forecast, 6, origin_week = 10L)
  expect_equal(as.numeric(p), 0.5)
  expect_true(attr(p, "partly_observed"))

  latest <- peak_week_distribution(forecast)
  expect_identical(latest$status, "unavailable")
  expect_error(probability_peak_before(forecast, 20), "forecast is unavailable")
  bad_season <- forecast
  bad_season$m1_peak_ensemble$season[1] <- NA_character_
  expect_error(peak_week_distribution(bad_season), "season does not match")
  bad_season <- forecast
  bad_season$m1_peak_ensemble$season[1] <- "s2"
  expect_error(peak_week_distribution(bad_season), "season does not match")
  missing_season <- forecast
  missing_season$season <- NA_character_
  expect_error(peak_week_distribution(missing_season), "exactly one season")
  expect_error(
    probability_peak_before(
      new_page_predictive_distribution(1:2, "other", support = c(0, 52), target = list(n_weeks = 52)),
      10
    ),
    "outcome `season_peak_week`"
  )
})

test_that("peak-week adapter records dropped support mass and fractional timing", {
  forecast <- structure(list(
    season = "s1",
    m1_peak_ensemble = tibble::tibble(
      eval_week = 8L, season = "s1", latest_data_week = 8L,
      iWeek_hat = 1.5, anchorWeek = 10, nW_true = 52L,
      timing_mode = "fractional", alignment_config_id = "fixture-v1",
      status = "available",
      fallback_reason = NA_character_, template = list(letters[1:3]),
      t_peak = list(c(9.5, 10.5, 100)), weight = list(c(0.25, 0.25, 0.5))
    )
  ), class = c("page_forecast", "list"))
  d <- peak_week_distribution(forecast)
  expect_equal(d$draws, c(1, 2))
  expect_equal(d$weights, c(0.5, 0.5))
  expect_equal(d$calibration$dropped_mass, 0.5)
  expect_true(attr(probability_peak_before(d, 1.5), "partly_observed"))
  expect_true(attr(probability_peak_before(d, 8), "partly_observed"))
  expect_false(attr(probability_peak_before(d, 10), "partly_observed"))
  expect_equal(as.numeric(probability_peak_before(d, 1.5)), 0.5)
})

test_that("peak-week adapter refuses collapsed atoms and handles an empty walk", {
  collapsed <- structure(list(
    season = "s1",
    m1_peak_ensemble = tibble::tibble(
      eval_week = 8L, season = "s1", latest_data_week = 8L,
      iWeek_hat = 5L, anchorWeek = 10L, nW_true = 52L,
      timing_mode = "legacy", alignment_config_id = "fixture-v1",
      status = "available",
      fallback_reason = NA_character_, template = list(c("a", "b")),
      t_peak = list(c(10.1, 10.3)), weight = list(c(0.5, 0.5))
    )
  ), class = c("page_forecast", "list"))
  expect_identical(peak_week_distribution(collapsed)$status, "unavailable")
  expect_identical(
    peak_week_distribution(collapsed)$provenance$reason,
    "insufficient_effective_peak_atoms"
  )
  empty <- structure(
    list(season = "s1", m1_peak_ensemble = tibble::tibble()),
    class = c("page_forecast", "list")
  )
  expect_identical(peak_week_distribution(empty)$provenance$reason, "no_m1_origins")
})

test_that("M1 runtime forwards its peak atoms into the forecast result", {
  peak_atoms <- data.frame(
    template = c("sA", "sB"), t_peak = c(12, 14), weight = c(0.5, 0.5)
  )
  local_mocked_bindings(
    run_alignment_prospective_multi = function(...) {
      list(
        state = "aligning", iWeek_hat = 10, tau = 1, delta = 0,
        a = 0, b = 0, t_peak = 13, peak_weekF = 13,
        peak_weekF_lo = 12, peak_weekF_hi = 14,
        peak_passed = FALSE, fallback_reason = NA_character_,
        peak_ensemble = peak_atoms,
        forecast_df = data.frame(newWeek = 1, p_hat = 0.1)
      )
    },
    .package = "PAGe"
  )
  current_data <- data.frame(
    season = "s1", weekF = 10:11, week = 36:37,
    nW_true = 52L, y = c(2, 3), neg = c(98, 97)
  )
  result <- run_m1_alignment(
    kit = list(
      ref = list(anchorWeek = 10), hyper = list(),
      M1_PARAMS = list(
        temperature = 0.25, rise_weight = 1, trough_weight = 0.1,
        peak_decay = 0.3, slope_weight = 8, slope_window = 6,
        dynamic_temp = FALSE, dynamic_temp_pivot = 10,
        spread_method = "between"
      )
    ),
    current_data = current_data,
    m0_result = list(iWeek_locked = 10L, ign_out = list()),
    walk_start = 10L, verbose = FALSE
  )
  forecast <- structure(
    list(season = "s1", m1_peak_ensemble = result$m1_peak_ensemble),
    class = c("page_forecast", "list")
  )
  expect_identical(result$m1_peak_ensemble$status, c("available", "available"))
  expect_equal(result$m1_peak_ensemble$latest_data_week, c(10, 11))
  expect_equal(as.numeric(probability_peak_before(forecast, 14)), 0.5)
})

test_that("forecast calibrator uses season-balanced out-of-sample residuals", {
  calibration_rows <- make_distribution_calibration_rows()
  calibrator <- fit_forecast_calibrator(
    calibration_rows,
    predictor_id = "page-m2-protocol-v1",
    out_of_sample = TRUE
  )
  forecast <- structure(
    list(
      season = "s4",
      predictor_id = "page-m2-protocol-v1",
      m2_preds = data.frame(
        eval_week = c(10L, 11L), h = 1L,
        target_weekF = c(11L, 12L),
        forecast_available = TRUE, m2_p = c(0.15, 0.25)
      )
    ),
    class = c("page_forecast", "list")
  )

  set.seed(991)
  rng_before <- .Random.seed
  dist_a <- predictive_distribution(forecast, calibrator, seed = 42L, n_draws = 500L)
  expect_identical(.Random.seed, rng_before)
  dist_b <- predictive_distribution(forecast, calibrator, seed = 42L, n_draws = 500L)

  expect_identical(distribution_draws(dist_a), distribution_draws(dist_b))
  expect_equal(dist_a$origin, list(week = 11L, season = "s4"))
  expect_equal(dist_a$target, list(week = 12L, season = "s4"))
  expect_equal(dist_a$horizon, 1L)
  expect_identical(dist_a$status, "experimental")
  expect_true(all(distribution_draws(dist_a) > 0))
  expect_true(all(distribution_draws(dist_a) < 1))
  expect_true(all(distribution_draws(dist_a) > 0.001))
  expect_true(all(distribution_draws(dist_a) < 0.999))
  expect_equal(
    dist_a$calibration$n_seasons,
    calibrator$seasons_per_horizon[["1"]]
  )
  expect_true(nzchar(dist_a$provenance$calibrator_id))
  expect_true(length(dist_a$calibration$rng_kind) >= 2L)
  expect_true(nzchar(dist_a$calibration$r_version))
})

test_that("forecast calibration fails closed without OOS attestation or support", {
  rows <- data.frame(
    season = c("s1", "s2", "s3"), lead = "h1", eval_week = 5L,
    p_hat = 0.1, y_lead = c(1, 2, 3), N_lead = 20
  ) |>
    transform(p_obs = y_lead / N_lead)
  expect_error(
    fit_forecast_calibrator(rows, predictor_id = "p1"),
    "out_of_sample = TRUE"
  )
  expect_error(
    fit_forecast_calibrator(
      rows[rows$season != "s3", ],
      predictor_id = "p1", out_of_sample = TRUE
    ),
    "At least 3 seasons"
  )
})

test_that("unavailable forecasts remain explicit", {
  rows <- data.frame(
    season = c("s1", "s2", "s3"), lead = "h1", eval_week = 5L,
    p_hat = 0.1, y_lead = c(1, 2, 3), N_lead = 20
  ) |>
    transform(p_obs = y_lead / N_lead)
  calibrator <- fit_forecast_calibrator(
    rows,
    predictor_id = "p1", out_of_sample = TRUE
  )
  forecast <- structure(
    list(
      season = "s4", predictor_id = "p1",
      m2_preds = data.frame(
        eval_week = 12L, h = 1L, target_weekF = 13L,
        forecast_available = FALSE, m2_p = NA_real_,
        unavailable_reason = "out_of_season"
      )
    ),
    class = c("page_forecast", "list")
  )
  dist <- predictive_distribution(forecast, calibrator)

  expect_identical(dist$status, "unavailable")
  expect_length(distribution_draws(dist), 0L)
  expect_error(probability_above(dist, 0.02), "forecast is unavailable")
  expect_error(distribution_quantile(dist), "forecast is unavailable")
})

test_that("single-origin seasons are sampled by index without sample length-one traps", {
  rows <- data.frame(
    season = c("s1", "s2", "s3"), lead = "h1",
    eval_week = 5L, p_hat = 0.2, p_obs = c(0.05, 0.2, 0.6)
  )
  rows$y_lead <- c(1, 4, 12)
  rows$N_lead <- 20
  calibrator <- fit_forecast_calibrator(
    rows,
    predictor_id = "p1", out_of_sample = TRUE
  )
  forecast <- structure(
    list(
      season = "s4", predictor_id = "p1",
      m2_preds = data.frame(
        eval_week = 10L, h = 1L, target_weekF = 11L,
        forecast_available = TRUE, m2_p = 0.2
      )
    ),
    class = c("page_forecast", "list")
  )
  d <- predictive_distribution(forecast, calibrator, n_draws = 6000L, seed = 3L)
  q <- distribution_draws(d)
  breaks <- sort(unique(q))
  counts <- tabulate(match(q, breaks), nbins = length(breaks)) / length(q)

  expect_length(breaks, 3L)
  expect_true(all(abs(counts - 1 / 3) < 0.04))
})

test_that("zero-denominator replay rows are excluded and season leakage is refused", {
  rows <- data.frame(
    season = c("s1", "s2", "s3", "s3"), lead = "h1",
    eval_week = 5:8,
    p_hat = c(0.1, 0.2, 0.3, 0.4),
    p_obs = c(0.1, 0.2, 0.3, 0),
    y_lead = c(1, 2, 3, 0), N_lead = c(10, 10, 10, 0)
  )
  expect_message(
    calibrator <- fit_forecast_calibrator(
      rows,
      predictor_id = "p1", out_of_sample = TRUE
    ),
    "1 invalid"
  )
  expect_equal(calibrator$n_dropped, 1L)
  forecast <- structure(
    list(
      season = "s3", predictor_id = "p1",
      m2_preds = data.frame(
        eval_week = 10L, h = 1L, target_weekF = 11L,
        forecast_available = TRUE, m2_p = 0.2
      )
    ),
    class = c("page_forecast", "list")
  )
  expect_error(predictive_distribution(forecast, calibrator), "present in the calibrator")
  expect_error(
    predictive_distribution(forecast, calibrator, predictor_id = "other"),
    "matching the calibrator"
  )
})

test_that("calibration validates canonical keys, targets, and identity", {
  rows <- make_distribution_calibration_rows()
  rows$season <- rep(c("2023-24", "2024-25", "2025-26"), each = 3)
  duplicate <- rows[1L, , drop = FALSE]
  duplicate$season <- "2023/24"
  duplicate$lead <- 1L
  rows <- rbind(rows, duplicate)
  expect_error(
    fit_forecast_calibrator(rows, predictor_id = "p1", out_of_sample = TRUE),
    "Duplicate season/origin/horizon"
  )

  rows <- make_distribution_calibration_rows()
  rows$target_weekF <- rows$eval_week + 1L
  rows$target_weekF[1L] <- 99L
  rows <- rbind(rows, transform(rows[1L, , drop = FALSE], eval_week = 9L, p_hat = 0))
  expect_no_message(expect_error(
    fit_forecast_calibrator(rows, predictor_id = "p1", out_of_sample = TRUE),
    "origin, horizon, and target"
  ))

  rows <- make_distribution_calibration_rows()
  calibrator <- fit_forecast_calibrator(
    rows,
    predictor_id = "p1", out_of_sample = TRUE
  )
  tampered <- calibrator
  tampered$residuals$residual[1L] <- tampered$residuals$residual[1L] + 0.1
  forecast <- structure(list(
    season = "s4", predictor_id = "p1",
    m2_preds = data.frame(
      eval_week = 10L, h = 1L, target_weekF = 11L,
      forecast_available = TRUE, m2_p = 0.2
    )
  ), class = c("page_forecast", "list"))
  expect_error(predictive_distribution(forecast, tampered), "modified after fitting")
  forecast$m2_preds$m2_p <- 0
  expect_error(predictive_distribution(forecast, calibrator), "does not support extrapolation")
  expect_error(predictive_distribution(list(), calibrator), "No .* method is registered")
})

test_that("calibration drops clipped forecasts and unavailable count outcomes clearly", {
  rows <- make_distribution_calibration_rows()
  rows$p_hat[1L] <- 0
  rows$y_lead[2L] <- NA_real_
  rows$p_obs[2L] <- NA_real_
  expect_message(
    calibrator <- fit_forecast_calibrator(
      rows,
      predictor_id = "p1", out_of_sample = TRUE
    ),
    "forecast_at_or_beyond_logit_clip=1, outcome_unavailable_or_nonfinite=1"
  )
  expect_equal(calibrator$n_dropped, 2L)
  expect_error(
    expect_no_message(fit_forecast_calibrator(
      rows,
      predictor_id = "p1", out_of_sample = TRUE, eps = 0
    )),
    "`eps` must"
  )
})

test_that("forecast method rejects multiple seasons and unused arguments", {
  rows <- make_distribution_calibration_rows()
  calibrator <- fit_forecast_calibrator(
    rows,
    predictor_id = "p1", out_of_sample = TRUE
  )
  forecast <- structure(list(
    season = "s4", predictor_id = "p1",
    m2_preds = data.frame(
      season = c("s4", "s5"), eval_week = c(10L, 11L),
      h = 1L, target_weekF = c(11L, 12L),
      forecast_available = TRUE, m2_p = c(0.2, 0.3)
    )
  ), class = c("page_forecast", "list"))
  expect_error(predictive_distribution(forecast, calibrator), "exactly one season")
  expect_error(
    predictive_distribution(forecast, calibrator, extra = TRUE),
    "Unused arguments"
  )
})
