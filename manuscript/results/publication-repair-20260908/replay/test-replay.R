replay_script <- "scripts/publication_replay.R"
if (!file.exists(replay_script)) {
  replay_script <- file.path("..", "..", "..", "..", replay_script)
}
source(replay_script)
testthat::test_that("trial weighted metrics use denominators and declared windows", {
  d <- data.frame(weekF = 1:3, lead = c(2, 2, 1), t_since = c(0, 12, 13),
    p_hat = c(.2, .4, .8), p_obs = c(.1, .5, .9), N_lead = c(10, 30, 20))
  x <- replay_metrics(d)
  h <- x[x$window == "h2_0_12", ]
  testthat::expect_equal(h$n, 2L)
  testthat::expect_equal(h$trials, 40)
  testthat::expect_equal(h$mae, .1)
  testthat::expect_equal(h$nll,
    sum(c(10, 30) * -(c(.1, .5) * log(c(.2, .4)) +
      (1 - c(.1, .5)) * log1p(-c(.2, .4)))) / 40)
  testthat::expect_equal(h$aggregate_positivity_mse, .01)
  testthat::expect_equal(h$bernoulli_brier, .22)
  testthat::expect_equal(replay_metrics(d[FALSE, ])$n, rep(0L, 4))
  d$p_hat[1] <- NA
  testthat::expect_error(replay_metrics(d), "Invalid scorable")
})
testthat::test_that("comparison joins exact origin/horizon keys and rejects duplicates", {
  old <- data.frame(season = "s", weekF = c(1, 2), lead = c("h1", "h2"),
    p_hat = c(.2, .4))
  new <- data.frame(season = "s", weekF = c(2, 3), lead = c(2, 1),
    p_hat = c(.5, .8), forecast_action = c("post_peak_m1", "gam"))
  x <- compare_predictions(new, old)
  testthat::expect_equal(x$summary$n_matched, 1L)
  testthat::expect_equal(x$summary$mean_delta, .1)
  testthat::expect_equal(x$counts$new_only, 1L)
  testthat::expect_equal(x$counts$old_only, 1L)
  testthat::expect_error(compare_predictions(new, rbind(old, old)), "Duplicate")
})
testthat::test_that("ledger requires every weekly origin including missing weeks", {
  d <- data.frame(weekF = c(1, 3))
  l <- expand.grid(weekF = 1:3, lead = 1:2)
  l$target_weekF <- l$weekF + l$lead
  l$forecast_status <- "not_emitted"
  testthat::expect_silent(validate_ledger(l, d))
  testthat::expect_error(validate_ledger(l[-1, ], d), "roster")
  l$target_weekF[1] <- 99
  testthat::expect_error(validate_ledger(l, d), "target")
})
