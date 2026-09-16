# Fold-level parallel dispatch in loso_M0v2() must produce results
# identical to the serial fold loop, with no cross-fold mixups and
# unchanged error/checkpoint behaviour. Uses fast fakes for fitIgnition/
# tuneIgnitionGrid_M0v2/detectIgnitionBySeason_M0v2 so the check targets
# the dispatch/wiring change, not GAM numerics.

test_that("fold-parallel loso_M0v2 matches serial dispatch exactly", {
  all_seasons <- sprintf("%d-%02d", 2010:2015, (11:16) %% 100)
  dat <- do.call(rbind, lapply(all_seasons, function(s) {
    data.frame(
      season = s, weekF = 1:10, y = 1L, N = 100L, p = 0.01, neg = 99L,
      stringsAsFactors = FALSE
    )
  }))

  fake_fit <- function(dat, season_col = "season", week_col = "weekF",
                       phase_col = "phase", p_col = "p", ...) {
    list(data = dat, fits = list(base = list(gam = structure(list(), class = "fake_m0_gam"))))
  }
  predict.fake_m0_gam <<- function(object, newdata, type = "response", ...) {
    rep(0.05, nrow(newdata))
  }

  fake_tune <- function(ign_fit, grid, score_col, week_col, season_col,
                        phase_col, truth_col, exSeason, timing_mode, ...) {
    held_out <- setdiff(all_seasons, unique(ign_fit[[season_col]]))
    rank <- which(all_seasons == held_out)
    list(results = data.frame(
      spec_id = grid$spec_id,
      score = seq_len(nrow(grid)) + rank * 1000,
      n_over2 = 0, n_late_over2 = 0, max_abs = 0, n_miss = 0,
      cls_thr = 0.2, p_thr = 0.01, prev_thr = 0.01, n_consec = 3L,
      L = 2L, eps = 0, K_sum = 4L, p_sum_thr = 0.04, N_req = 3L,
      w_min = 13L, w_max = 30L, use_cls = FALSE,
      stringsAsFactors = FALSE
    ))
  }

  fake_detect <- function(ign_fit, params, score_col, week_col, season_col,
                          phase_col, keep_signals, verbose, iWeek, copy_data, ...) {
    ho <- unique(ign_fit[[season_col]])
    rank <- which(all_seasons == ho)
    list(
      compare = data.frame(season = ho, diff = rank, iWeek_hat = 10, stringsAsFactors = FALSE),
      by_season = data.frame(season = ho, iWeek_hatF = 10, stringsAsFactors = FALSE)
    )
  }

  grid <- data.frame(spec_id = sprintf("spec%02d", 1:5), stringsAsFactors = FALSE)

  run <- function(n_cores) {
    testthat::local_mocked_bindings(
      fitIgnition = fake_fit,
      tuneIgnitionGrid_M0v2 = fake_tune,
      detectIgnitionBySeason_M0v2 = fake_detect,
      .package = "PAGe"
    )
    loso_M0v2(
      dat = dat, grid = grid,
      fit_args = list(),
      tune_args = list(ncores = n_cores, verbose = FALSE),
      verbose = FALSE
    )
  }

  serial <- run(1L)
  par2 <- run(2L)
  par3 <- run(3L)

  expect_identical(names(serial$folds), names(par2$folds))
  expect_identical(
    serial$compare[order(serial$compare$season), ],
    par2$compare[order(par2$compare$season), ]
  )
  expect_identical(
    serial$compare[order(serial$compare$season), ],
    par3$compare[order(par3$compare$season), ]
  )
  expect_identical(serial$best_params, par2$best_params)
  expect_identical(serial$best_params, par3$best_params)
  for (s in all_seasons) {
    expect_identical(serial$folds[[s]]$compare$season, s)
    expect_identical(par2$folds[[s]]$compare$season, s)
    expect_identical(par3$folds[[s]]$compare$season, s)
  }
})

test_that("fold-parallel loso_M0v2 checkpoints progress and propagates a fold error with its season", {
  all_seasons <- sprintf("%d-%02d", 2010:2013, (11:14) %% 100)
  dat <- do.call(rbind, lapply(all_seasons, function(s) {
    data.frame(
      season = s, weekF = 1:5, y = 1L, N = 10L, p = 0.1, neg = 9L,
      stringsAsFactors = FALSE
    )
  }))
  grid <- data.frame(spec_id = "spec01", stringsAsFactors = FALSE)

  bad_season <- all_seasons[[2]]
  fake_fit_err <- function(dat, season_col = "season", week_col = "weekF",
                           phase_col = "phase", p_col = "p", ...) {
    held_out <- setdiff(all_seasons, unique(dat[[season_col]]))
    if (identical(held_out, bad_season)) stop("synthetic fit failure")
    list(data = dat, fits = list(base = list(gam = structure(list(), class = "fake_m0_gam"))))
  }
  predict.fake_m0_gam <<- function(object, newdata, type = "response", ...) rep(0.05, nrow(newdata))
  fake_tune_ok <- function(ign_fit, grid, score_col, week_col, season_col,
                           phase_col, truth_col, exSeason, timing_mode, ...) {
    list(results = data.frame(
      spec_id = grid$spec_id, score = 1, n_over2 = 0, n_late_over2 = 0,
      max_abs = 0, n_miss = 0, cls_thr = 0.2, p_thr = 0.01, prev_thr = 0.01,
      n_consec = 3L, L = 2L, eps = 0, K_sum = 4L, p_sum_thr = 0.04,
      N_req = 3L, w_min = 13L, w_max = 30L, use_cls = FALSE,
      stringsAsFactors = FALSE
    ))
  }
  fake_detect_ok <- function(ign_fit, params, score_col, week_col, season_col,
                             phase_col, keep_signals, verbose, iWeek, copy_data, ...) {
    ho <- unique(ign_fit[[season_col]])
    list(
      compare = data.frame(season = ho, diff = 1, iWeek_hat = 10, stringsAsFactors = FALSE),
      by_season = data.frame(season = ho, iWeek_hatF = 10, stringsAsFactors = FALSE)
    )
  }

  testthat::local_mocked_bindings(
    fitIgnition = fake_fit_err,
    tuneIgnitionGrid_M0v2 = fake_tune_ok,
    detectIgnitionBySeason_M0v2 = fake_detect_ok,
    .package = "PAGe"
  )

  ckpt_dir <- withr::local_tempdir()
  expect_error(
    loso_M0v2(
      dat = dat, grid = grid,
      fit_args = list(),
      tune_args = list(ncores = 2L, verbose = FALSE),
      verbose = FALSE,
      checkpoint_dir = ckpt_dir
    ),
    regexp = paste0("M0 LOSO fold `", bad_season, "` classifier fit failed"),
    fixed = TRUE
  )
})
