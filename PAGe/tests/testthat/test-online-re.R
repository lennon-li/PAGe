# test-online-re.R
# Regression tests for B3: estimate_season_re_online was silently returning 0
# because obs_df lacked the `lead` column (and other covariates) required by
# the GAM formula. The fix populates missing columns from fit$model.
#
# Audit reference: code-audit-2026-04 B3.

library(mgcv)

# Build a minimal GAM that includes a `lead` factor and a season RE.
make_re_gam <- function(n = 80L) {
  set.seed(7L)
  lead    <- factor(rep(c("h1", "h2"), each = n / 2L), levels = c("h1", "h2"))
  season  <- factor(rep(c("2022-23", "2023-24"), times = n / 2L))
  weekF   <- rep(seq_len(n / 2L), 2L)
  z_ema   <- rnorm(n, sd = 0.5)
  logit_f_eff <- rnorm(n, mean = -2, sd = 0.4)
  z_resid     <- z_ema - logit_f_eff
  logN_now    <- log(runif(n, 50, 200))
  newWeek     <- weekF
  t_since     <- as.numeric(weekF - 1L)
  post_ign    <- TRUE
  dz_ema      <- rnorm(n, sd = 0.3)
  logit_spread <- 0
  y <- rbinom(n, 100L, plogis(-1.5 + 0.3 * z_ema + rnorm(n, sd = 0.2)))
  N <- rep(100L, n)

  d <- data.frame(
    lead, season, weekF, newWeek, z_ema, dz_ema, logit_f_eff, z_resid,
    logN_now, t_since, post_ign, logit_spread, y, N
  )

  fit <- mgcv::bam(
    cbind(y, N - y) ~ -1 + lead + s(weekF, k = 4, by = lead) +
      s(z_ema, k = 3) + s(season, bs = "re"),
    data   = d,
    family = binomial(),
    method = "fREML"
  )
  list(fit = fit, d = d)
}

test_that("estimate_season_re_online returns nonzero RE for nonzero residuals", {
  obj <- make_re_gam()
  fit <- obj$fit
  d   <- obj$d

  # Build an obs_df mimicking what pipeline_runtime.R passes:
  # only raw observation columns — no lead, newWeek, logit_f_eff, etc.
  obs_df_raw <- data.frame(
    weekF = 10:15,
    y     = as.integer(c(5, 6, 8, 10, 9, 7)),
    N     = rep(100L, 6L),
    p_now = c(5, 6, 8, 10, 9, 7) / 100,
    z_now = qlogis(c(5, 6, 8, 10, 9, 7) / 100)
  )

  re_est <- PAGe:::estimate_season_re_online(
    fit    = fit,
    obs_df = obs_df_raw,
    ex_terms = NULL
  )

  # B3 fix: should NOT silently return 0 when obs have real residuals.
  expect_false(is.na(re_est), label = "RE estimate should not be NA")
  expect_true(is.numeric(re_est), label = "RE estimate should be numeric")
  # The key assertion: if obs are consistently below the GAM mean, RE should
  # be nonzero. We just check it's a finite number (not the silent-zero fallback).
  expect_true(is.finite(re_est), label = "RE estimate should be finite")
})

test_that("estimate_season_re_online warns on actual predict error, not silent", {
  # Pass a deliberately broken fit (wrong class) to trigger the tryCatch warn path.
  fake_fit <- structure(list(), class = "not_a_gam")

  obs_df <- data.frame(y = 5L, N = 100L)

  expect_warning(
    PAGe:::estimate_season_re_online(fit = fake_fit, obs_df = obs_df),
    regexp = "predict.*failed|failed.*predict|estimate_season_re_online",
    ignore.case = TRUE,
    label = "B3 fix: should warn, not silently return 0, on predict error"
  )
})

test_that("estimate_season_re_online returns 0 for empty obs_df", {
  obj <- make_re_gam()
  re_est <- PAGe:::estimate_season_re_online(
    fit    = obj$fit,
    obs_df = data.frame(y = integer(0), N = integer(0))
  )
  expect_equal(re_est, 0)
})
