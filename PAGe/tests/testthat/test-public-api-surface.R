test_that("public namespace is compact and version-free", {
  expected <- c(
    "aggregate_strata", "aggregate_strata_draws", "check_promotion",
    "evaluate_forecasts", "m0_detect", "m0_fit", "m1_fit",
    "m1_passage_posterior", "m1_peak_posterior", "m1_predict",
    "m2_fit", "m2_predict", "page_forecast", "page_forecast_now",
    "page_label_ignitions", "page_load_kit", "page_load_surveillance",
    "page_models", "page_save_kit", "page_season_calendar", "page_train",
    "page_validate_kit", "page_walkforward_report", "plot_forecast",
    "prepare_surveillance_data", "replay_holdout", "season_selection",
    "shared_denominator_correlation", "validate_season_selection",
    "validate_surveillance_data", "verify_promotion"
  )
  exports <- sort(getNamespaceExports("PAGe"))
  expect_setequal(exports, expected)
  expect_false(any(grepl("(^|_)v[0-9]+(_|$)", exports)))
})

test_that("stable forecast wrappers reproduce current implementation", {
  fixture <- system.file(
    "extdata", "v3-week12", "report-support", "week12_panel_fixture.csv",
    package = "PAGe"
  )
  expect_true(nzchar(fixture))
  panel <- utils::read.csv(fixture, stringsAsFactors = FALSE)

  stable <- page_forecast(panel, season = "2026-27", origin_weekF = 12)
  internal <- PAGe:::page_v3_forecast(panel, season = "2026-27", origin_weekF = 12)
  expect_equal(stable$forecasts, internal$forecasts, tolerance = 1e-14)
  expect_identical(page_models()$release_id, PAGe:::page_v3_models()$release_id)
})

test_that("stable aggregation wrappers reproduce implementation", {
  args <- list(
    estimate = c(A = 0.05, B = 0.02),
    se = c(A = 0.004, B = 0.002),
    method = "sum",
    dependence = "shared_denominator",
    bounds = c(0, 1)
  )
  expect_equal(
    do.call(aggregate_strata, args),
    do.call(PAGe:::page_aggregate_strata, args),
    tolerance = 1e-14
  )
  expect_equal(
    shared_denominator_correlation(c(A = 0.05, B = 0.02)),
    PAGe:::page_shared_denominator_correlation(c(A = 0.05, B = 0.02)),
    tolerance = 1e-14
  )
})
