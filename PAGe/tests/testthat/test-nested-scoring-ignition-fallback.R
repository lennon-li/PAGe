# A true unseen holdout has no timing-truth entry (injecting one would be
# leakage) and no `ignition_weekF` column in the raw data, so
# .nested_scoring_export()'s existing lookup leaves ignition_weekF NA for
# every row of that season -- collapsing every row's phase to "censored"
# and its page_v2 weight to NA, which then makes the M1-vs-M2 decision
# error out with "No matched forecast rows remain with positive decision
# weight." (reproduced live against the 2025-26 outer holdout replay).
# observed_peak_weekF already has a data-driven fallback for this case;
# ignition_weekF did not. The fix adds one, sourced only from the replay's
# own runtime-locked detection (never a looked-up truth value).

test_that(".replay_ignition_override only trusts a locked, finite detection", {
  locked <- list(season = "2025-26", ignition_week = 18.91, ignition_status = "locked")
  expect_equal(
    PAGe:::.replay_ignition_override(locked),
    c(`2025-26` = 18.91)
  )

  not_available <- list(season = "2025-26", ignition_week = NA_real_, ignition_status = "not_available")
  expect_null(PAGe:::.replay_ignition_override(not_available))

  missing_status <- list(season = "2025-26", ignition_week = 18.91, ignition_status = NULL)
  expect_null(PAGe:::.replay_ignition_override(missing_status))
})

test_that(".nested_scoring_export leaves a truthless holdout censored without an override, and resolves it with one", {
  # No ignition_weekF column, no timing_labels covering this season --
  # exactly the true-holdout shape.
  data <- data.frame(
    season = "C", weekF = 1:4, y = c(1, 2, 3, 4), N = 10, nW_true = 4L,
    stringsAsFactors = FALSE
  )
  rows <- data.frame(
    season = "C", origin = c(1L, 1L, 2L, 2L), target = c(2L, 3L, 3L, 4L),
    horizon = c(1L, 2L, 1L, 2L), outcome = 0, m1_prediction = 0.2,
    m2_prediction = 0.1, t_since_target = c(1, 2, 13, 14), N_lead = 10,
    stringsAsFactors = FALSE
  )

  without_override <- PAGe:::.nested_scoring_export(rows, data)
  expect_true(all(is.na(without_override$ignition_weekF)))
  expect_true(all(without_override$phase == "censored"))
  expect_true(all(is.na(without_override$weight_page_v2)))

  with_override <- PAGe:::.nested_scoring_export(
    rows, data,
    ignition_overrides = c(C = 2)
  )
  expect_true(all(is.finite(with_override$ignition_weekF)))
  expect_true(all(with_override$ignition_weekF == 2))
  expect_false(any(with_override$phase == "censored"))
  expect_true(all(is.finite(with_override$weight_page_v2) & with_override$weight_page_v2 > 0))
})

test_that(".nested_scoring_export's override never clobbers a real timing-truth/data value", {
  data <- data.frame(
    season = "C", weekF = 1:4, y = c(1, 2, 3, 4), N = 10, nW_true = 4L,
    ignition_weekF = 3, stringsAsFactors = FALSE
  )
  rows <- data.frame(
    season = "C", origin = c(1L, 1L), target = c(2L, 3L),
    horizon = c(1L, 2L), outcome = 0, m1_prediction = 0.2,
    m2_prediction = 0.1, t_since_target = c(1, 2), N_lead = 10,
    stringsAsFactors = FALSE
  )
  out <- PAGe:::.nested_scoring_export(rows, data, ignition_overrides = c(C = 99))
  expect_true(all(out$ignition_weekF == 3))
})
