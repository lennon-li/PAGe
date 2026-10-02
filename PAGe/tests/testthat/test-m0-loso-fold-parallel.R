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


test_that("fractional loso_M0v2 uses explicit decimal timing truth for tuning and held-out scoring", {
  seasons <- c("2012-13", "2013-14", "2014-15")
  dat <- do.call(rbind, lapply(seasons, function(s) {
    data.frame(
      season = s, weekF = 1:8, y = 1L, N = 100L, p = 0.01,
      phase = as.integer(1:8 >= 6L), stringsAsFactors = FALSE
    )
  }))
  truth <- data.frame(
    season = seasons,
    ignition_target_weekF = c(5.25, 5.50, 5.75),
    stringsAsFactors = FALSE
  )
  seen_truth <- new.env(parent = emptyenv())

  fake_fit <- function(dat, timing_truth = NULL, ...) {
    list(data = dat, fits = list(base = list(gam = structure(list(), class = "fake_m0_decimal_gam"))))
  }
  predict.fake_m0_decimal_gam <<- function(object, newdata, type = "response", ...) {
    rep(0.05, nrow(newdata))
  }
  fake_tune <- function(ign_fit, grid, season_col, timing_truth = NULL, ...) {
    held_out <- setdiff(seasons, unique(as.character(ign_fit[[season_col]])))
    seen_truth[[held_out]] <- timing_truth
    list(results = data.frame(
      spec_id = grid$spec_id,
      score = 1, sum_loss = 1, max_abs = 0, n_miss = 0,
      n_over2 = 0, n_late_over2 = 0, mean_abs = 0,
      cls_thr = 0.2, p_thr = 0.01, prev_thr = 0.01,
      n_consec = 3L, L = 2L, eps = 0, K_sum = 4L,
      p_sum_thr = 0.04, N_req = 3L, w_min = 1L, w_max = 8L,
      use_cls = FALSE, stringsAsFactors = FALSE
    ))
  }
  fake_detect_timing <- function(ign_fit, season_col = "season", ...) {
    ho <- unique(as.character(ign_fit[[season_col]]))
    list(
      compare = data.frame(
        season = ho, iWeek_true = 6, iWeek_hat = 6,
        diff = 0, diffF = 0, stringsAsFactors = FALSE
      ),
      by_season = data.frame(
        season = ho, iWeek_hat = 6, iWeek_hatF = 5.6,
        stringsAsFactors = FALSE
      )
    )
  }

  grid <- data.frame(
    spec_id = "decimal_spec", cls_thr = 0.2, use_cls = FALSE,
    p_thr = 0.01, prev_thr = 0.01, n_consec = 3L, L = 2L, eps = 0,
    K_sum = 4L, p_sum_thr = 0.04, N_req = 3L, w_min = 1L, w_max = 8L,
    stringsAsFactors = FALSE
  )

  testthat::local_mocked_bindings(
    fitIgnition = fake_fit,
    tuneIgnitionGrid_M0v2 = fake_tune,
    detectIgnitionBySeason_M0v2_timing = fake_detect_timing,
    .package = "PAGe"
  )

  out <- loso_M0v2(
    dat = dat, grid = grid,
    fit_args = list(),
    tune_args = list(ncores = 1L, verbose = FALSE),
    timing_truth = truth,
    timing_mode = "fractional",
    verbose = FALSE
  )

  for (s in seasons) {
    tt <- seen_truth[[s]]
    expect_false(s %in% tt$season)
    expect_setequal(tt$season, setdiff(seasons, s))
  }
  got <- out$compare[match(seasons, out$compare$season), ]
  expect_equal(got$iWeek_true, truth$ignition_target_weekF)
  expect_equal(got$iWeek_hatF, rep(5.6, length(seasons)))
  expect_equal(got$diff, 5.6 - truth$ignition_target_weekF)
})
