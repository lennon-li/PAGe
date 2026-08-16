test_that("M1 Phase 1 handoff drops M1-only payloads", {
  full <- list(
    `2024-25` = list(
      fold = list(
        ref = list(anchorWeek = 19L, fitted = stats::runif(4)),
        hyper = list(slope = 8),
        aligned_train = data.frame(season = "2023-24", weekF = 1L),
        template_df = data.frame(newWeek = 1:2, fit = c(0.1, 0.2)),
        train_seasons = "2023-24",
        test_season = "2024-25"
      ),
      m1_train = data.frame(eval_weekF = 1L, h = 1L, m1_p_hat = 0.1),
      m1_test = data.frame(eval_weekF = 1L, h = 1L, m1_p_hat = 0.2)
    )
  )

  compact <- PAGe::compact_m1_cache_for_m2(full)
  expect_named(compact, "2024-25")
  expect_named(
    compact[[1]]$fold,
    c("aligned_train", "template_df", "train_seasons", "test_season", "anchorWeek")
  )
  expect_false("ref" %in% names(compact[[1]]$fold))
  expect_false("hyper" %in% names(compact[[1]]$fold))
  expect_identical(compact[[1]]$fold$anchorWeek, 19L)
  expect_identical(compact[[1]]$m1_train, full[[1]]$m1_train)
  expect_identical(compact[[1]]$m1_test, full[[1]]$m1_test)
})

test_that("M1 Phase 1 artifact round-trips with identity", {
  cache <- list(
    `2024-25` = list(
      fold = list(
        aligned_train = data.frame(season = "2023-24"),
        template_df = data.frame(newWeek = 1L, fit = 0.1),
        train_seasons = "2023-24",
        test_season = "2024-25"
      ),
      m1_train = data.frame(x = 1),
      m1_test = data.frame(x = 2)
    )
  )
  identity <- list(context = "test-identity")
  path <- tempfile(fileext = ".rds")
  withr::defer(unlink(path))

  PAGe:::.write_m1_phase1_artifact(path, identity, cache)
  expect_identical(
    PAGe:::.read_m1_phase1_artifact(path, identity),
    cache
  )
  expect_null(PAGe:::.read_m1_phase1_artifact(path, list(context = "other")))
})

test_that("M0 handoff retains only the inputs M1 consumes", {
  aligned <- data.frame(
    season = c("2023-24", "2024-25"), weekF = c(1L, 1L),
    y = c(1, 2), N = c(10, 10)
  )
  m0 <- list(
    aligned = aligned,
    seasons_used = c("2023-24", "2024-25"),
    best_params = list(p_thr = 0.01),
    manual_labels = c("2023-24" = 20L),
    flag_args = list(n_consec = 2L),
    tuning = list(large = stats::runif(4)),
    grid = data.frame(p_thr = c(0.01, 0.02))
  )

  handoff <- PAGe::compact_m0_artifact_for_m1(m0)
  expect_named(
    handoff,
    c("aligned", "seasons_used", "best_params", "manual_labels", "flag_args", "data_id")
  )
  expect_identical(handoff$aligned, aligned)
  expect_identical(handoff$best_params, m0$best_params)
  expect_false("tuning" %in% names(handoff))
  expect_false("grid" %in% names(handoff))
})

test_that("M0 handoff derives seasons and permits legacy minimal inputs", {
  aligned <- data.frame(season = c("2023-24", "2024-25"))
  derived <- PAGe::compact_m0_artifact_for_m1(list(aligned = aligned))
  expect_identical(derived$seasons_used, c("2023-24", "2024-25"))

  minimal <- PAGe::compact_m0_artifact_for_m1(list(best_params = list(x = 1)))
  expect_null(minimal$aligned)
  expect_identical(minimal$best_params, list(x = 1))
})

test_that("build_m1 reuses a season-matched M0 alignment", {
  aligned <- data.frame(
    season = c("2023-24", "2024-25"), newWeek = c(1, 1),
    y = c(1, 2), neg = c(9, 8)
  )
  local_mocked_bindings(
    build_m0 = function(...) stop("M0 should not be rebuilt"),
    estimateRef = function(alignedD, ...) {
      expect_identical(alignedD, aligned)
      list(
        dat = alignedD,
        g_ref_fun = function(x) x,
        pred_df = data.frame(newWeek = 1, fit = 0.1),
        anchorWeek = 20L
      )
    },
    learn_alignment_hyperparams = function(...) list(slope = 8),
    .package = "PAGe"
  )

  out <- PAGe::build_m1(
    allD = data.frame(
      season = aligned$season, weekF = aligned$newWeek,
      y = aligned$y, N = aligned$y + aligned$neg
    ),
    m0 = list(
      aligned = aligned,
      seasons_used = c("2023-24", "2024-25"),
      manual_labels = integer(), flag_args = list()
    ),
    exclude = character(), exclude_live = FALSE,
    m1_params = list(k_ref = 2L)
  )
  expect_identical(out$aligned_train, aligned)
})
