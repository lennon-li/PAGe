# Regression tests for the M1 tuning alignment-reuse speedup.
#
# The optimization computes the slope_weight-independent per-template
# alignment once and re-ensembles for each weighting. These tests prove the
# reweighting is exact and that tune_m1_alignment only shares an alignment pass
# across specs whose alignment inputs are identical.

.alignment_reuse_fixture <- function(seed = 1L) {
  set.seed(seed)
  n_weeks <- 30L
  eta_mat <- sapply(1:3, function(s) {
    mu <- 0.02 + 0.18 * exp(-((seq_len(n_weeks) - 16)^2) / 40) * (0.8 + 0.2 * s)
    stats::qlogis(pmin(pmax(mu + stats::rnorm(n_weeks, 0, 0.01), 0.002), 0.998))
  })
  colnames(eta_mat) <- c("S1", "S2", "S3")
  spline_all <- stats::splinefun(seq_len(n_weeks), rowMeans(eta_mat), method = "natural")
  g_ref_fun <- function(u) spline_all(pmin(pmax(u, 1), n_weeks))
  list(
    eta_mat = eta_mat,
    g_ref_fun = g_ref_fun,
    g_ref_mu_se = function(u) list(mu = g_ref_fun(u), se = rep(0.05, length(u))),
    hyper = list(
      TAU_BOUNDS = c(-6, 6), DELTA_BOUNDS = c(-0.2, 0.2),
      WEEK_THRESHOLD_DELTA = 16, LAMBDA_DELTA = 0.1
    ),
    currentD = data.frame(
      newWeek = 1:14,
      y = c(0, 0, 1, 1, 2, 3, 5, 7, 9, 11, 13, 15, 16, 17),
      neg = 200 - c(0, 0, 1, 1, 2, 3, 5, 7, 9, 11, 13, 15, 16, 17)
    )
  )
}

.alignment_reuse_args <- function(fx, ...) {
  list(
    currentD = fx$currentD, eta_mat = fx$eta_mat,
    g_ref_fun = fx$g_ref_fun, g_ref_mu_se = fx$g_ref_mu_se,
    hyper = fx$hyper, allow_scale = TRUE, level = 0.95,
    future_weeks = seq(1, 30, by = 1), include_observed = TRUE,
    top_k = NULL, blend_alpha = 1.0, trough_weight = 0.1,
    rise_weight = 1.0, peak_decay = 0.3, gam_obj = NULL,
    spread_method = "between", timing_mode = "legacy", ...
  )
}

test_that("align_multi_template prep reuse is exact across weighting axes", {
  fx <- .alignment_reuse_fixture()
  prep <- do.call(
    PAGe:::align_multi_template,
    .alignment_reuse_args(fx, return_prep = TRUE)
  )
  for (sw in c(0, 8, 20)) {
    for (tp in c(0.25, 1.0)) {
      direct <- do.call(
        PAGe:::align_multi_template,
        .alignment_reuse_args(fx, slope_weight = sw, temperature = tp)
      )
      reused <- do.call(
        PAGe:::align_multi_template,
        .alignment_reuse_args(fx, slope_weight = sw, temperature = tp, prep = prep)
      )
      expect_equal(reused$tau, direct$tau, tolerance = 1e-13)
      expect_equal(reused$delta, direct$delta, tolerance = 1e-13)
      expect_equal(reused$a, direct$a, tolerance = 1e-13)
      expect_equal(reused$b, direct$b, tolerance = 1e-13)
      expect_equal(reused$nll, direct$nll, tolerance = 1e-13)
      expect_equal(reused$weights, direct$weights, tolerance = 1e-13)
      expect_equal(reused$peak, direct$peak, tolerance = 1e-13)
      expect_equal(
        as.data.frame(reused$pred_df),
        as.data.frame(direct$pred_df),
        tolerance = 1e-13
      )
    }
  }
})

test_that("prep carries no weighting-axis state", {
  fx <- .alignment_reuse_fixture()
  prep_lo <- do.call(
    PAGe:::align_multi_template,
    .alignment_reuse_args(fx,
      slope_weight = 0, temperature = 0.25,
      dynamic_temp = FALSE, return_prep = TRUE
    )
  )
  prep_hi <- do.call(
    PAGe:::align_multi_template,
    .alignment_reuse_args(fx,
      slope_weight = 20, temperature = 1.0,
      dynamic_temp = TRUE, return_prep = TRUE
    )
  )
  expect_identical(prep_lo, prep_hi)
})

test_that("run_alignment_prospective_multi_weights matches one pass per spec", {
  fx <- .alignment_reuse_fixture()
  ref <- list(
    eta_mat = fx$eta_mat, anchorWeek = 20L, g_ref_fun = fx$g_ref_fun,
    g_ref_mu_se = fx$g_ref_mu_se, mod2 = list(gam = NULL)
  )
  currentSeason <- data.frame(
    weekF = 1:14, y = fx$currentD$y, neg = fx$currentD$neg
  )
  ign_out <- list(
    ign_week_locked = 5L, iWeek_hat_locked = 5L, iWeek_hat_lockedF = 5,
    iWeek_hat_bracket = NULL
  )
  common <- list(
    currentSeason = currentSeason, ref = ref, hyper = fx$hyper,
    ign_out = ign_out, use_ci = TRUE, buffer_weeks = 0L, allow_scale = TRUE,
    level = 0.95, min_obs = 4L, curvature_ratio = 1.0, trough_weight = 0.1,
    rise_weight = 1.0, peak_decay = 0.3, top_k = NULL, blend_alpha = 1.0,
    spread_method = "between", timing_mode = "legacy"
  )
  weight_sets <- list(
    a = list(
      slope_weight = 0, temperature = 0.25, slope_window = 6L,
      dynamic_temp = FALSE, dynamic_temp_pivot = 10L
    ),
    b = list(
      slope_weight = 8, temperature = 0.25, slope_window = 6L,
      dynamic_temp = TRUE, dynamic_temp_pivot = 10L
    ),
    c = list(
      slope_weight = 20, temperature = 1.0, slope_window = 4L,
      dynamic_temp = TRUE, dynamic_temp_pivot = 8L
    )
  )
  batch <- do.call(
    PAGe:::run_alignment_prospective_multi_weights,
    c(common, list(weight_sets = weight_sets))
  )

  for (sid in names(weight_sets)) {
    ws <- weight_sets[[sid]]
    single <- do.call(
      PAGe:::run_alignment_prospective_multi,
      c(common, list(
        slope_weight = ws$slope_weight, temperature = ws$temperature,
        slope_window = ws$slope_window, dynamic_temp = ws$dynamic_temp,
        dynamic_temp_pivot = ws$dynamic_temp_pivot
      ))
    )
    expect_equal(batch[[sid]]$state, single$state)
    expect_equal(batch[[sid]]$tau, single$tau, tolerance = 1e-13)
    expect_equal(batch[[sid]]$delta, single$delta, tolerance = 1e-13)
    expect_equal(batch[[sid]]$t_peak, single$t_peak, tolerance = 1e-13)
    expect_equal(batch[[sid]]$weights, single$weights, tolerance = 1e-13)
    expect_equal(
      as.data.frame(batch[[sid]]$forecast_df),
      as.data.frame(single$forecast_df),
      tolerance = 1e-13
    )
  }
})

test_that("tune_m1_alignment shares one alignment pass across weighting-only specs", {
  fake_wf <- function() {
    list(
      params_df = tibble::tibble(
        season = "b", eval_week = 1L, iWeek_true = 1L, iWeek_hat = 1L,
        t_peak = 1.2, t_peak_median = 1.1, anchorWeek = 1L
      ),
      forecast_df = tibble::tibble()
    )
  }
  calls <- new.env(parent = emptyenv())
  calls$single <- 0L
  calls$multi <- 0L
  calls$multi_sizes <- integer(0)

  local_mocked_bindings(
    loso_walkforward = function(...) {
      calls$single <- calls$single + 1L
      fake_wf()
    },
    loso_walkforward_weights = function(weight_sets, ...) {
      calls$multi <- calls$multi + 1L
      calls$multi_sizes <- c(calls$multi_sizes, length(weight_sets))
      stats::setNames(
        lapply(names(weight_sets), function(sid) fake_wf()),
        names(weight_sets)
      )
    },
    .package = "PAGe"
  )

  dat <- data.frame(season = "b", weekF = 1:3, p = c(0.01, 0.05, 0.02), N = 100)

  invisible(PAGe::tune_m1_alignment(
    dat,
    params = list(),
    grid = data.frame(slope_weight = c(8, 20)),
    n_cores = 1L, checkpoint_dir = withr::local_tempdir(), verbose = FALSE
  ))
  expect_equal(calls$single, 0L)
  expect_equal(calls$multi, 1L)
  expect_equal(calls$multi_sizes, 2L)

  calls$single <- 0L
  calls$multi <- 0L
  calls$multi_sizes <- integer(0)
  invisible(PAGe::tune_m1_alignment(
    dat,
    params = list(),
    grid = data.frame(k_ref = c(10L, 20L)),
    n_cores = 1L, checkpoint_dir = withr::local_tempdir(), verbose = FALSE
  ))
  expect_equal(calls$single, 2L)
  expect_equal(calls$multi, 0L)
})

test_that("tune_m1_alignment does not group specs when multi-template is off", {
  calls <- new.env(parent = emptyenv())
  calls$single <- 0L
  calls$multi <- 0L
  local_mocked_bindings(
    loso_walkforward = function(...) {
      calls$single <- calls$single + 1L
      list(
        params_df = tibble::tibble(
          season = "b", eval_week = 1L, iWeek_true = 1L, iWeek_hat = 1L,
          t_peak = 1.2, t_peak_median = 1.1, anchorWeek = 1L
        ),
        forecast_df = tibble::tibble()
      )
    },
    loso_walkforward_weights = function(...) {
      calls$multi <- calls$multi + 1L
      stop("grouped path must not run")
    },
    .package = "PAGe"
  )
  dat <- data.frame(season = "b", weekF = 1:3, p = c(0.01, 0.05, 0.02), N = 100)
  invisible(PAGe::tune_m1_alignment(
    dat,
    params = list(),
    grid = data.frame(slope_weight = c(8, 20)),
    n_cores = 1L, checkpoint_dir = withr::local_tempdir(), verbose = FALSE,
    use_multi_template = FALSE
  ))
  expect_equal(calls$single, 2L)
  expect_equal(calls$multi, 0L)
})

test_that("alignment prep failure matches the single-spec pre-ignition fallback", {
  fx <- .alignment_reuse_fixture()
  local_mocked_bindings(
    .m1_build_alignment_prep = function(...) stop("template build failed"),
    .package = "PAGe"
  )
  ref <- list(
    eta_mat = fx$eta_mat, anchorWeek = 20L, g_ref_fun = fx$g_ref_fun,
    g_ref_mu_se = fx$g_ref_mu_se, mod2 = list(gam = NULL)
  )
  common <- list(
    currentSeason = data.frame(weekF = 1:14, y = fx$currentD$y, neg = fx$currentD$neg),
    ref = ref, hyper = fx$hyper, allow_scale = TRUE,
    ign_out = list(ign_week_locked = 5L, iWeek_hat_locked = 5L, iWeek_hat_lockedF = 5)
  )
  ws <- list(
    slope_weight = 8, temperature = 0.25, slope_window = 6L,
    dynamic_temp = FALSE, dynamic_temp_pivot = 10L
  )
  batch <- do.call(
    PAGe:::run_alignment_prospective_multi_weights,
    c(common, list(weight_sets = list(a = ws, b = ws)))
  )
  single <- do.call(PAGe:::run_alignment_prospective_multi, c(common, ws))
  expect_identical(single$state, "alignment_failed")
  expect_identical(single$fallback_reason, "template build failed")
  expect_identical(batch$a, single)
  expect_identical(batch$b, single)
})

test_that("broad tau/delta windows surface insufficient common support", {
  # Broad-window regression (restores the original +/-12 tau and +/-0.35 delta
  # bounds that were narrowed to +/-6 / +/-0.2 for the reuse fixtures).
  #
  # Documented contract: alignment support is the candidate-independent
  # intersection of template-admissible rows over the complete optimiser window
  # (PAGe/R/m1_fit.R, .page_alignment_common_support). When that support drops
  # below min_support the alignment must fail explicitly instead of silently
  # returning a reduced-support fit. The documented failure messages are:
  #   - "M1 alignment has insufficient common support in the optimizer window."
  #     (fit_tau_delta, optimizer-window support check)
  #   - "M1 alignment candidate has fewer than the minimum admissible
  #     template-support rows." / "...insufficient admissible support after
  #     fitting." (align_forecast_pipeline_dilate)
  #
  # This path is reached through align_multi_template(): every template fails
  # the support check, the all-invalid fallback re-runs the population
  # reference, and the explicit error propagates. Matching on "support" pins the
  # contract without over-specifying which of the documented checks fires first.
  # If Jax's concurrent work replaces the stop() with a structured failure state
  # (for example a returned `state` field), assert that state here instead; Ming
  # reconciles.
  fx <- .alignment_reuse_fixture()
  fx$hyper$TAU_BOUNDS <- c(-12, 12)
  fx$hyper$DELTA_BOUNDS <- c(-0.35, 0.35)
  expect_error(
    do.call(PAGe:::align_multi_template, .alignment_reuse_args(fx)),
    "support"
  )
})
