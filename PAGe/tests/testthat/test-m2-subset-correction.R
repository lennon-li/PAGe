testthat::test_that("subset grid has per-term basis choices including zero", {
  g <- PAGe:::m2_subset_grid()
  testthat::expect_equal(nrow(g), 686L)
  testthat::expect_equal(anyDuplicated(g$id), 0L)
  testthat::expect_equal(g$id[1L], "i0_kz0_ku0_kd0")
  testthat::expect_equal(g$enabled_count[1L], 0)
  testthat::expect_true(all(g$enabled_count == as.integer(g$intercept) +
    rowSums(g[c("k_z", "k_u", "k_d")] > 0)))
})

testthat::test_that("all-off is exactly the M1 offset and has no GAM fit", {
  g <- PAGe:::m2_subset_grid()[1L, , drop = FALSE]
  d <- data.frame(
    season = rep(c("a", "b"), each = 4),
    lead = rep(c("h1", "h2"), 4),
    m1_logit = seq(-3, 1, length.out = 8),
    y_lead = c(1, 2, 4, 5, 2, 3, 5, 6), N_lead = 20
  )
  fit <- PAGe:::m2_subset_fit(d, g)
  pred <- PAGe:::m2_subset_predict(fit, d)
  testthat::expect_equal(fit$type, "all_off")
  testthat::expect_null(fit[["fit"]])
  testthat::expect_equal(pred$p_hat, stats::plogis(d$m1_logit), tolerance = 0)
})

testthat::test_that("disabled intercept is absent and disabling terms removes dependencies", {
  g <- PAGe:::m2_subset_grid()
  for (i in seq_len(nrow(g))) {
    ftxt <- paste(deparse(PAGe:::m2_subset_formula(g[i, ])), collapse = " ")
    for (nm in c("z", "u", "d")) {
      has_term <- grepl(sprintf("s\\(%s,", nm), ftxt)
      testthat::expect_identical(has_term, g[[paste0("k_", nm)]][i] > 0)
    }
    has_intercept <- grepl("(^|[+ ])lead([+ ]|$)", ftxt)
    testthat::expect_identical(has_intercept, isTRUE(g$intercept[i]))
    if (!isTRUE(g$intercept[i])) testthat::expect_false(grepl("~.*\\+ lead", ftxt))
  }
})

testthat::test_that("known correction recovery uses an offset, not an M1 coefficient", {
  testthat::skip_if_not_installed("mgcv")
  set.seed(20260908)
  n <- 2400L
  d <- data.frame(
    season = rep(sprintf("s%02d", 1:12), each = 200),
    lead = rep(rep(c("h1", "h2"), each = 100), 12),
    m1_logit = stats::runif(n, -3, 1), z = stats::runif(n, -3, 1),
    u = stats::runif(n, 0, 12), d = stats::runif(n, -1, 1), N_lead = 200
  )
  true_shift <- ifelse(d$lead == "h1", 0.35, -0.25)
  d$y_lead <- stats::rbinom(n, d$N_lead, stats::plogis(d$m1_logit + true_shift))
  spec <- PAGe:::m2_subset_spec(intercept = TRUE)
  fit <- PAGe:::m2_subset_fit(d, spec)
  pred <- PAGe:::m2_subset_predict(fit, d)
  recovered <- tapply(pred$correction_logit, d$lead, median)
  testthat::expect_true(fit$converged)
  testthat::expect_lt(max(abs(recovered - c(h1 = 0.35, h2 = -0.25))), 0.12)
  testthat::expect_false(any(grepl("m1_logit", names(stats::coef(fit$fit)), fixed = TRUE)))
})

testthat::test_that("ridge shrinkage pulls a horizon correction toward zero", {
  testthat::skip_if_not_installed("mgcv")
  d <- data.frame(
    season = rep(c("a", "b"), each = 40),
    lead = rep(c("h1", "h2"), 40), m1_logit = -1,
    z = seq(-3, 1, length.out = 80), u = 1, d = 0,
    N_lead = 100, y_lead = 50
  )
  fit <- PAGe:::m2_subset_fit(d,
    PAGe:::m2_subset_spec(intercept = TRUE),
    intercept_sp = 1e12
  )
  pred <- PAGe:::m2_subset_predict(fit, d)
  testthat::expect_lt(max(abs(pred$correction_logit)), 1e-7)
})

testthat::test_that("feature construction uses adjacent observations and is prefix-safe", {
  obs <- data.frame(
    season = "a", weekF = c(1L, 2L, 4L, 5L),
    y = c(1, 2, 4, 5), N = 100
  )
  f <- PAGe:::m2_subset_observed_features(obs, declaration_week = 2, alpha_state = 0.2)
  testthat::expect_true(is.na(f$d[1L]))
  testthat::expect_true(is.finite(f$d[2L]))
  testthat::expect_true(is.na(f$d[3L]))
  testthat::expect_true(is.finite(f$d[4L]))
  before <- f[f$weekF <= 2L, c("z", "u", "d")]
  obs$y[obs$weekF > 2L] <- 99
  after <- PAGe:::m2_subset_observed_features(obs, declaration_week = 2, alpha_state = 0.2)
  testthat::expect_equal(after[after$weekF <= 2L, c("z", "u", "d")], before,
    tolerance = 0
  )
})

testthat::test_that("prefix declaration never receives observations after the origin", {
  observed_max <- integer()
  detector <- function(currentSeason, params, start_week) {
    observed_max <<- c(observed_max, max(currentSeason$weekF))
    list(
      ign_week_locked = if (max(currentSeason$weekF) >= 3L) 3L else NA_integer_,
      df = data.frame(weekF = currentSeason$weekF, ignite_ok_now = FALSE)
    )
  }
  obs <- data.frame(
    season = "a", weekF = 1:5, y = 1:5, N = 100
  )
  out <- PAGe:::m2_subset_prefix_declaration(
    obs,
    params = list(), origin_week = 3L, detector = detector
  )
  testthat::expect_equal(observed_max, 3L)
  testthat::expect_equal(out$week, 3L)
  testthat::expect_equal(out$rows_evaluated, 3L)
})

testthat::test_that("mgcv convergence requires a full outer convergence diagnostic", {
  full <- list(converged = TRUE, outer.info = list(conv = "full convergence"))
  failed <- list(converged = TRUE, outer.info = list(conv = "step failed"))
  testthat::expect_true(PAGe:::m2_subset_is_converged(full))
  testthat::expect_false(PAGe:::m2_subset_is_converged(failed))
  testthat::expect_true(PAGe:::m2_subset_is_converged(list(converged = TRUE)))
})

testthat::test_that("count, horizon, finite, and training-range checks are explicit", {
  g <- PAGe:::m2_subset_spec(z = TRUE)
  d <- data.frame(
    season = rep(c("a", "b"), each = 4),
    lead = rep(c("h1", "h2"), 4), m1_logit = 0, z = seq(-1, 1, length.out = 8),
    y_lead = 1, N_lead = 10
  )
  testthat::expect_error(PAGe:::m2_subset_fit(transform(d, y_lead = 11), g), "counts")
  testthat::expect_error(PAGe:::m2_subset_fit(transform(d, lead = "h3"), g), "h1 and h2")
  testthat::expect_error(PAGe:::m2_subset_fit(transform(d, z = Inf), g), "finite")
  testthat::expect_error(PAGe:::m2_subset_predict(
    PAGe:::m2_subset_fit(d, g), transform(d, z = NULL)
  ), "missing")
})

testthat::test_that("zero basis dimensions preserve the exact M1 offset baseline", {
  spec <- PAGe:::m2_subset_spec(k_z = 0L, k_u = 0L, k_d = 0L)
  expect_equal(spec$enabled_count, 0L)
  expect_true(grepl("offset\\(m1_logit\\)", paste(deparse(
    PAGe:::m2_subset_formula(spec)
  ), collapse = " ")))
  expect_false(grepl("s\\(", paste(deparse(PAGe:::m2_subset_formula(spec)), collapse = " ")))
})
