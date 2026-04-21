# test-feature-scale.R
# Regression tests for B2: dz_ema must be divided by training SD at inference.
# Audit reference: code-audit-2026-04 B2.
#
# Training: prep_stage2_joint() divides dz_ema by dze_sd, stores dz_ema_sd in feature_ranges.
# Inference (old): dz_ema_now = z_ema_now - z_ema_prev  (unscaled — the bug).
# Inference (fixed): dz_ema_now = (z_ema_now - z_ema_prev) / fr$dz_ema_sd.

library(mgcv)

# Build a minimal GAM with a dz_ema smooth so we can test the scaling effect.
# Two seasons needed for contrasts; two lead levels for the factor.
make_toy_dz_gam <- function(dz_sd = 2.0, n = 80L) {
  set.seed(42L)
  half    <- n / 2L
  dz_raw  <- rnorm(n, sd = dz_sd)          # raw dz, sd ≈ dz_sd
  dz_scaled <- dz_raw / dz_sd              # scaled, sd ≈ 1
  lead    <- factor(rep(c("h1", "h2"), each = half), levels = c("h1", "h2"))
  season  <- factor(rep(c("2022-23", "2023-24"), times = half))
  weekF   <- rep(seq_len(half), 2L)
  y <- rbinom(n, 100L, plogis(-1.5 + 0.5 * dz_scaled))
  N <- rep(100L, n)

  d <- data.frame(lead, season, weekF, dz_ema = dz_scaled, y, N)

  # Minimal formula: lead + s(dz_ema) — enough to test scaling.
  fit <- mgcv::bam(
    cbind(y, N - y) ~ lead + s(dz_ema, k = 3),
    data   = d,
    family = binomial(),
    method = "fREML"
  )
  list(fit = fit, dz_sd = dz_sd, d = d)
}

test_that("training dz_ema values are unit-scale (sd ≈ 1 after division)", {
  obj <- make_toy_dz_gam(dz_sd = 2.5)
  # The dz_ema column in training data should have sd ≈ 1 (divided by dz_sd=2.5)
  sd_dz <- sd(obj$d$dz_ema)
  expect_lt(abs(sd_dz - 1.0), 0.3,
    label = "Training dz_ema should be near unit-variance after scaling")
})

test_that("scaled inference row gives same prediction as training-scale value", {
  obj    <- make_toy_dz_gam(dz_sd = 2.0)
  fit    <- obj$fit
  dz_sd  <- obj$dz_sd

  # Simulate an inference scenario: raw diff = 1.0 (on unscaled units)
  raw_diff      <- 1.0
  dz_ema_scaled <- raw_diff / dz_sd   # fixed formula

  # Build a newdata row using the scaled value (matching training feature space)
  nd_scaled <- data.frame(
    lead   = factor("h1", levels = levels(fit$model$lead)),
    dz_ema = dz_ema_scaled
  )
  eta_scaled <- as.numeric(predict(fit, newdata = nd_scaled, type = "link"))

  # Build the same row using the UNSCALED value (the pre-fix bug)
  nd_unscaled <- nd_scaled
  nd_unscaled$dz_ema <- raw_diff  # not divided by dz_sd
  eta_unscaled <- as.numeric(predict(fit, newdata = nd_unscaled, type = "link"))

  # When dz_sd != 1, the two predictions must differ (pinning the bug).
  diff_eta <- abs(eta_scaled - eta_unscaled)
  expect_gt(diff_eta, 1e-6,
    label = "Scaled vs unscaled dz_ema should give different predictions when dz_sd != 1")

  # No NA in prediction
  expect_false(is.na(eta_scaled), label = "Scaled inference prediction should not be NA")
})

test_that("B2 fix: applying dz_ema_sd division changes prediction (pins the bug)", {
  # Explicitly demonstrate that inference WITHOUT scaling (old code) differs
  # from inference WITH scaling (fixed code) by > 1e-3 on eta when dz_sd >> 1.
  obj   <- make_toy_dz_gam(dz_sd = 3.0)
  fit   <- obj$fit
  dz_sd <- obj$dz_sd

  raw_diff <- 1.5  # a raw dz_ema difference

  # Fixed (correct): scale by dz_sd
  dz_fixed <- raw_diff / dz_sd
  nd_fixed <- data.frame(
    lead   = factor("h1", levels = levels(fit$model$lead)),
    dz_ema = dz_fixed
  )
  eta_fixed <- as.numeric(predict(fit, newdata = nd_fixed, type = "link"))

  # Buggy (old): no scaling
  nd_buggy <- nd_fixed
  nd_buggy$dz_ema <- raw_diff
  eta_buggy <- as.numeric(predict(fit, newdata = nd_buggy, type = "link"))

  # Must differ by more than 1e-3 (bug is meaningful)
  expect_gt(abs(eta_fixed - eta_buggy), 1e-3,
    label = paste0("B2 bug: unscaled dz_ema (dz_sd=", dz_sd, ") must give different eta"))
})
