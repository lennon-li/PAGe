test_that("causal peak stabilization preserves decimals and bounds origin jumps", {
  first <- PAGe:::.m1_stabilize_peak(
    t_peak = 24.37,
    t_peak_ci = c(23.10, 25.80)
  )
  expect_equal(first$t_peak, 24.37)
  expect_equal(first$t_peak_ci, c(23.10, 25.80))

  second <- PAGe:::.m1_stabilize_peak(
    t_peak = 32.73,
    t_peak_ci = c(31.20, 34.40),
    previous_state = first,
    max_jump_weeks = 2
  )
  expect_equal(second$jump, 2)
  expect_equal(second$t_peak, 26.37)
  expect_equal(second$t_peak_ci, c(24.84, 28.04))
  expect_true(second$t_peak %% 1 != 0)
  expect_lte(abs(second$t_peak - first$t_peak), 2)
})

test_that("causal peak stabilization does not depend on future origins", {
  stabilize_prefix <- function(raw_peaks) {
    state <- NULL
    out <- numeric(length(raw_peaks))
    for (i in seq_along(raw_peaks)) {
      state <- PAGe:::.m1_stabilize_peak(
        t_peak = raw_peaks[i],
        t_peak_ci = raw_peaks[i] + c(-1.2, 1.4),
        previous_state = state,
        max_jump_weeks = 2
      )
      out[i] <- state$t_peak
    }
    out
  }

  prefix <- stabilize_prefix(c(20.25, 21.80))
  with_future <- stabilize_prefix(c(20.25, 21.80, 35.90))
  expect_equal(with_future[seq_along(prefix)], prefix)
})

test_that("peak passage latch never reverts and uses the supplied evidence", {
  res <- list(peak = list(t_peak = 20.25, t_peak_ci = c(19.2, 21.4)))
  early <- PAGe:::peak_status_from_align(
    res = res,
    currentD = data.frame(newWeek = 27),
    use_ci = TRUE,
    buffer_weeks = 5L
  )
  expect_true(early$peak_passed)
  expect_true(early$peak_passed_now)

  late_origin_reassessment <- PAGe:::peak_status_from_align(
    res = res,
    currentD = data.frame(newWeek = 20),
    use_ci = TRUE,
    buffer_weeks = 5L,
    previous_peak_passed = early$peak_passed
  )
  expect_false(late_origin_reassessment$peak_passed_now)
  expect_true(late_origin_reassessment$peak_passed)
  expect_equal(early$threshold_week, 26.4)

  unavailable_origin <- PAGe:::peak_status_from_align(
    res = list(peak = list(t_peak = NA_real_, t_peak_ci = c(NA_real_, NA_real_))),
    currentD = data.frame(newWeek = 28),
    previous_peak_passed = early$peak_passed
  )
  expect_false(unavailable_origin$peak_passed_now)
  expect_true(unavailable_origin$peak_passed)
})

test_that("legacy peak mode leaves the raw decimal estimate unchanged", {
  res <- list(peak = list(t_peak = 24.37, t_peak_ci = c(23.1, 25.8)))
  prepared <- PAGe:::.m1_prepare_peak(
    res,
    peak_stabilization = "legacy",
    previous_state = list(t_peak = 10),
    max_jump_weeks = 2
  )
  expect_equal(prepared$t_peak_raw, 24.37)
  expect_equal(prepared$t_peak_stabilized, 24.37)
  expect_equal(prepared$t_peak_ci_stabilized, c(23.1, 25.8))

  status <- PAGe:::peak_status_from_align(
    res = res,
    currentD = data.frame(newWeek = 20),
    use_ci = FALSE,
    buffer_weeks = 0L
  )
  expect_false(status$peak_passed)
  expect_false(status$peak_passed_now)
})

test_that("the walk-forward bridge carries causal state between origins", {
  seen <- new.env(parent = emptyenv())
  seen$states <- list()

  testthat::local_mocked_bindings(
    run_alignment_prospective_multi = function(currentSeason,
                                               peak_state = NULL,
                                               peak_stabilization = "legacy",
                                               ...) {
      ew <- max(currentSeason$weekF)
      seen$states[[length(seen$states) + 1L]] <- list(value = peak_state)
      latched <- isTRUE(peak_state$peak_passed) || ew >= 4L
      list(
        state = "aligning",
        iWeek_hat = 1L,
        iWeek_hatF = 1,
        tau = 0,
        delta = 1,
        peak_weekF = 9.25,
        peak_weekF_lo = 8.10,
        peak_weekF_hi = 10.40,
        peak_weekF_raw = 9.25,
        peak_weekF_lo_raw = 8.10,
        peak_weekF_hi_raw = 10.40,
        peak_weekF_stabilized = 9.25,
        peak_weekF_lo_stabilized = 8.10,
        peak_weekF_hi_stabilized = 10.40,
        peak_passed = latched,
        peak_passed_now = ew >= 4L,
        peak_passed_latched = latched,
        peak_threshold_week = 15.4,
        peak_state = list(
          t_peak_stabilized = 18.25,
          t_peak_ci_stabilized = c(17.1, 19.4),
          peak_passed = latched
        ),
        forecast_df = data.frame(
          newWeek = seq(1, 52, by = 0.5),
          p_hat = 0.2,
          p_lo = 0.1,
          p_hi = 0.3,
          logit_spread = 0.4
        )
      )
    },
    .package = "PAGe"
  )

  dat <- data.frame(
    season = "S1", weekF = 1:5, y = 1:5, neg = rep(99, 5), N = rep(100, 5)
  )
  out <- PAGe:::m1_walkforward_predictions(
    seasonD = dat,
    ref = list(anchorWeek = 10L),
    hyper = list(),
    ign_out = list(ign_week_locked = 1L, iWeek_hat_locked = 1L),
    eval_weeks = 3:5,
    horizons = 1L,
    peak_stabilization = "causal"
  )

  expect_true(nrow(out) > 0)
  expect_null(seen$states[[1L]]$value)
  expect_false(isTRUE(seen$states[[2L]]$value$peak_passed))
  expect_true(isTRUE(seen$states[[3L]]$value$peak_passed))
  expect_true(all(out$peak_passed_latched[out$eval_weekF >= 4L]))
  expect_true(all(out$peak_weekF_stabilized == 9.25))
})
