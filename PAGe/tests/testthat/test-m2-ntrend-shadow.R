make_ntrend_test_data <- function(n_seasons = 5L, weeks = 10:24, feedback = FALSE) {
  out <- list()
  for (j in seq_len(n_seasons)) {
    season <- sprintf("20%02d-%02d", 10 + j, 11 + j)
    t <- seq_along(weeks)
    N <- round(1000 * exp(0.015 * t + 0.03 * j))
    base <- stats::plogis(-5 + 0.24 * t - 0.008 * t^2 + 0.03 * j)
    if (feedback) {
      # Deterministic denominator expansion; future positivity is lower when
      # recent volume growth is larger, creating known predictive signal.
      N <- round(900 * exp((0.01 + 0.004 * j) * t + 0.002 * t^2))
      dn2 <- c(0, 0, (log(N[3:length(N)]) - log(N[1:(length(N) - 2)])) / 2)
      base <- stats::plogis(stats::qlogis(base) - 1.1 * dn2)
    }
    y <- pmax(0L, pmin(N, as.integer(round(N * base))))
    out[[j]] <- data.frame(season = season, weekF = weeks, y = y, N = N,
                           denominator_regime = if (j == n_seasons) "orvt_type_specific" else "historical_proxy")
  }
  do.call(rbind, out)
}

test_that("N-trend feature uses only exact past weeks", {
  d <- make_ntrend_test_data(3L)
  led <- getFromNamespace('.m2_ntrend_prepare', 'PAGe')(d, windows = c(0L, 2L), min_origin_week = 13L)
  z <- d[d$season == unique(d$season)[1L], ]
  o <- led[led$season == unique(d$season)[1L] & led$origin_week == 15L & led$horizon == 1L, ]
  i <- match(15L, z$weekF); j <- match(13L, z$weekF)
  expect_equal(o$ntrend_w2, (log(z$N[i]) - log(z$N[j])) / 2, tolerance = 1e-14)

  gapped <- d[!(d$season == unique(d$season)[1L] & d$weekF == 13L), ]
  led2 <- getFromNamespace('.m2_ntrend_prepare', 'PAGe')(gapped, windows = c(0L, 2L), min_origin_week = 13L)
  o2 <- led2[led2$season == unique(d$season)[1L] & led2$origin_week == 15L & led2$horizon == 1L, ]
  expect_equal(nrow(o2), 0L)
})

test_that("window zero is explicit OFF and remains tunable", {
  d <- make_ntrend_test_data(5L)
  fit <- fit_m2_a_ntrend_shadow(d, windows = 0L, off_tolerance = 0)
  expect_s3_class(fit, "page_m2_a_ntrend_shadow")
  expect_identical(fit$selected_window, 0L)
  expect_false(grepl("ntrend", paste(deparse(stats::formula(fit$full_fit)), collapse = " ")))
})

test_that("tuner requires the OFF candidate", {
  d <- make_ntrend_test_data(4L)
  expect_error(fit_m2_a_ntrend_shadow(d, windows = 1:3), "must include 0")
})


test_that("OFF preference can disable a lower-NLL nonzero candidate within tolerance", {
  d <- make_ntrend_test_data(6L, feedback = TRUE)
  raw <- fit_m2_a_ntrend_shadow(d, windows = c(0L, 2L), off_tolerance = 0)
  tolerant <- fit_m2_a_ntrend_shadow(d, windows = c(0L, 2L), off_tolerance = 1e6)
  expect_identical(tolerant$selected_window, 0L)
  expect_false(grepl("ntrend", paste(deparse(stats::formula(tolerant$full_fit)), collapse = " ")))
})

test_that("runtime N-trend prediction is future invariant", {
  d <- make_ntrend_test_data(6L, feedback = TRUE)
  fit <- fit_m2_a_ntrend_shadow(d, windows = c(0L, 1L, 2L, 3L), off_tolerance = 0)
  current <- d[d$season == unique(d$season)[6L], c("weekF", "y", "N")]
  current <- current[current$weekF <= 20L, ]
  p1 <- predict_m2_a_ntrend_shadow(fit, current, origin_week = 20L)
  leaked <- rbind(current, data.frame(weekF = 21:22, y = c(99999, 99999), N = c(100000, 100000)))
  p2 <- predict_m2_a_ntrend_shadow(fit, leaked, origin_week = 20L)
  expect_equal(p1$forecast_pct, p2$forecast_pct, tolerance = 1e-12)
  expect_identical(p1$ntrend_window, p2$ntrend_window)
})

test_that("shadow artifact reports both LOSO and chronological evidence", {
  d <- make_ntrend_test_data(6L, feedback = TRUE)
  fit <- fit_m2_a_ntrend_shadow(d, windows = c(0L, 2L), min_chronological_train_seasons = 3L)
  expect_true(nrow(fit$loso_summary$overall) == 2L)
  expect_true(nrow(fit$chronological_summary$overall) == 2L)
  expect_true(all(c(0L, 2L) %in% fit$loso_summary$overall$window))
  expect_true(isTRUE(fit$shadow_only))
})
