# Regression tests for the three M2 subset-correction fixes from the Opus M2
# audit (2026-09-18). None of the pre-existing fixtures exercised them: the
# audit found that what looked like "M2 hurts at h2" was driven by 5 rows out
# of 633, all in 2019-20, manufactured by a fixed 1e-6 probability floor.

# ---------------------------------------------------------------------------
# Fix 1: observed-feature logit uses a Jeffreys-style (y+0.5)/(N+1) estimate
# instead of clamping the raw proportion at a fixed 1e-6 floor. A zero-count
# week under the old floor produced qlogis(1e-6) = -13.82, an outlier whose
# magnitude was an artefact of the floor constant rather than of the data.
# ---------------------------------------------------------------------------

m2_fix_zero_season <- function(N) {
  data.frame(
    season = "A", weekF = 1:3, y = 0, N = N, stringsAsFactors = FALSE
  )
}

test_that("zero-positive weeks no longer produce the -13.82 floor artefact", {
  # The observed logit is not returned directly, but z is its EMA seeded at
  # logit_now[1], so an all-zero season makes z exactly the observed logit.
  small <- PAGe:::m2_subset_observed_features(
    m2_fix_zero_season(50),
    declaration_week = 3L, alpha_state = 0.2
  )
  large <- PAGe:::m2_subset_observed_features(
    m2_fix_zero_season(500),
    declaration_week = 3L, alpha_state = 0.2
  )

  # Under the old fixed 1e-6 floor both of these collapsed to qlogis(1e-6) =
  # -13.82 regardless of N.
  expect_equal(unique(small$z), stats::qlogis(0.5 / 51))
  expect_equal(unique(large$z), stats::qlogis(0.5 / 501))
  expect_true(all(small$z > stats::qlogis(1e-6) + 1))
  expect_true(all(large$z > stats::qlogis(1e-6) + 1))

  # Still sample-size aware: a zero out of 500 is stronger evidence of a low
  # rate than a zero out of 50.
  expect_lt(large$z[1L], small$z[1L])

  # An ordinary non-zero week is essentially unchanged by the fix.
  ordinary <- PAGe:::m2_subset_observed_features(
    data.frame(season = "A", weekF = 1:3, y = 5, N = 100),
    declaration_week = 3L, alpha_state = 0.2
  )
  expect_lt(abs(ordinary$z[1L] - stats::qlogis(5 / 100)), 0.15)
})

# ---------------------------------------------------------------------------
# Fix 2: the GAM correction is clamped to +/-10 logits before being added to
# the mandatory M1 offset, so a pathological extrapolation cannot move a
# forecast to a numerically saturated probability. The clamp is reported.
# ---------------------------------------------------------------------------

predict.m2_fix_fake_gam <- function(object, newdata, type, ...) object$eta

test_that("an extreme correction is clamped and flagged, leaving M1 dominant", {
  registerS3method(
    "predict", "m2_fix_fake_gam", predict.m2_fix_fake_gam,
    envir = asNamespace("stats")
  )
  m1_logit <- rep(-3, 3L)
  raw_correction <- c(-40, 0.25, 40)
  nd <- data.frame(
    m1_logit = m1_logit, lead = c("h1", "h2", "h1"), stringsAsFactors = FALSE
  )
  fake_fit <- list(
    type = "subset",
    spec = list(enabled_count = 1L),
    conf_scale = "none",
    w_ref = NA_real_,
    feature_ranges = NULL,
    fit = structure(
      list(eta = m1_logit + raw_correction),
      class = "m2_fix_fake_gam"
    )
  )

  local_mocked_bindings(
    m2_subset_enabled_features = function(spec) character(0),
    m2_subset_apply_ranges = function(data, ranges) data,
    .m2_subset_confidence = function(data, conf_scale, w_ref = NA_real_) {
      list(scale = rep(1, nrow(data)), missing = rep(FALSE, nrow(data)))
    }
  )

  out <- PAGe:::m2_subset_predict(fake_fit, nd)

  expect_equal(out$correction_clamped, c(TRUE, FALSE, TRUE))
  expect_equal(out$eta, c(-3 - 10, -3 + 0.25, -3 + 10))
  expect_equal(out$p_hat, stats::plogis(out$eta))
  # Clamped or not, every prediction stays a usable probability.
  expect_true(all(out$p_hat > 0 & out$p_hat < 1))
})

# ---------------------------------------------------------------------------
# Fix 3: spec selection is degradation-aware. Ranking on mean NLL alone could
# pick a spec that beats all-off on average while being far worse than it in
# one season -- which the downstream adoption gate then rejects outright
# (max_season_degradation = 0). Selection now prefers specs that never
# underperform all-off in any single season.
# ---------------------------------------------------------------------------

m2_fix_test_training_data <- function(seasons = c("S1", "S2", "S3")) {
  do.call(rbind, lapply(seasons, function(s) {
    data.frame(
      season = s, eval_weekF = c(10L, 10L), target_weekF = c(11L, 12L),
      h = c(1L, 2L), y = 5, N = 100, m1_logit = -3,
      forecast_available = TRUE, stringsAsFactors = FALSE
    )
  }))
}

# Per-season NLL by spec. "risky" has the best mean (0.3667) but is
# catastrophically worse than all-off in S3; "safe" is uniformly better than
# all-off. A mean-only ranking selects "risky"; the fix must select "safe".
m2_fix_test_nll <- list(
  alloff = c(S1 = 0.50, S2 = 0.50, S3 = 0.50),
  risky  = c(S1 = 0.10, S2 = 0.10, S3 = 0.90),
  safe   = c(S1 = 0.45, S2 = 0.45, S3 = 0.45)
)

test_that("selection rejects a better-mean spec that degrades a single season", {
  expect_lt(mean(m2_fix_test_nll$risky), mean(m2_fix_test_nll$safe))

  grid <- data.frame(
    id = c("alloff", "risky", "safe"),
    enabled_count = c(0L, 1L, 1L),
    stringsAsFactors = FALSE
  )
  seasons <- c("S1", "S2", "S3")

  local_mocked_bindings(
    m2_subset_fit = function(data, spec, ...) {
      list(spec_id = as.character(spec$id[1L]))
    },
    m2_subset_predict = function(fit, newdata) {
      list(p_hat = structure(rep(0.05, nrow(newdata)), spec_id = fit$spec_id))
    },
    m2_subset_score = function(data, prediction, weights = NULL) {
      sid <- attr(prediction, "spec_id")
      nll <- m2_fix_test_nll[[sid]][[as.character(data$season[1L])]]
      c(
        nll_test_count = nll, nll_equal_week = nll,
        mae_test_count = nll, mae_equal_week = nll,
        rows = nrow(data), trials = 100, weight_sum = nrow(data)
      )
    },
    .m2_subset_stage_b_grid = function(stage_a_grid, stage_a_summary) stage_a_grid,
    m2_subset_config = function(h1, h2, alpha_state, gamma) {
      list(h1 = h1, h2 = h2, alpha_state = alpha_state, gamma = gamma)
    }
  )

  td <- m2_fix_test_training_data(seasons)
  res <- PAGe:::.m2_subset_select_core(
    training_data = td,
    row_weights = rep(1, nrow(td)),
    grid = grid,
    training_seasons = seasons,
    scored_seasons_by_horizon = list("1" = seasons, "2" = seasons),
    nll_primary = "nll_equal_week", mae_primary = "mae_equal_week",
    alpha_state = 0.2, gamma = 1.4, n_cores = 1L
  )

  expect_equal(res$selected[[1L]]$id, "safe")
  expect_equal(res$selected[[2L]]$id, "safe")

  # The diagnostic that drove the decision must be reported, and must carry
  # the right sign for each spec.
  s1 <- res$summary[res$summary$horizon == 1L, , drop = FALSE]
  excess <- stats::setNames(
    s1$worst_season_excess_vs_all_off, s1$spec_id
  )
  expect_equal(unname(excess[["alloff"]]), 0)
  expect_gt(excess[["risky"]], 0) # worse than all-off in its worst season
  expect_lt(excess[["safe"]], 0) # never worse than all-off
})

test_that("with no degrading season the best mean still wins", {
  # Guard against the filter being over-eager: when every candidate is robust,
  # selection must fall through to ordinary mean-NLL ranking.
  local_nll <- list(
    alloff = c(S1 = 0.50, S2 = 0.50, S3 = 0.50),
    risky  = c(S1 = 0.10, S2 = 0.10, S3 = 0.30),
    safe   = c(S1 = 0.45, S2 = 0.45, S3 = 0.45)
  )
  grid <- data.frame(
    id = c("alloff", "risky", "safe"),
    enabled_count = c(0L, 1L, 1L),
    stringsAsFactors = FALSE
  )
  seasons <- c("S1", "S2", "S3")

  local_mocked_bindings(
    m2_subset_fit = function(data, spec, ...) {
      list(spec_id = as.character(spec$id[1L]))
    },
    m2_subset_predict = function(fit, newdata) {
      list(p_hat = structure(rep(0.05, nrow(newdata)), spec_id = fit$spec_id))
    },
    m2_subset_score = function(data, prediction, weights = NULL) {
      sid <- attr(prediction, "spec_id")
      nll <- local_nll[[sid]][[as.character(data$season[1L])]]
      c(
        nll_test_count = nll, nll_equal_week = nll,
        mae_test_count = nll, mae_equal_week = nll,
        rows = nrow(data), trials = 100, weight_sum = nrow(data)
      )
    },
    .m2_subset_stage_b_grid = function(stage_a_grid, stage_a_summary) stage_a_grid,
    m2_subset_config = function(h1, h2, alpha_state, gamma) {
      list(h1 = h1, h2 = h2, alpha_state = alpha_state, gamma = gamma)
    }
  )

  td <- m2_fix_test_training_data(seasons)
  res <- PAGe:::.m2_subset_select_core(
    training_data = td,
    row_weights = rep(1, nrow(td)),
    grid = grid,
    training_seasons = seasons,
    scored_seasons_by_horizon = list("1" = seasons, "2" = seasons),
    nll_primary = "nll_equal_week", mae_primary = "mae_equal_week",
    alpha_state = 0.2, gamma = 1.4, n_cores = 1L
  )

  expect_equal(res$selected[[1L]]$id, "risky")
})
