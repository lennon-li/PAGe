# .nested_inner_gate_rows() re-selects M0 per gate-excluded season and
# explicitly strips that season's own manual timing label before re-fitting
# M0 (`labels <- manual_labels[names(manual_labels) != season]`), but its
# subsequent m2_subset_make_rows() call for the gate's M2 features passed
# the FULL, unfiltered timing_truth through -- so the excluded season's own
# test rows still got its true (manual) ignition week instead of a nested
# M0 detection, unlike every other axis in the same function. Fixed by
# stripping the excluded season from timing_truth before that call too.

test_that(".nested_inner_gate_rows strips the gate season's own row from timing_truth", {
  recorded <- list()

  fake_make_rows <- function(data, m0, m1, m1_train_preds = NULL,
                             seasons = character(0),
                             alpha_state = 0.2,
                             timing_mode = "legacy",
                             timing_truth = NULL, ...) {
    recorded[[length(recorded) + 1]] <<- timing_truth
    list(data = data.frame(
      season = character(0), forecast_available = logical(0),
      stringsAsFactors = FALSE
    ))
  }
  fake_cache <- list(predictions = list())

  testthat::local_mocked_bindings(
    m2_subset_make_rows = fake_make_rows,
    .nested_m1_cache = function(...) fake_cache,
    .package = "PAGe"
  )

  truth <- data.frame(
    season = c("2011-12", "2012-13"),
    ignition_target_weekF = c(10.5, 12.5),
    stringsAsFactors = FALSE
  )
  tuning <- list(
    training_rows = data.frame(season = "2011-12", h = 1L, stringsAsFactors = FALSE),
    selected_config = list(gamma = 1),
    alpha_state = 0.2
  )

  # No inner-fold rows survive the empty stub, so the function errors after
  # visiting every season -- that's fine, we only need the capture.
  testthat::expect_error(
    PAGe:::.nested_inner_gate_rows(
      tuning = tuning,
      seasons = c("2011-12", "2012-13"),
      data = data.frame(season = c("2011-12", "2012-13"), stringsAsFactors = FALSE),
      m0 = list(), m1 = list(),
      timing_mode = "fractional",
      timing_truth = truth,
      gate_nesting = "conditional"
    ),
    "No inner-fold"
  )

  expect_length(recorded, 2L)
  by_season <- stats::setNames(recorded, c("2011-12", "2012-13"))

  expect_identical(by_season[["2011-12"]]$season, "2012-13")
  expect_identical(by_season[["2012-13"]]$season, "2011-12")
})
