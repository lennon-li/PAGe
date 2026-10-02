make_m0_rank_fixture <- function(n_seasons) {
  out <- expand.grid(
    season = sprintf("S%02d", seq_len(n_seasons)),
    weekF = seq_len(52L),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  season_id <- as.integer(sub("S", "", out$season))
  out$p <- 0.004 + 0.0007 * season_id + 0.00008 * out$weekF
  out$phase <- as.integer(out$weekF >= 20.5)
  out
}

make_m0_rank_truth <- function(n_seasons) {
  data.frame(
    season = sprintf("S%02d", seq_len(n_seasons)),
    ignition_target_weekF = rep(20.5, n_seasons),
    stringsAsFactors = FALSE
  )
}

test_that("M0 reduces the positivity basis at the event-support rank boundary", {
  dat <- make_m0_rank_fixture(8L)
  truth <- make_m0_rank_truth(8L)

  fit <- PAGe:::fitIgnition(
    dat,
    timing_truth = truth, fit_base = TRUE,
    fit_slope = FALSE, fit_fs = FALSE, k_week = 6L, k_p = 8L,
    verbose = FALSE
  )

  expect_true(is.list(fit$fits$base))
  expect_identical(unname(fit$basis_support$requested), c(6L, 8L))
  expect_identical(unname(fit$basis_support$effective), c(6L, 7L))
  expect_match(
    fit$basis_support$adjustments$reason[2L],
    "event-supported p rank boundary"
  )
})

test_that("M0 keeps the requested basis and fitted values on healthy support", {
  dat <- make_m0_rank_fixture(10L)
  truth <- make_m0_rank_truth(10L)

  set.seed(20260916)
  fit <- PAGe:::fitIgnition(
    dat,
    timing_truth = truth, fit_base = TRUE,
    fit_slope = FALSE, fit_fs = FALSE, k_week = 6L, k_p = 8L,
    verbose = FALSE
  )
  set.seed(20260916)
  reference <- gamm4::gamm4(
    event ~ s(weekF, bs = "ts", k = 6) + s(p, bs = "ts", k = 8),
    random = ~ (1 | season), data = fit$train_data,
    family = binomial(), nAGQ = 1
  )

  expect_identical(unname(fit$basis_support$effective), c(6L, 8L))
  expect_equal(
    fit$data$p_cls_p,
    as.numeric(stats::predict(reference$gam, newdata = fit$data, type = "response")),
    tolerance = 1e-10
  )
})
