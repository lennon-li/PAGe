test_that("fit_peak_calibration: holdout_season excludes the season from prior and GAM", {
  skip_if_not_installed("mgcv")

  # ---- minimal synthetic dataset: 8 seasons to give the GAM enough data ----
  set.seed(42L)
  n_seasons <- 8L
  season_names <- paste0("S", seq_len(n_seasons))
  # Varying peak weeks so the distribution has real variance
  peak_weeks <- c(8L, 9L, 10L, 11L, 12L, 10L, 9L, 11L)

  make_season_allD <- function(s, pw) {
    wks <- seq_len(20L)
    p   <- dnorm(wks, mean = pw, sd = 3)
    p   <- p / max(p) * 0.25 + 0.01
    data.frame(
      season = s,
      weekF  = wks,
      p      = p,
      N      = rep(300L, 20L),
      y      = as.integer(round(p * 300L)),
      neg    = as.integer(round((1 - p) * 300L)),
      stringsAsFactors = FALSE
    )
  }
  allD <- do.call(rbind, Map(make_season_allD, season_names, peak_weeks))

  # Build params_df that fit_peak_calibration expects.
  # Each season contributes multiple evaluation weeks (walk-forward style).
  make_params_rows <- function(s, pw) {
    eval_wks <- seq(3L, pw)   # evaluations before the true peak
    n <- length(eval_wks)
    data.frame(
      season     = s,
      iWeek_true = rep(3L, n),
      iWeek_hat  = rep(3L, n),
      eval_week  = eval_wks,
      # t_peak in newWeek space (anchorWeek=27 by default)
      t_peak     = rep(pw - 3L + 27L, n) + rnorm(n, 0, 0.5),
      t_peak_lo  = rep(pw - 3L + 27L - 2L, n),
      t_peak_hi  = rep(pw - 3L + 27L + 2L, n),
      stringsAsFactors = FALSE
    )
  }
  params_df <- do.call(rbind, Map(make_params_rows, season_names, peak_weeks))

  # Full-data calibration (no holdout) -- this should succeed
  cal_full <- fit_peak_calibration(params_df, allD)

  # Holdout S3 -- should exclude S3's rows
  cal_held <- fit_peak_calibration(params_df, allD, holdout_season = "S3")

  # 1. Training data in cal_df must not contain S3
  expect_false(
    "S3" %in% cal_held$cal_df$season,
    info = "cal_df must not contain the holdout season S3"
  )

  # 2. cal_df for full vs held must differ (one has fewer rows)
  expect_lt(nrow(cal_held$cal_df), nrow(cal_full$cal_df),
            label = "held-out calibrator must have fewer training rows than full")

  # 3. sigma_prior or mu_prior should differ (S3 excluded from prior distribution)
  #    At minimum, the GAM coefficients must differ (fewer data points).
  coef_differ <- !isTRUE(
    all.equal(coef(cal_full$bias_gam), coef(cal_held$bias_gam), tolerance = 1e-9)
  )
  expect_true(coef_differ,
              info = "bias_gam coefficients must differ when S3 is held out")

  # 4. holdout_season = NULL is bit-for-bit equal to full calibration
  cal_null <- fit_peak_calibration(params_df, allD, holdout_season = NULL)
  expect_equal(cal_null$mu_prior,    cal_full$mu_prior)
  expect_equal(cal_null$sigma_prior, cal_full$sigma_prior)
  expect_equal(cal_null$cal_df,      cal_full$cal_df)
})
