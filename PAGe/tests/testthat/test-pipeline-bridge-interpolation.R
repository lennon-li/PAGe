test_that("M1 walk-forward interpolation averages duplicate coordinates without warnings", {
  testthat::local_mocked_bindings(
    run_alignment_prospective_multi = function(...) {
      list(
        state = "aligning",
        iWeek_hat = 1L,
        tau = 0,
        delta = 1,
        forecast_df = data.frame(
          newWeek = c(1, 3, 3, 5),
          p_hat = c(0.1, 0.2, 0.4, 0.5),
          p_lo = c(0.01, 0.02, 0.06, 0.1),
          p_hi = c(0.2, 0.3, 0.7, 0.8),
          logit_spread = c(0.1, 0.2, 0.6, 0.8)
        )
      )
    },
    .package = "PAGe"
  )

  out <- expect_no_warning(PAGe:::m1_walkforward_predictions(
    seasonD = data.frame(season = "2024-25", weekF = 1:2),
    ref = list(anchorWeek = 1L),
    hyper = list(),
    ign_out = list(ign_week_locked = 1L),
    eval_weeks = 2L,
    horizons = 1L
  ))

  expect_equal(out$m1_p_hat, 0.3)
  expect_equal(out$m1_p_lo, 0.04)
  expect_equal(out$m1_p_hi, 0.5)
  expect_equal(out$m1_logit_spread, 0.4)
})

test_that("snapshot M1 interpolation averages duplicate coordinates without warnings", {
  pp <- list(df = list(data.frame(
    weekF = 2L,
    lead = "h1",
    logit_f_eff = 0
  )))
  m1_result <- list(
    state = "aligning",
    iWeek_hat = 1L,
    forecast_df = data.frame(
      newWeek = c(1, 3, 3, 5),
      p_hat = c(0.1, 0.2, 0.4, 0.5)
    )
  )

  out <- expect_no_warning(PAGe:::inject_m1_into_snapshots(
    pp = pp,
    m1_result = m1_result,
    ref = list(anchorWeek = 1L)
  ))

  expect_equal(out$df[[1]]$logit_f_eff, qlogis(0.3))
})
