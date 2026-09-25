m1v2_test_truth <- function(data, k = 6L, grid_step = .05) {
  seasons <- sort(unique(data$season))
  do.call(rbind, lapply(seasons, function(s) {
    fit <- retrospective_gam_peak_truth(data, season = s, k = k, grid_step = grid_step)
    data.frame(season = s, peak_week_decimal = fit$peak_week_decimal)
  }))
}

m1v2_test_activation_table <- function(seasons, origin = 10, decimal = 9.6) {
  cmp <- data.frame(
    season = seasons, iWeek_hat = origin, iWeek_hatF = decimal,
    detection_failed = FALSE, stringsAsFactors = FALSE
  )
  folds <- setNames(lapply(seasons, function(ss) list(
    season = ss, best_params = list(),
    compare = cmp[cmp$season == ss, c("season", "iWeek_hat", "iWeek_hatF"), drop = FALSE]
  )), seasons)
  m1_v2_activation_table_from_m0_loso(structure(list(
    folds = folds, compare = cmp, context_id = paste0("test-", paste(seasons, collapse = "-"))
  ), class = c("page_m0_loso_result", "list")))
}

test_that("M1-v2 library enforces peak-anchored low-rank shapes", {
  make_season <- function(season, peak, amp) {
    w <- 1:32
    p <- amp * exp(-0.5 * ((w - peak) / 3)^2)
    N <- rep(2000L, length(w))
    y <- as.integer(round(N * p))
    data.frame(season = season, weekF = w, y = y, N = N)
  }
  hist <- rbind(
    make_season("s1", 17, .22),
    make_season("s2", 18, .28),
    make_season("s3", 16, .18),
    make_season("s4", 17, .25)
  )
  truth <- m1v2_test_truth(hist)

  lib <- fit_m1_v2_library(hist, truth, k = 6L, grid_step = .05, tau_step = .2)
  expect_s3_class(lib, "page_m1_v2_library")

  for (comp in list(lib$forecast, lib$passage)) {
    i0 <- which.min(abs(comp$tau))
    for (cc in c(comp$c_lo, mean(c(comp$c_lo, comp$c_hi)), comp$c_hi)) {
      f <- pmax(comp$mean + cc * comp$pc1, .001)
      expect_equal(which.max(f), i0)
      expect_true(all(f > 0))
    }
  }
})

test_that("M1-v2 refuses inference on a season present in its training library", {
  make_season <- function(season, peak) {
    w <- 1:32
    p <- .2 * exp(-0.5 * ((w - peak) / 3)^2)
    N <- rep(1500L, length(w))
    data.frame(season = season, weekF = w, y = round(N * p), N = N)
  }
  hist <- rbind(make_season("s1", 16), make_season("s2", 17), make_season("s3", 18))
  truth <- m1v2_test_truth(hist)
  lib <- fit_m1_v2_library(hist, truth, k = 6L, grid_step = .05, tau_step = .2)

  expect_error(
    m1_v2_peak_posterior(lib, hist[hist$season == "s1", ], activation_week = 7, origin_week = 9),
    "present in the M1-v2 training library"
  )
})

test_that("M1-v2 future posterior respects release-time boundary", {
  make_season <- function(season, peak, amp = .22) {
    w <- 1:32
    p <- amp * exp(-0.5 * ((w - peak) / 3)^2)
    N <- rep(1800L, length(w))
    data.frame(season = season, weekF = w, y = round(N * p), N = N)
  }
  hist <- rbind(
    make_season("s1", 16), make_season("s2", 17, .25),
    make_season("s3", 18, .20), make_season("s4", 16.5, .18)
  )
  truth <- m1v2_test_truth(hist)
  lib <- fit_m1_v2_library(hist, truth, k = 6L, grid_step = .05, tau_step = .2)
  current <- make_season("heldout", 17, .23)

  fit <- m1_v2_peak_posterior(lib, current, activation_week = 7.3, origin_week = 9, candidate_step = .2)
  expect_s3_class(fit, "page_m1_v2_forecast")
  expect_true(all(fit$posterior$peak_week_decimal > 10))
  expect_equal(fit$asof_boundary, 10)
  expect_true(fit$summary$peak_q05 > 10)
})

test_that("M1-v2 passage decision requires posterior and decline evidence", {
  d <- data.frame(
    season = "heldout", weekF = 8:13,
    y = c(20, 40, 80, 120, 110, 90),
    N = rep(1000L, 6)
  )
  h <- data.frame(origin_week = 13, prob_peak_passed = .97)
  dec <- m1_v2_passage_decision(h, d, activation_week = 8, high_threshold = .95,
                                low_threshold = .1, drop_fraction = .05,
                                min_post_activation = 4)
  expect_true(dec$peak_reached_or_passed)
  expect_equal(dec$confirmation_branch, "high_posterior_decline")

  d2 <- d
  d2$y[nrow(d2)] <- 130
  dec2 <- m1_v2_passage_decision(h, d2, activation_week = 8, high_threshold = .95,
                                 low_threshold = .1, drop_fraction = .05,
                                 min_post_activation = 4)
  expect_false(dec2$peak_reached_or_passed)
})

test_that("M1-v2 rejects aggressive passage high thresholds", {
  h <- data.frame(origin_week = 10, prob_peak_passed = .95)
  d <- data.frame(season = "heldout", weekF = 8:10, y = c(50, 60, 55), N = 1000L)
  expect_error(
    m1_v2_passage_decision(h, d, activation_week = 7, high_threshold = .8),
    "\\[0.95, 1\\]"
  )
  expect_error(
    m1_v2_passage_decision(h, d, activation_week = 7, high_threshold = .9),
    "\\[0.95, 1\\]"
  )
})


test_that("M1-v2 early-bias calibration is inner cross-fitted and library-bound", {
  make_season <- function(season, peak, amp = .22) {
    w <- 1:32
    p <- amp * exp(-0.5 * ((w - peak) / 3)^2)
    N <- rep(1800L, length(w))
    data.frame(season = season, weekF = w, y = round(N * p), N = N)
  }
  hist <- rbind(
    make_season("s1", 16, .20), make_season("s2", 17, .24),
    make_season("s3", 18, .18), make_season("s4", 16.5, .26)
  )
  truth <- m1v2_test_truth(hist)
  lib <- fit_m1_v2_library(hist, truth, k = 6L, grid_step = .05, tau_step = .2)
  activation <- m1v2_test_activation_table(truth$season)

  cal <- fit_m1_v2_bias_calibrator(
    lib, hist, truth, activation,
    n_origins = 2L, candidate_step = .4
  )
  expect_s3_class(cal, "page_m1_v2_calibrator")
  expect_true(is.finite(cal$mean_signed_bias))
  expect_equal(cal$offset_week, -cal$mean_signed_bias)
  expect_equal(cal$library_hash, lib$provenance$library_hash)
  expect_equal(sort(unique(cal$inner_predictions$season)), sort(truth$season))

  current <- make_season("heldout", 17, .21)
  fc <- m1_v2_peak_posterior(lib, current, activation_week = 9.6,
                             origin_week = 11, candidate_step = .2)
  raw_prob <- fc$posterior$probability
  adj <- m1_v2_apply_bias_calibration(fc, cal)
  expect_equal(adj$peak_mean_calibrated,
               adj$peak_mean_raw + cal$offset_week)
  expect_equal(adj$interval_width_90, fc$summary$interval_width_90)
  expect_equal(fc$posterior$probability, raw_prob)
})

test_that("M1-v2 calibration refuses a forecast from another library", {
  make_season <- function(season, peak, amp = .22) {
    w <- 1:32
    p <- amp * exp(-0.5 * ((w - peak) / 3)^2)
    N <- rep(1600L, length(w))
    data.frame(season = season, weekF = w, y = round(N * p), N = N)
  }
  h1 <- rbind(make_season("a",16),make_season("b",17),make_season("c",18),make_season("d",16.5))
  t1 <- m1v2_test_truth(h1)
  l1 <- fit_m1_v2_library(h1,t1,k=6L,grid_step=.05,tau_step=.2)
  act <- m1v2_test_activation_table(t1$season)
  cal <- fit_m1_v2_bias_calibrator(l1,h1,t1,act,n_origins=1L,candidate_step=.5)

  h2 <- rbind(make_season("e",16),make_season("f",17),make_season("g",18),make_season("h",16.5))
  t2 <- m1v2_test_truth(h2)
  l2 <- fit_m1_v2_library(h2,t2,k=6L,grid_step=.05,tau_step=.2)
  fc2 <- m1_v2_peak_posterior(l2,make_season("heldout2",17),9.6,11,candidate_step=.3)
  expect_error(
    m1_v2_apply_bias_calibration(fc2,cal),
    "not fitted from the same historical M1-v2 library"
  )
})


test_that("M1-v2 library integrity covers fitted model contents", {
  make_season <- function(season, peak) {
    w <- 1:32
    p <- .22 * exp(-0.5 * ((w - peak) / 3)^2)
    N <- rep(1500L, length(w))
    data.frame(season = season, weekF = w, y = round(N * p), N = N)
  }
  hist <- rbind(make_season("s1",16),make_season("s2",17),make_season("s3",18),make_season("s4",16.5))
  truth <- m1v2_test_truth(hist)
  lib <- fit_m1_v2_library(hist, truth, k=6L, grid_step=.05, tau_step=.2)
  bad <- lib
  bad$forecast$mean[1] <- bad$forecast$mean[1] + .001
  expect_error(.validate_m1_v2_library(bad), "integrity check failed")
})

test_that("M1-v2 calibrator rejects ungoverned activation data frames", {
  make_season <- function(season, peak) {
    w <- 1:32
    p <- .22 * exp(-0.5 * ((w - peak) / 3)^2)
    N <- rep(1500L, length(w))
    data.frame(season = season, weekF = w, y = round(N * p), N = N)
  }
  hist <- rbind(make_season("s1",16),make_season("s2",17),make_season("s3",18),make_season("s4",16.5))
  truth <- m1v2_test_truth(hist)
  lib <- fit_m1_v2_library(hist, truth, k=6L, grid_step=.05, tau_step=.2)
  raw <- data.frame(season=truth$season,activation_origin_week=10,activation_week_decimal=9.6)
  expect_error(
    fit_m1_v2_bias_calibrator(lib,hist,truth,raw,n_origins=1L,candidate_step=.5),
    "m1_v2_activation_table_from_m0_loso"
  )
})


test_that("M1-v2 governed activation payload detects post-construction mutation", {
  seasons <- c("s1", "s2", "s3")
  act <- m1v2_test_activation_table(seasons)
  bad <- act
  bad$activation_week_decimal[1] <- bad$activation_week_decimal[1] + 0.25
  expect_error(
    .validate_m1_v2_activation_table(bad, seasons),
    "payload integrity check failed"
  )
})


test_that("M1-v2 low-rank component uses deterministic PCA sign anchor", {
  hist <- rbind(
    data.frame(season="s1",weekF=1:32,y=round(1800*.20*exp(-.5*((1:32-16)/3)^2)),N=1800L),
    data.frame(season="s2",weekF=1:32,y=round(1800*.24*exp(-.5*((1:32-17)/3)^2)),N=1800L),
    data.frame(season="s3",weekF=1:32,y=round(1800*.18*exp(-.5*((1:32-18)/3)^2)),N=1800L),
    data.frame(season="s4",weekF=1:32,y=round(1800*.26*exp(-.5*((1:32-16.5)/3)^2)),N=1800L)
  )
  truth <- m1v2_test_truth(hist)
  lib <- fit_m1_v2_library(hist,truth,k=6L,grid_step=.05,tau_step=.2)
  for (comp in list(lib$forecast,lib$passage)) {
    i <- which.max(abs(comp$pc1))
    expect_gte(comp$pc1[[i]],0)
  }
})

test_that("M1-v2 post-activation history is trimmed to template support instead of failing", {
  make_season <- function(season, peak, amp=.22) {
    w <- 1:36
    p <- amp*exp(-.5*((w-peak)/3)^2)
    data.frame(season=season,weekF=w,y=round(2000*p),N=2000L)
  }
  hist <- rbind(make_season("s1",18,.20),make_season("s2",19,.24),
                make_season("s3",20,.18),make_season("s4",18.5,.26))
  truth <- m1v2_test_truth(hist)
  lib <- fit_m1_v2_library(hist,truth,k=6L,grid_step=.05,tau_step=.2)
  current <- make_season("heldout",19,.21)
  expect_no_error({
    f <- m1_v2_peak_posterior(lib,current,activation_week=9.6,origin_week=30,candidate_step=.2)
    expect_true(nrow(f$posterior)>0)
  })
  expect_no_error({
    p <- m1_v2_passage_posterior(lib,current,activation_week=9.6,origin_week=30,candidate_step=.2)
    expect_true(is.finite(p$prob_peak_passed))
  })
})


test_that("M1-v2 library supports an explicit type-specific amplitude grid", {
  make_season <- function(season, peak, amp) {
    w <- 1:32
    p <- amp * exp(-0.5 * ((w - peak) / 3)^2)
    N <- rep(2200L, length(w))
    data.frame(season = season, weekF = w, y = round(N * p), N = N)
  }
  hist <- rbind(
    make_season("b1", 17, .025), make_season("b2", 18, .045),
    make_season("b3", 16, .070), make_season("b4", 17.5, .12)
  )
  truth <- m1v2_test_truth(hist)
  grid <- seq(.005, .20, by = .005)
  lib <- fit_m1_v2_library(hist, truth, k = 6L, grid_step = .05,
                           tau_step = .2, amplitude_grid = grid)
  expect_equal(lib$config$amplitude_grid, grid)
  expect_equal(lib$forecast$amplitude_grid, grid)
  expect_equal(lib$passage$amplitude_grid, grid)

  current <- make_season("heldout-b", 17, .04)
  fit <- m1_v2_peak_posterior(lib, current, activation_week = 10.2,
                              origin_week = 13, candidate_step = .2)
  expect_true(all(is.finite(fit$posterior$probability)))
  expect_equal(sum(fit$posterior$probability), 1, tolerance = 1e-10)

  expect_error(
    fit_m1_v2_library(hist, truth, k = 6L, grid_step = .05,
                      tau_step = .2, amplitude_grid = c(.01, .02)),
    "at least three unique finite values"
  )
  expect_error(
    fit_m1_v2_library(hist, truth, k = 6L, grid_step = .05,
                      tau_step = .2, amplitude_grid = c(.005, .01, .02, .03)),
    "regularly spaced"
  )
})
