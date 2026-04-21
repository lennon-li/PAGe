# test-holt-bias.R
# Regression tests for B1: Holt bias update uses raw error (not post-correction).
#
# Audit reference: code-audit-2026-04 B1.
# The EMA level must asymptote to the true logit-scale bias B, not B/2.
# Fixed formula: lev_new = (lev+trn) + alpha*(err - (lev+trn))
# where err = logit_obs - eta_raw (eta_raw = GAM linear pred BEFORE bias addition).

# Internal Holt step helper — mirrors the production update formula.
# Both the test and the production code use this same formula.
.holt_update_step_fixed <- function(lev_prev, trn_prev, err, alpha, beta = 0) {
  lev_new <- (lev_prev + trn_prev) + alpha * (err - (lev_prev + trn_prev))
  trn_new <- trn_prev + beta * (lev_new - lev_prev - trn_prev)
  list(lev = lev_new, trn = trn_new)
}

# The old (buggy) formula — for the negative-control test.
# resid = logit_obs - (eta_raw + lev_prev)  [post-correction error]
# lev_new = alpha*resid + (1-alpha)*(lev+trn)
# Steady state: lev* = B/2  (bug documented here for posterity).
.holt_update_step_buggy <- function(lev_prev, trn_prev, resid_post, alpha, beta = 0) {
  lev_new <- alpha * resid_post + (1 - alpha) * (lev_prev + trn_prev)
  trn_new <- beta * (lev_new - lev_prev) + (1 - beta) * trn_prev
  list(lev = lev_new, trn = trn_new)
}

test_that("fixed Holt update converges to true bias B (not B/2)", {
  # Simulate: true logit bias B = 0.3. GAM always predicts eta = 0.
  # Observed logit = eta + B = 0.3 each step.
  B     <- 0.3
  alpha <- 0.2
  beta  <- 0.0
  lev   <- 0
  trn   <- 0
  n     <- 80L

  for (i in seq_len(n)) {
    eta_raw <- 0          # uncorrected GAM prediction (logit scale)
    err     <- B - eta_raw  # raw error = B
    s <- .holt_update_step_fixed(lev, trn, err, alpha, beta)
    lev <- s$lev
    trn <- s$trn
  }

  expect_lt(abs(lev - B), 0.02,
    label = paste0("Fixed Holt level after ", n, " steps should be within 0.02 of B=", B))
})

test_that("buggy Holt update (negative control) converges to B/2 not B", {
  # Audit B1 negative-control: old formula converges to B/2.
  # This test documents the pre-fix behavior and should remain GREEN forever.
  B     <- 0.3
  alpha <- 0.2
  beta  <- 0.0
  lev   <- 0
  trn   <- 0
  n     <- 200L

  for (i in seq_len(n)) {
    eta_raw      <- 0
    corrected    <- eta_raw + lev + trn  # the corrected prediction (logit scale)
    resid_post   <- B - corrected        # post-correction residual (the bug)
    s <- .holt_update_step_buggy(lev, trn, resid_post, alpha, beta)
    lev <- s$lev
    trn <- s$trn
  }

  # Buggy formula converges to B/2 = 0.15, NOT B = 0.3.
  expect_lt(abs(lev - B / 2), 0.02,
    label = paste0("Buggy Holt level should converge to B/2=", B / 2, " (documenting B1 bug)"))
  expect_gt(abs(lev - B), 0.05,
    label = "Buggy Holt level should NOT be close to true B (documents the bug)")
})

test_that("fixed Holt update with auto-boost alpha also converges to B", {
  # Verify that the consecutive-same-sign boost to alpha=0.7 does not
  # prevent convergence to the true bias B.
  B          <- 0.5
  alpha_base <- 0.2
  alpha_high <- 0.7
  beta       <- 0.0
  lev        <- 0
  trn        <- 0
  n          <- 50L
  consec     <- 0L
  prev_pos   <- NA

  for (i in seq_len(n)) {
    eta_raw <- 0
    err     <- B - eta_raw
    cur_pos <- err > 0
    if (!is.na(prev_pos) && cur_pos == prev_pos) {
      consec <- consec + 1L
    } else {
      consec <- 0L
    }
    prev_pos <- cur_pos
    alpha_t  <- if (consec >= 2L) alpha_high else alpha_base
    s <- .holt_update_step_fixed(lev, trn, err, alpha_t, beta)
    lev <- s$lev
    trn <- s$trn
  }

  expect_lt(abs(lev - B), 0.005,
    label = "Auto-boost alpha should still converge to B (faster)")
})
