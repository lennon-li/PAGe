# Full subset tuning with synthetic observations, supplied M1 predictions and
# a deterministic ignition adapter. No surveillance data or reference fit.
m2_parallel_fixture <- function() {
  seasons <- c("2019-20", "2017-18", "2018-19")
  data <- do.call(rbind, lapply(seq_along(seasons), function(i) {
    data.frame(
      season = seasons[i], weekF = 1:18,
      y = round(10 + 4 * sin((1:18 + i) / 4)), N = 100L,
      nW_true = 18L
    )
  }))
  preds <- do.call(rbind, lapply(seasons, function(s) {
    d <- expand.grid(eval_weekF = 4:16, h = 1:2)
    d$season <- s
    d$target_weekF <- d$eval_weekF + d$h
    d$m1_p_hat <- 0.08 + 0.02 * sin(d$target_weekF / 5)
    d
  }))
  detector <- function(currentSeason, params, start_week) {
    list(
      ign_week_locked = 3L,
      df = data.frame(weekF = currentSeason$weekF, ignite_ok_now = FALSE)
    )
  }
  grid <- do.call(rbind, list(
    PAGe:::m2_subset_spec(k_u = 200L), # More basis coefficients than rows: fails.
    PAGe:::m2_subset_spec(intercept = TRUE),
    PAGe:::m2_subset_spec(k_z = 3L),
    PAGe:::m2_subset_spec()
  ))
  list(
    data = data,
    selection = PAGe::validate_season_selection(data, training_seasons = seasons),
    m0 = list(best_params = list(), artifact_id = "synthetic-m0"),
    m1 = list(artifact_id = "synthetic-m1"),
    grid = grid, m1_train_preds = preds, detector = detector,
    early_weight = 2, late_weight = 0.5, score_scale = "equal_week"
  )
}

m2_parallel_host <- function() {
  testthat::skip_on_os("windows")
  testthat::skip_if_not(future::supportsMulticore())
}

test_that("full subset tuning is identical across cores, including failed specs", {
  m2_parallel_host()
  withr::local_envvar(PAGE_FUTURE_BACKEND = "multicore")
  old_plan <- future::plan()
  on.exit(future::plan(old_plan), add = TRUE)
  future::plan(future::multicore, workers = 3L)
  before <- future::plan()
  args <- m2_parallel_fixture()
  serial <- do.call(PAGe:::m2_subset_tune, c(args, list(n_cores = 1L)))

  # Verify actual forked spec evaluation, not merely an identical serial fallback.
  trace_dir <- withr::local_tempdir()
  real_fit <- PAGe:::m2_subset_fit
  local_mocked_bindings(
    m2_subset_fit = function(...) {
      file.create(file.path(trace_dir, as.character(Sys.getpid())))
      real_fit(...)
    },
    .package = "PAGe"
  )
  parallel_result <- do.call(PAGe:::m2_subset_tune, c(args, list(n_cores = 2L)))
  # Backend initialization metadata may change when a future plan is restored.
  expect_identical(class(future::plan()), class(before))
  expect_identical(as.integer(future::nbrOfWorkers()), 3L)
  expect_gte(length(list.files(trace_dir)), 2L)
  expect_false(as.character(Sys.getpid()) %in% list.files(trace_dir))
  expect_identical(parallel_result, serial)
  expect_identical(max(abs(parallel_result$scores$bernoulli_nll -
    serial$scores$bernoulli_nll), na.rm = TRUE), 0)
  failed <- serial$scores$spec_id == args$grid$id[1L]
  expect_true(all(serial$scores$status[failed] == "failed"))
  expect_true(all(is.na(serial$scores$bernoulli_nll[failed])))
  expect_true(any(serial$scores$status == "ok"))
  expect_true(all(args$grid$id %in% unique(serial$scores$spec_id)))
  expect_gt(length(unique(serial$scores$spec_id)), length(args$grid$id))
  # Existing tuning checkpoints have no failure_reason column: NULL is preserved.
  expect_identical(parallel_result$scores$failure_reason, serial$scores$failure_reason)
  expect_identical(parallel_result$selected, serial$selected)
})

test_that("partial checkpoint resume preserves results and never rewrites cached specs", {
  m2_parallel_host()
  withr::local_envvar(PAGE_FUTURE_BACKEND = "multicore")
  args <- m2_parallel_fixture()
  serial_dir <- withr::local_tempdir()
  resume_dir <- withr::local_tempdir()
  serial <- do.call(PAGe:::m2_subset_tune, c(args, list(
    n_cores = 1L, checkpoint_dir = serial_dir
  )))
  hash <- serial$scoring$scoring_hash
  dir.create(file.path(resume_dir, hash))
  # Include a failed spec and a successful one, leaving the rest interrupted.
  seeds <- paste0(args$grid$id[1:2], ".rds")
  seeded_paths <- file.path(resume_dir, hash, seeds)
  expect_true(all(file.copy(file.path(serial_dir, hash, seeds), seeded_paths)))
  Sys.setFileTime(seeded_paths, as.POSIXct("2000-01-01", tz = "UTC"))
  seeded_times <- file.info(seeded_paths)$mtime
  # An unreadable checkpoint must still be recomputed, as in the serial loop.
  writeLines("interrupted write", file.path(resume_dir, hash, paste0(args$grid$id[3L], ".rds")))
  resumed <- do.call(PAGe:::m2_subset_tune, c(args, list(
    n_cores = 2L, checkpoint_dir = resume_dir
  )))
  expect_identical(resumed, serial)
  expect_identical(file.info(seeded_paths)$mtime, seeded_times)
  files <- list.files(file.path(serial_dir, hash))
  expect_identical(list.files(file.path(resume_dir, hash)), files)
  for (f in files) {
    expect_identical(
      readRDS(file.path(resume_dir, hash, f)),
      readRDS(file.path(serial_dir, hash, f))
    )
  }
})

test_that("season preparation preserves rows, declarations and M1 prediction order", {
  m2_parallel_host()
  withr::local_envvar(PAGE_FUTURE_BACKEND = "multicore")
  args <- m2_parallel_fixture()
  # Exercise the real M1 season-map adapter, with a synthetic per-season model.
  # The feature/declaration preparation and all M2 fits remain real.
  preds <- args$m1_train_preds
  local_mocked_bindings(
    .m1_heldout_references = function(m1, seasons, timing_mode) {
      stats::setNames(lapply(seasons, function(s) {
        list(ref = list(), hyper = list(), excluded_season = s)
      }), seasons)
    },
    m1_walkforward_predictions = function(seasonD, ...) {
      preds[preds$season == as.character(seasonD$season[1L]), , drop = FALSE]
    },
    .package = "PAGe"
  )
  prep_args <- list(
    data = args$data, m0 = args$m0, m1 = args$m1,
    seasons = args$selection$training_seasons, detector = args$detector
  )
  serial <- do.call(PAGe:::m2_subset_make_rows, prep_args)
  old_plan <- PAGe:::.page_set_parallel_plan(2L)
  on.exit(future::plan(old_plan), add = TRUE)
  parallel_result <- do.call(PAGe:::m2_subset_make_rows, c(prep_args, list(parallel = TRUE)))
  expect_identical(parallel_result, serial)
  expect_identical(names(parallel_result$declarations), args$selection$training_seasons)
})

test_that("subset tuning restores the caller plan after errors and validates cores", {
  m2_parallel_host()
  withr::local_envvar(PAGE_FUTURE_BACKEND = "multicore")
  before <- future::plan()
  args <- m2_parallel_fixture()
  args$grid <- args$grid[FALSE, ]
  expect_error(do.call(PAGe:::m2_subset_tune, c(args, list(n_cores = 2L))), "non-empty")
  expect_identical(future::plan(), before)
  for (cores in list(0, -1, NA_real_, Inf, 1.5, c(1, 2), "2", 2^31)) {
    expect_error(do.call(PAGe:::m2_subset_tune, c(args, list(n_cores = cores))), "positive integer")
  }
})

test_that("tune_m2 forwards worker count to the subset family", {
  captured <- NULL
  local_mocked_bindings(
    .require_frozen_stage = function(...) NULL,
    .check_selection_match = function(...) NULL,
    .check_upstream_identity = function(...) NULL,
    .selected_training_data = function(data, selection) data,
    m2_subset_tune = function(..., n_cores) {
      captured <<- n_cores
      list()
    },
    .package = "PAGe"
  )
  PAGe::tune_m2(data.frame(), list(), list(), list(), data.frame(),
    family = "offset_subset_v1", n_cores = 2L
  )
  expect_identical(captured, 2L)
})
