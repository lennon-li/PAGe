# Regression tests for the build_m2 Phase 2 future::plan() launch.
#
# future (>= 1.66) rejects `future::plan(future::tweak(...))`; build_m2 must
# launch multisession workers via direct plan arguments and restore the
# caller's previous plan via on.exit on both success and error. These tests
# run the real build_m2() (no mocks) through the Phase 2 plan-launch path by
# seeding a matching M1 Phase 1 artifact so Phase 2 executes real M2 workers.

.fixture_build <- function() {
  synth <- PAGe::simulate_flu_seasons(S = 3, weeks = 1:40, seed = 2025)
  synth$season <- factor(synth$season, labels = c("2022-23", "2023-24", "2024-25"))
  allD <- data.frame(
    season = as.character(synth$season),
    weekF = as.integer(synth$newWeek),
    y = as.integer(synth$y),
    neg = as.integer(synth$neg)
  )
  allD$N <- allD$y + allD$neg
  allD$p <- allD$y / allD$N

  trainD <- allD[allD$season != "2024-25", ]
  res_deriv <- PAGe:::estimateDerivs(trainD, k = 10L)
  outs <- split(res_deriv$data, res_deriv$data$season) |>
    lapply(function(df) {
      do.call(
        PAGe:::flagIgnition,
        c(list(df = df, manual_labels = NULL), PAGe:::.default_flag_args())
      )
    })
  aligned_train <- PAGe:::alignIgnition(outs)
  ref <- PAGe:::estimateRef(
    alignedD = aligned_train, exSeason = character(0),
    k = 8L, n_weeks = 52L, method = "fs"
  )

  m1_test <- tibble::tibble(
    season = "2024-25",
    eval_weekF = rep(24:37, each = 2),
    target_weekF = rep(24:37, each = 2) + rep(1:2, 14),
    h = rep(1:2, 14),
    m1_p_hat = 0.15,
    m1_logit_spread = 0.1
  )

  m0 <- list(
    best_params = list(p_thr = 0.01),
    manual_labels = PAGe:::.default_manual_labels(),
    flag_args = PAGe:::.default_flag_args()
  )
  m1 <- list(
    m1_params = list(
      k_ref = 8L, ref_method = "fs", temperature = 0.25, rise_weight = 1.0,
      trough_weight = 0.1, peak_decay = 0.3, slope_weight = 8.0,
      slope_window = 6L, dynamic_temp = FALSE, dynamic_temp_pivot = 10L
    ),
    ref = list(anchorWeek = 20L, pred_df = data.frame(newWeek = 1:52, fit = 0.1)),
    hyper = list(slope = 8)
  )
  cache <- list(
    "2024-25" = list(
      fold = list(
        ref = ref,
        hyper = list(slope = 8),
        aligned_train = aligned_train,
        template_df = ref$pred_df[, c("newWeek", "fit")],
        train_seasons = c("2022-23", "2023-24"),
        test_season = "2024-25"
      ),
      m1_train = NULL,
      m1_test = m1_test
    )
  )
  list(allD = allD, m0 = m0, m1 = m1, cache = cache)
}

.fixture_seed_phase1 <- function(fx, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  identity <- PAGe:::.m1_phase1_identity(
    allD = fx$allD, test_seasons = "2024-25", m0 = fx$m0, m1 = fx$m1
  )
  PAGe:::.write_m1_phase1_artifact(file.path(dir, "m1_phase1.rds"), identity, fx$cache)
  invisible(file.path(dir, "m1_phase1.rds"))
}

.expect_sequential_plan <- function() {
  expect_identical(future::nbrOfWorkers(), 1L)
  expect_true(any(class(future::plan()) == "sequential"))
}

.expect_multisession_plan <- function() {
  expect_identical(future::nbrOfWorkers(), 1L)
  expect_true(any(class(future::plan()) == "multisession"))
}

test_that("build_m2 Phase 2 launches multisession workers and completes", {
  skip_on_cran()
  fx <- .fixture_build()
  dir <- tempfile("page-smoke")
  artifact <- .fixture_seed_phase1(fx, dir)
  withr::defer({
    unlink(dir, recursive = TRUE)
    future::plan(future::sequential)
  })

  grid <- data.frame(
    delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L, alpha_state = 0.20,
    k_r = 0L, k_de = 0L, k_sp = 0L, bias_alpha = 0.05, bias_beta = 0
  )

  future::plan(future::multisession, workers = 1L)
  out <- PAGe::build_m2(
    allD = fx$allD, m0 = fx$m0, m1 = fx$m1, loso_seasons = "2024-25",
    grid = grid, n_cores = 2, checkpoint_dir = dir, verbose = FALSE
  )

  expect_identical(nrow(out$summary), 1L)
  expect_identical(out$summary$spec_id, PAGe:::.m2_spec_ids(grid))
  expect_identical(out$best_spec_id, PAGe:::.m2_spec_ids(grid)[[1L]])
  expect_false(is.null(out$best_spec$formula))
  expect_true(is.finite(out$summary$bernoulli_nll[[1L]]))
  expect_identical(out$m1_artifact_path, artifact)
  expect_true(out$m2_handoff_bytes > 0)
  expect_true(out$m2_handoff_bytes < out$m1_cache_bytes)
  expect_true(file.exists(file.path(dir, "build_m2_phase2.rds")))
  .expect_multisession_plan()
})

test_that("build_m2 restores the previous future plan after a Phase 2 error", {
  skip_on_cran()
  fx <- .fixture_build()
  dir <- tempfile("page-smoke-err")
  .fixture_seed_phase1(fx, dir)
  withr::defer({
    unlink(dir, recursive = TRUE)
    future::plan(future::sequential)
  })

  # k_sp = 8 without M1 stacking features fails deterministically inside the
  # multisession worker, after the Phase 2 plan has been launched.
  grid <- data.frame(
    delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L, alpha_state = 0.20,
    k_r = 0L, k_de = 0L, k_sp = 8L, bias_alpha = 0.05, bias_beta = 0
  )

  future::plan(future::multisession, workers = 1L)
  expect_error(
    PAGe::build_m2(
      allD = fx$allD, m0 = fx$m0, m1 = fx$m1, loso_seasons = "2024-25",
      grid = grid, n_cores = 2, checkpoint_dir = dir, verbose = FALSE
    ),
    "training failed"
  )
  .expect_multisession_plan()
})

test_that("build_m2 rejects invalid future_max_size and restores the plan", {
  skip_on_cran()
  fx <- .fixture_build()
  dir <- tempfile("page-smoke-maxsize")
  .fixture_seed_phase1(fx, dir)
  withr::defer({
    unlink(dir, recursive = TRUE)
    future::plan(future::sequential)
  })

  grid <- data.frame(
    delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L, alpha_state = 0.20,
    k_r = 0L, k_de = 0L, k_sp = 0L, bias_alpha = 0.05, bias_beta = 0
  )

  future::plan(future::sequential)
  expect_error(
    PAGe::build_m2(
      allD = fx$allD, m0 = fx$m0, m1 = fx$m1, loso_seasons = "2024-25",
      grid = grid, n_cores = 2, checkpoint_dir = dir,
      future_max_size = -1, verbose = FALSE
    ),
    "positive finite byte count"
  )
  .expect_sequential_plan()
})
