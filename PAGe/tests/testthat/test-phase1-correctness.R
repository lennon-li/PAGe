.phase1_data <- function() {
  do.call(rbind, lapply(seq_len(3), function(i) {
    w <- 1:24
    p <- 0.005 + (0.12 + 0.04 * i) * exp(-((w - (14 + 4 * i)) / (3 + i))^2)
    data.frame(
      season = c("2017-18", "2018-19", "2019-20")[i],
      weekF = w, y = round(2000 * p), N = 2000, neg = 2000 - round(2000 * p),
      p = round(2000 * p) / 2000, fit = p, iWeek = 10,
      newWeek = w, phase = as.integer(w >= 10)
    )
  }))
}

.phase1_detector <- function(currentSeason, ...) {
  list(
    ign_week_locked = 10L, iWeek_hat_locked = 10L, iWeek_hat_lockedF = 10,
    df = data.frame(weekF = currentSeason$weekF, ignite_ok_now = currentSeason$weekF == 10)
  )
}

test_that("F1 held-out references change inner predictions and preserve runtime M1", {
  dat <- .phase1_data()
  attr(dat, "anchorWeek") <- 10L
  ref <- PAGe:::estimateRef(dat, k = 6L, method = "fs")
  m1 <- list(
    aligned_train = dat, ref = ref,
    hyper = PAGe:::learn_alignment_hyperparams(ref$dat, ref$g_ref_fun),
    m1_params = list(k_ref = 6L, ref_method = "fs")
  )
  original_aligned <- m1$aligned_train
  original_params <- m1$m1_params
  original_pred_df <- m1$ref$pred_df
  references <- PAGe:::.m1_heldout_references(m1, unique(dat$season))
  for (s in names(references)) {
    expect_false(s %in% colnames(references[[s]]$ref$eta_mat))
    expect_setequal(references[[s]]$training_seasons, setdiff(unique(dat$season), s))
    expect_false(s %in% as.character(references[[s]]$ref$dat$season))
  }
  local_mocked_bindings(run_ignition_weekly = .phase1_detector, .package = "PAGe")
  args <- list(
    allD = dat, ref = ref, hyper = m1$hyper, params = list(),
    eval_weeks = c(16L, 20L), use_ci = FALSE, parallel = FALSE, verbose = FALSE
  )
  before <- do.call(PAGe:::m1_walkforward_multi, args)
  heldout <- do.call(
    PAGe:::m1_walkforward_multi,
    c(args, list(season_references = references))
  )
  expect_gt(nrow(heldout), 0L)
  expect_equal(nrow(heldout), nrow(before))
  expect_gt(max(abs(heldout$m1_p_hat - before$m1_p_hat)), 1e-5)
  after <- do.call(PAGe:::m1_walkforward_multi, args)
  expect_identical(after, before)
  expect_identical(m1$aligned_train, original_aligned)
  expect_identical(m1$m1_params, original_params)
  expect_identical(m1$ref$pred_df, original_pred_df)

  # Supplied predictions remain an exact pass-through; the gate reads these
  # same held-out rows, with its correction fit excluding the test season.
  rows <- PAGe:::m2_subset_make_rows(dat, list(best_params = list()), m1,
    m1_train_preds = heldout, detector = .phase1_detector
  )
  expect_identical(rows$m1_train_preds, as.data.frame(heldout))
  local_mocked_bindings(
    m2_subset_fit = function(...) list(),
    m2_subset_predict = function(fit, target) list(p_hat = target$m1_p),
    m1_walkforward_multi = function(seasons, ...) {
      heldout[as.character(heldout$season) %in% as.character(seasons), ,
        drop = FALSE]
    },
    .package = "PAGe"
  )
  gate <- PAGe:::.nested_inner_gate_rows(
    list(
      training_rows = rows$data,
      selected_config = PAGe:::m2_subset_config(),
      grid = PAGe:::m2_subset_grid(k_values = c(0L, 3L)),
      scoring = list(
        scoring = "legacy_0_12", score_scale = "equal_week",
        early_weight = 1, early_max_t_since = 12,
        pre_ignition_weight = 0, late_weight = 1
      )
    ), unique(dat$season),
    data = dat,
    m0 = list(best_params = list()), m1 = m1,
    m2_recipe_grid = PAGe:::m2_subset_grid(k_values = c(0L, 3L))
  )
  key <- function(d, origin, horizon) paste(d$season, d[[origin]], d[[horizon]])
  idx <- match(key(gate, "origin", "horizon"), key(heldout, "eval_weekF", "h"))
  expect_equal(gate$m1_prediction, heldout$m1_p_hat[idx])
  expect_equal(gate$m2_prediction, gate$m1_prediction)
})

test_that("F1 row generation caches one excluded reference per season", {
  dat <- .phase1_data()
  calls <- 0L
  real <- PAGe:::.m1_heldout_references
  local_mocked_bindings(
    .m1_heldout_references = function(m1, seasons, timing_mode) {
      calls <<- calls + 1L
      stats::setNames(lapply(seasons, function(s) list(excluded = s)), seasons)
    },
    m1_walkforward_multi = function(seasons, season_references, ...) {
      expect_named(season_references, seasons)
      do.call(rbind, lapply(seasons, function(s) {
        expect_identical(season_references[[s]]$excluded, s)
        data.frame(season = s, eval_weekF = 16L, target_weekF = 17L, h = 1L, m1_p_hat = 0.1)
      }))
    }, .package = "PAGe"
  )
  args <- list(
    data = dat, m0 = list(best_params = list()), m1 = list(),
    detector = .phase1_detector
  )
  rows <- do.call(PAGe:::m2_subset_make_rows, args)
  expect_identical(calls, 1L)
  repeated <- do.call(
    PAGe:::m2_subset_make_rows,
    c(args, list(m1_train_preds = rows$m1_train_preds))
  )
  expect_identical(repeated, rows)
  expect_identical(calls, 1L)
})

test_that("F2 partial coverage cannot shorten the MMWR calendar", {
  outs <- lapply(c("2024-25", "2025-26", "2023-24"), function(s) {
    iw <- if (s == "2025-26") 9L else 10L
    list(
      data = data.frame(season = s, weekF = 9:28, nW_true = 28L),
      ignition = data.frame(season = s, weekF = iw)
    )
  })
  aligned <- PAGe:::alignIgnition(outs)
  expect_equal(aligned$newWeek[aligned$season == "2025-26" & aligned$weekF == 28L], 29)
  expect_equal(aligned$nW_true, rep(c(52L, 53L, 52L), each = 20L))
  # Complete, correctly labelled calendar data keep the historical mapping.
  complete <- outs
  for (i in seq_along(complete)) {
    complete[[i]]$data <- data.frame(
      season = outs[[i]]$data$season[1L], weekF = 1:52, nW_true = 52L
    )
  }
  actual <- PAGe:::alignIgnition(complete)
  expect_equal(
    actual$newWeek,
    ((actual$weekF + 10 - actual$iWeek - 1) %% actual$nW_true) + 1
  )
  expect_identical(PAGe:::.season_calendar_weeks(data.frame(season = c("2020-21", "2021-22"))), c(53L, 52L))
  expect_error(PAGe:::.season_calendar_weeks(data.frame(season = "unknown", nW_true = 52L)), "Cannot derive")
})

test_that("F3 tune and fit receive identical smoothing and ignition settings", {
  captured <- new.env()
  labels <- c("2017-18" = 10L, "2018-19" = 11L, "2019-20" = 12L)
  local_mocked_bindings(
    build_m0 = function(allD, k_deriv, peak_weight_boost, peak_weight_decay, manual_labels, flag_args, ...) {
      captured$fit <- list(
        k_deriv = k_deriv, peak_weight_boost = peak_weight_boost,
        peak_weight_decay = peak_weight_decay, manual_labels = manual_labels, flag_args = flag_args
      )
      list(aligned = allD)
    },
    estimateRef = function(alignedD, ...) list(dat = alignedD, g_ref_fun = identity),
    learn_alignment_hyperparams = function(...) list(),
    tune_m1_alignment = function(...) {
      captured$tune <- list(...)
      list()
    },
    .package = "PAGe"
  )
  for (mode in c("legacy", "fractional")) {
    for (p in list(list(), list(k_deriv = 12L, peak_weight_boost = 2, peak_weight_decay = 0.5))) {
      m0 <- list(best_params = list(p_thr = 0.01), manual_labels = labels, flag_args = list(w_min = 10L))
      fit <- PAGe::build_m1(.phase1_data(), m0,
        exclude = character(), exclude_live = FALSE,
        m1_params = p, timing_mode = mode
      )
      PAGe::tune_m1(.phase1_data(), m0,
        m1 = list(m1_params = p),
        grid = data.frame(k_ref = 6L), n_cores = 1L, checkpoint_dir = withr::local_tempdir(),
        timing_mode = mode, verbose = FALSE
      )
      expect_identical(captured$tune[names(captured$fit)], captured$fit)
      expect_identical(fit$m1_params, p)
    }
  }
})

.phase1_m0_params <- function() {
  list(
    cls_thr = 0.2, p_thr = 0.01, prev_thr = 0.01,
    n_consec = 2L, L = 1L, eps = 0, K_sum = 1L, p_sum_thr = 0.01,
    N_req = 5L, w_min = 1L, w_max = 8L
  )
}

test_that("F4 classifier voting is optional and misses remain explicit", {
  dat <- data.frame(
    season = "2024-25", weekF = 1:8,
    p = c(0.01, 0.1, rep(0.1, 6)), y = 10L, N = 100L,
    p_cls_p = 0.9, iWeek = 2L
  )
  params <- .phase1_m0_params()
  enabled <- PAGe:::detectIgnitionBySeason_M0v2(dat, c(params, list(use_cls = TRUE)), verbose = FALSE)
  expect_identical(enabled$by_season$iWeek_hat, 2L)
  disabled <- PAGe:::detectIgnitionBySeason_M0v2(dat, c(params, list(use_cls = FALSE)), verbose = FALSE)
  implicit <- PAGe:::detectIgnitionBySeason_M0v2(dat, params, verbose = FALSE)
  expect_identical(implicit, disabled)
  expect_true(all(!disabled$data$cond_cls))
  expect_true(is.na(disabled$by_season$iWeek_hat))
  expect_true(disabled$by_season$detection_failed)
  grid <- as.data.frame(c(params, list(use_cls = FALSE)))
  score <- PAGe:::tuneIgnitionGrid_M0v2(dat, grid, ncores = 1L, verbose = FALSE)
  expect_equal(score$results$n_miss, 1)
  expect_equal(score$results$sum_loss, 106)
  expect_equal(score$results$max_abs, 6)
  expect_equal(score$results$score, 226)
  legacy_diff <- params$w_max - 2L
  legacy_adj <- pmax(legacy_diff, 0) + pmax(-1 - legacy_diff, 0)
  legacy_score <- legacy_adj + 25 * pmax(legacy_adj - 2, 0) + 20 * legacy_adj
  expect_gte(score$results$score, legacy_score)
  expect_equal(score$results$score, legacy_score)
  expect_identical(score$best_params$use_cls, FALSE)
})

test_that("F4 fractional errors are symmetric and late penalties unchanged", {
  dat <- data.frame(
    season = "2024-25", weekF = 1:8, p = 0.1, y = 10L, N = 100L,
    p_cls_p = 0.9, iWeek = 2
  )
  prediction <- 1.5
  detector <- function(...) list(by_season = data.frame(season = "2024-25", iWeek_hat = 2L, iWeek_hatF = prediction))
  local_mocked_bindings(
    detectIgnitionBySeason_M0v2_timing = detector,
    detectIgnitionBySeason_M0v2 = detector, .package = "PAGe"
  )
  score <- function(mode, kappa = 0) {
    PAGe:::tuneIgnitionGrid_M0v2(dat,
      as.data.frame(.phase1_m0_params()),
      ncores = 1L, verbose = FALSE,
      timing_mode = mode, lambda = 0, kappa = kappa
    )$results$sum_loss
  }
  early <- score("fractional")
  prediction <- 2.5
  expect_equal(score("fractional"), early)
  expect_equal(early, 0.5)
  expect_equal(score("fractional", 2), 1.5)
  expect_equal(score("legacy"), 0)
})

test_that("F5 binomial initialization counts each trial once", {
  dat <- data.frame(newWeek = 10:20, y = 2:12, neg = seq(80, 180, by = 10))
  captured <- list()
  local_mocked_bindings(glm = function(formula, family, weights, ...) {
    if (!missing(weights)) captured[[length(captured) + 1L]] <<- weights
    stats::glm(formula, family = family, weights = if (missing(weights)) NULL else weights, ...)
  }, .package = "PAGe")
  args <- list(
    currentD = dat, g_ref_fun = function(x) -4 + x / 10,
    tau_bounds = c(-2, 2), delta_bounds = c(-0.2, 0.2), allow_scale = FALSE,
    week_threshold_delta = 99, lam_delta = 0.1
  )
  fit <- do.call(PAGe:::fit_tau_delta, args)
  expect_gt(length(captured), 1L)
  expect_true(all(vapply(captured, function(w) all(w == 1), logical(1))))
  # Explicit unit time weights are equivalent to the default unaffected path.
  explicit <- do.call(PAGe:::fit_tau_delta, c(args, list(time_weights = rep(1, nrow(dat)))))
  expect_equal(explicit, fit)
})

test_that("F6 audit preserves seeded results and retains bounded warning counts", {
  directory <- withr::local_tempdir()
  set.seed(31)
  initial <- .Random.seed
  expected <- stats::runif(3)
  set.seed(31)
  actual <- PAGe:::.page_training_audit(
    {
      warning("repeated")
      warning("repeated")
      warning("second")
      warning("overflow")
      PAGe:::.nested_save_rds(list(stage = "m1"), directory, "stage.rds")
      stats::runif(3)
    },
    directory,
    max_messages = 2L
  )
  expect_identical(actual, expected)
  post <- readRDS(file.path(directory, "post_training_manifest.rds"))
  expect_identical(post$rng_start$state, initial)
  expect_identical(post$warnings$messages$count, c(2L, 1L))
  expect_identical(post$warnings$total, 4L)
  expect_identical(post$warnings$overflow_count, 1L)
  expect_true("gratia" %in% names(post$package_versions))
  stage <- readRDS(file.path(directory, "stage.rds"))
  expect_identical(attr(stage, "reproducibility")$run_rng_start$state, initial)
  expect_true(post$success)
  expect_error(PAGe:::.page_training_audit(stop("synthetic failure"), directory), "synthetic failure")
  expect_false(readRDS(file.path(directory, "post_training_manifest.rds"))$success)
})
