# Stage contract tests: season selection, artifact identity, tuning gates,
# fit/freeze lifecycle, and upstream mismatch rejection.
# All tests use synthetic/minimal objects; no private data required.

# ---- helpers ----

make_canonical_data <- function(seasons = c("2017-18", "2018-19", "2019-20")) {
  rows <- lapply(seasons, function(s) {
    data.frame(
      season = s,
      weekF = 1:30,
      y = rep(5L, 30L),
      N = rep(100L, 30L),
      p = rep(0.05, 30L),
      neg = rep(95L, 30L),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

make_m0_config <- function() {
  list(cls_thr = 0.2, p_thr = 0.01, prev_thr = 0.01, n_consec = 3L,
       L = 2L, eps = 0, K_sum = 4L, p_sum_thr = 0.04, N_req = 3L,
       w_min = 13L, w_max = 30L)
}

make_m1_config <- function() {
  list(k_ref = 25L, ref_method = "fs", temperature = 0.25,
       slope_weight = 8.0, slope_window = 6L)
}

make_m2_config <- function() {
  list(
    spec_id = "v16", delta = 0L, K = 1L, k_f = 4L,
    alpha_state = 0.15, bias_alpha = 0.05, bias_beta = 0
  )
}

make_draft_m0 <- function(selection = NULL) {
  if (is.null(selection)) {
    selection <- validate_season_selection(
      make_canonical_data(),
      training_seasons = c("2017-18", "2018-19")
    )
  }
  PAGe:::.new_stage_fit(
    stage = "m0",
    selection = selection,
    config = make_m0_config(),
    payload = list(
      aligned = make_canonical_data(selection$training_seasons),
      seasons_used = selection$training_seasons,
      manual_labels = c("2017-18" = 20L, "2018-19" = 20L),
      flag_args = list(p_thresh = 0.01),
      best_params = make_m0_config()
    ),
    data_id = "test-data"
  )
}

make_frozen_m0 <- function(selection = NULL) {
  freeze_m0(make_draft_m0(selection))
}

make_draft_m1 <- function(m0 = NULL, selection = NULL) {
  if (is.null(m0)) m0 <- make_frozen_m0(selection)
  if (is.null(selection)) selection <- season_selection(m0)
  PAGe:::.new_stage_fit(
    stage = "m1",
    selection = selection,
    config = make_m1_config(),
    payload = list(
      ref = list(
        anchorWeek = 20L,
        pred_df = data.frame(newWeek = 1:52, fit = 0)
      ),
      hyper = list(scale = 1),
      aligned_train = make_canonical_data(selection$training_seasons),
      m1_params = make_m1_config(),
      seasons_used = selection$training_seasons
    ),
    upstream_ids = list(m0 = m0$artifact_id),
    data_id = "test-data"
  )
}

make_frozen_m1 <- function(m0 = NULL) {
  freeze_m1(make_draft_m1(m0))
}

make_draft_m2 <- function(m0 = NULL, m1 = NULL) {
  if (is.null(m0)) m0 <- make_frozen_m0()
  if (is.null(m1)) m1 <- make_frozen_m1(m0)
  selection <- season_selection(m0)
  PAGe:::.new_stage_fit(
    stage = "m2",
    selection = selection,
    config = make_m2_config(),
    payload = list(
      fit = structure(list(model = data.frame(
        logit_f_eff = 0, z_ema = 0, lead = factor("h1")
      )), class = "gam"),
      feature_ranges = list(),
      m1_train_preds = data.frame(),
      spec = make_m2_config(),
      training_seasons = selection$training_seasons,
      spec_version = "test"
    ),
    upstream_ids = list(m0 = m0$artifact_id, m1 = m1$artifact_id),
    data_id = "test-data"
  )
}

# ============================================================
# Season selection validation
# ============================================================

test_that("validate_season_selection returns page_season_selection", {
  dat <- make_canonical_data()
  sel <- validate_season_selection(dat, training_seasons = c("2017-18", "2018-19"))
  expect_s3_class(sel, "page_season_selection")
  expect_identical(sel$training_seasons, c("2017-18", "2018-19"))
  expect_identical(sel$exclude_seasons, character(0))
  expect_identical(sel$holdout_seasons, character(0))
  expect_identical(sel$application_seasons, character(0))
})

test_that("validate_season_selection normalizes order deterministically", {
  dat <- make_canonical_data(c("2019-20", "2017-18", "2018-19"))
  sel1 <- validate_season_selection(dat, training_seasons = c("2018-19", "2017-18"))
  sel2 <- validate_season_selection(dat, training_seasons = c("2017-18", "2018-19"))
  expect_identical(sel1$training_seasons, sel2$training_seasons)
  expect_identical(sel1$data_seasons, c("2019-20", "2017-18", "2018-19"))
})

test_that("validate_season_selection rejects invalid data season identifiers", {
  dat <- make_canonical_data()
  dat$season[1] <- NA_character_
  expect_error(
    validate_season_selection(dat, training_seasons = "2017-18"),
    "data.*season|identifier"
  )
})

test_that("validate_season_selection detects duplicates after trimming", {
  expect_error(
    validate_season_selection(
      make_canonical_data(),
      training_seasons = c("2017-18", " 2017-18 ")
    ),
    "duplicate"
  )
})

test_that("validate_season_selection rejects unknown seasons", {
  dat <- make_canonical_data()
  expect_error(
    validate_season_selection(dat, training_seasons = c("2017-18", "9999-00")),
    "not found"
  )
})

test_that("validate_season_selection rejects duplicates", {
  dat <- make_canonical_data()
  expect_error(
    validate_season_selection(dat, training_seasons = c("2017-18", "2017-18")),
    "duplicate"
  )
})

test_that("validate_season_selection rejects empty training set", {
  dat <- make_canonical_data()
  expect_error(
    validate_season_selection(dat, training_seasons = character(0)),
    "non-empty"
  )
})

test_that("validate_season_selection rejects non-character season IDs", {
  dat <- make_canonical_data()
  expect_error(
    validate_season_selection(dat, training_seasons = 42),
    "character"
  )
})

test_that("validate_season_selection rejects overlapping sets", {
  dat <- make_canonical_data()
  expect_error(
    validate_season_selection(
      dat,
      training_seasons = c("2017-18", "2018-19"),
      holdout_seasons = "2018-19"
    ),
    "disjoint"
  )
  expect_error(
    validate_season_selection(
      dat,
      training_seasons = c("2017-18", "2018-19"),
      exclude_seasons = "2017-18"
    ),
    "disjoint"
  )
})

test_that("validate_season_selection records data seasons", {
  dat <- make_canonical_data()
  sel <- validate_season_selection(dat, training_seasons = "2017-18")
  expect_setequal(sel$data_seasons, c("2017-18", "2018-19", "2019-20"))
})

test_that("validate_season_selection rejects non-data-frame input", {
  expect_error(validate_season_selection("not a df", training_seasons = "a"), "data frame")
})

# ============================================================
# season_selection accessor
# ============================================================

test_that("season_selection accessor works on stage objects", {
  m0 <- make_frozen_m0()
  sel <- season_selection(m0)
  expect_s3_class(sel, "page_season_selection")
})

test_that("season_selection errors on unsupported objects", {
  expect_error(season_selection(42), "applicable")
})

# ============================================================
# Artifact identity determinism
# ============================================================

test_that("artifact identity is deterministic and stable", {
  m0a <- make_frozen_m0()
  m0b <- make_frozen_m0()
  expect_identical(m0a$artifact_id, m0b$artifact_id)
})

test_that("artifact identity changes with different config", {
  sel <- validate_season_selection(
    make_canonical_data(), training_seasons = c("2017-18", "2018-19")
  )
  cfg1 <- make_m0_config()
  cfg2 <- make_m0_config()
  cfg2$cls_thr <- 0.5
  m0a <- make_draft_m0(sel)
  m0b <- make_draft_m0(sel)
  m0a$config <- cfg1
  m0b$config <- cfg2
  m0a <- freeze_m0(m0a)
  m0b <- freeze_m0(m0b)
  expect_false(identical(m0a$artifact_id, m0b$artifact_id))
})

# ============================================================
# M0 tuning validation gate
# ============================================================

test_that("validate_m0_tuning accepts valid tuning", {
  tuning <- structure(
    list(
      best_params = make_m0_config(),
      results = data.frame(score = 1, n_over2 = 0, max_abs = 1, n_miss = 0),
      folds = list(
        "2017-18" = list(best_params = make_m0_config()),
        "2018-19" = list(best_params = make_m0_config())
      ),
      selection = validate_season_selection(
        make_canonical_data(), training_seasons = c("2017-18", "2018-19")
      )
    ),
    class = "page_m0_tuning"
  )
  expect_silent(validate_m0_tuning(tuning))
})

test_that("validate_m0_tuning rejects zero evaluable folds", {
  tuning <- structure(
    list(best_params = make_m0_config(), results = data.frame(), folds = list()),
    class = "page_m0_tuning"
  )
  expect_error(validate_m0_tuning(tuning), "evaluable")
})

test_that("validate_m0_tuning rejects non-finite selected metric", {
  tuning <- structure(
    list(
      best_params = make_m0_config(),
      results = data.frame(score = Inf, n_over2 = 0, max_abs = 1, n_miss = 0),
      folds = list("a" = list())
    ),
    class = "page_m0_tuning"
  )
  expect_error(validate_m0_tuning(tuning), "non-finite|nonfinite")
})

test_that("validate_m0_tuning rejects missing selected config", {
  tuning <- structure(
    list(
      best_params = NULL,
      results = data.frame(score = 1),
      folds = list("a" = list())
    ),
    class = "page_m0_tuning"
  )
  expect_error(validate_m0_tuning(tuning), "best_params")
})

# ============================================================
# M1 tuning validation gate
# ============================================================

test_that("validate_m1_tuning rejects zero evaluable seasons", {
  tuning <- structure(
    list(scores = data.frame(), best = data.frame()),
    class = "page_m1_tuning"
  )
  expect_error(validate_m1_tuning(tuning), "evaluable")
})

test_that("validate_m1_tuning rejects all-NA metrics", {
  tuning <- structure(
    list(
      scores = data.frame(spec_id = "s001", mae_weibull = NA_real_),
      best = data.frame(spec_id = "s001", mae_weibull = NA_real_)
    ),
    class = "page_m1_tuning"
  )
  expect_error(validate_m1_tuning(tuning), "NA|missing")
})

test_that("validate_m1_tuning rejects non-finite selected metric", {
  tuning <- structure(
    list(
      scores = data.frame(spec_id = "s001", mae_weibull = Inf),
      best = data.frame(spec_id = "s001", mae_weibull = Inf)
    ),
    class = "page_m1_tuning"
  )
  expect_error(validate_m1_tuning(tuning), "non-finite|nonfinite")
})

test_that("validate_m1_tuning rejects missing selected config", {
  tuning <- structure(
    list(
      scores = data.frame(spec_id = "s001", mae_weibull = 1.5),
      best = data.frame()
    ),
    class = "page_m1_tuning"
  )
  expect_error(validate_m1_tuning(tuning), "best")
})

test_that("validate_m1_tuning rejects fold/selection mismatch", {
  sel <- validate_season_selection(
    make_canonical_data(), training_seasons = c("2017-18", "2018-19")
  )
  tuning <- structure(
    list(
      scores = data.frame(spec_id = "s001", mae_weibull = 1.5, n_seasons = 5L),
      best = data.frame(spec_id = "s001", mae_weibull = 1.5),
      selection = sel
    ),
    class = "page_m1_tuning"
  )
  expect_error(validate_m1_tuning(tuning), "fold|mismatch|seasons")
})

# ============================================================
# M2 tuning validation gate
# ============================================================

test_that("validate_m2_tuning rejects invalid grid identity", {
  tuning <- structure(
    list(
      summary = data.frame(spec_id = "s001", bernoulli_nll = 0.5),
      best_spec_id = "s001",
      grid = data.frame()
    ),
    class = "page_m2_tuning"
  )
  expect_error(validate_m2_tuning(tuning), "grid")
})

test_that("validate_m2_tuning rejects non-finite selected metric", {
  tuning <- structure(
    list(
      summary = data.frame(spec_id = "s001", bernoulli_nll = NaN),
      best_spec_id = "s001",
      grid = data.frame(spec_id = "s001")
    ),
    class = "page_m2_tuning"
  )
  expect_error(validate_m2_tuning(tuning), "non-finite|nonfinite")
})

test_that("validate_m2_tuning rejects absent selected specification", {
  tuning <- structure(
    list(
      summary = data.frame(spec_id = "s001", bernoulli_nll = 0.5),
      best_spec_id = NULL,
      grid = data.frame(spec_id = "s001")
    ),
    class = "page_m2_tuning"
  )
  expect_error(validate_m2_tuning(tuning), "spec")
})

# ============================================================
# Fit / freeze lifecycle
# ============================================================

test_that("fit_m0 returns draft page_m0_fit", {
  dat <- make_canonical_data()
  sel <- validate_season_selection(
    dat,
    training_seasons = c("2017-18", "2019-20"),
    holdout_seasons = "2018-19"
  )
  local_mocked_bindings(
    build_m0 = function(allD, exclude, best_params, ...) {
      expect_setequal(unique(allD$season), sel$training_seasons)
      expect_identical(exclude, character(0))
      list(
        aligned = allD,
        seasons_used = unique(allD$season),
        manual_labels = c("2017-18" = 20L),
        flag_args = list(p_thresh = 0.01),
        best_params = best_params
      )
    },
    .package = "PAGe"
  )
  m0 <- fit_m0(dat, sel, make_m0_config())
  expect_s3_class(m0, "page_m0_fit")
  expect_identical(m0$status, "draft")
  expect_identical(m0$best_params, make_m0_config())
  expect_true(is.character(m0$data_id) && nzchar(m0$data_id))
})

test_that("fit_m1 and fit_m2 retain their existing fitted payloads", {
  dat <- make_canonical_data()
  selection <- validate_season_selection(
    dat, training_seasons = c("2017-18", "2018-19")
  )
  m0 <- make_frozen_m0(selection)
  local_mocked_bindings(
    build_m1 = function(allD, m0, exclude, exclude_live, m1_params, ...) {
      expect_setequal(unique(allD$season), selection$training_seasons)
      list(
        ref = list(pred_df = data.frame(newWeek = 1:52, fit = 0)),
        hyper = list(scale = 1),
        aligned_train = allD,
        m1_params = m1_params,
        seasons_used = unique(allD$season)
      )
    },
    train_m2 = function(allD, m0, m1, best_spec, exclude, ...) {
      expect_setequal(unique(allD$season), selection$training_seasons)
      list(
        fit = "fitted-gam",
        feature_ranges = list(),
        m1_train_preds = data.frame(),
        spec = best_spec,
        training_seasons = unique(allD$season),
        spec_version = "test"
      )
    },
    .package = "PAGe"
  )

  m1 <- freeze_m1(fit_m1(dat, selection, m0, make_m1_config()))
  m2 <- fit_m2(dat, selection, m0, m1, make_m2_config())

  expect_equal(m1$hyper$scale, 1)
  expect_identical(m2$fit, "fitted-gam")
  expect_identical(m2$spec, make_m2_config())
})

test_that("governed tune APIs record selection and real result schemas", {
  dat <- make_canonical_data()
  selection <- validate_season_selection(
    dat, training_seasons = c("2017-18", "2018-19")
  )
  m0 <- make_frozen_m0(selection)
  m1 <- make_frozen_m1(m0)
  local_mocked_bindings(
    build_m0 = function(allD, exclude, manual_labels, flag_args, ...) {
      list(
        aligned = allD,
        seasons_used = unique(allD$season),
        manual_labels = manual_labels,
        flag_args = flag_args,
        best_params = make_m0_config()
      )
    },
    loso_M0v2 = function(...) {
      list(
        folds = list("2017-18" = list(), "2018-19" = list()),
        summary = list(mean_abs = 0),
        best_params = make_m0_config()
      )
    },
    tune_m1_alignment = function(...) {
      list(
        scores = data.frame(
          spec_id = "s001", mae_weibull = 1.5, n_seasons = 2L
        ),
        best = data.frame(
          spec_id = "s001", mae_weibull = 1.5,
          k_ref = 25L, slope_weight = 8
        ),
        grid = data.frame(spec_id = "s001")
      )
    },
    build_m2 = function(...) {
      list(
        best_spec = make_m2_config(),
        best_spec_id = "v16",
        summary = data.frame(
          spec_id = "v16", bernoulli_nll = 0.4, n_seasons = 2L
        ),
        scores = data.frame(
          spec_id = c("v16", "v16"),
          season = c("2017-18", "2018-19"),
          bernoulli_nll = c(0.4, 0.4)
        ),
        cv_results = list(),
        grid = data.frame(spec_id = "v16")
      )
    },
    .package = "PAGe"
  )

  m0_tuning <- tune_m0(
    dat, selection = selection, n_cores = 1L, verbose = FALSE
  )
  m1_tuning <- tune_m1(
    dat, m0 = m0, selection = selection,
    n_cores = 1L, verbose = FALSE
  )
  m2_tuning <- tune_m2(
    dat, selection, m0, m1, grid = data.frame(spec_id = "v16"),
    n_cores = 1L, verbose = FALSE
  )

  expect_silent(validate_m0_tuning(m0_tuning))
  expect_silent(validate_m1_tuning(m1_tuning))
  expect_silent(validate_m2_tuning(m2_tuning))
  expect_identical(season_selection(m2_tuning), selection)
})

test_that("validate_m2_tuning rejects incomplete governed folds", {
  selection <- validate_season_selection(
    make_canonical_data(),
    training_seasons = c("2017-18", "2018-19")
  )
  tuning <- structure(
    list(
      summary = data.frame(
        spec_id = "s001", bernoulli_nll = 0.5, n_seasons = 2L
      ),
      scores = data.frame(
        spec_id = "s001", season = "2017-18", bernoulli_nll = 0.5
      ),
      best_spec_id = "s001",
      best_spec = list(spec_id = "s001"),
      grid = data.frame(spec_id = "s001"),
      selection = selection
    ),
    class = c("page_m2_tuning", "list")
  )
  expect_error(validate_m2_tuning(tuning), "incomplete|fold")
})

test_that("freeze_m0 returns frozen page_m0_fit", {
  m0 <- make_frozen_m0()
  expect_s3_class(m0, "page_m0_fit")
  expect_identical(m0$status, "frozen")
})

test_that("freeze_m0 is idempotent on frozen objects", {
  m0 <- make_frozen_m0()
  m0b <- freeze_m0(m0)
  expect_identical(m0$artifact_id, m0b$artifact_id)
})

test_that("fit_m1 requires frozen M0", {
  sel <- validate_season_selection(
    make_canonical_data(), training_seasons = c("2017-18", "2018-19")
  )
  draft_m0 <- make_draft_m0(sel)
  expect_error(
    fit_m1(make_canonical_data(), sel, draft_m0, make_m1_config()),
    "frozen"
  )
})

test_that("fit_m1 rejects mismatched upstream selection", {
  sel_a <- validate_season_selection(
    make_canonical_data(), training_seasons = c("2017-18", "2018-19")
  )
  sel_b <- validate_season_selection(
    make_canonical_data(), training_seasons = c("2017-18", "2019-20")
  )
  m0 <- make_frozen_m0(sel_a)
  expect_error(
    fit_m1(make_canonical_data(), sel_b, m0, make_m1_config()),
    "selection|mismatch"
  )
})

test_that("fit_m2 requires frozen M0 and M1", {
  sel <- validate_season_selection(
    make_canonical_data(), training_seasons = c("2017-18", "2018-19")
  )
  draft_m0 <- make_draft_m0(sel)
  m1 <- make_frozen_m1()
  expect_error(
    fit_m2(make_canonical_data(), sel, draft_m0, m1, make_m2_config()),
    "frozen"
  )
})

test_that("fit_m2 rejects unfrozen M1", {
  m0 <- make_frozen_m0()
  sel <- season_selection(m0)
  draft_m1 <- make_draft_m1(m0)
  expect_error(
    fit_m2(make_canonical_data(), sel, m0, draft_m1, make_m2_config()),
    "frozen"
  )
})

test_that("fit_m2 rejects mismatched M1 upstream identity", {
  sel_a <- validate_season_selection(
    make_canonical_data(), training_seasons = c("2017-18", "2018-19")
  )
  sel_b <- validate_season_selection(
    make_canonical_data(), training_seasons = c("2017-18", "2019-20")
  )
  m0_a <- make_frozen_m0(sel_a)
  m0_b <- make_frozen_m0(sel_b)
  m1_b <- make_frozen_m1(m0_b)
  expect_error(
    fit_m2(make_canonical_data(), sel_a, m0_a, m1_b, make_m2_config()),
    "mismatch|identity"
  )
})

# ============================================================
# Freeze with tuning validation
# ============================================================

test_that("freeze_m0 with invalid tuning rejects", {
  draft <- make_draft_m0()
  bad_tuning <- structure(
    list(best_params = NULL, results = data.frame(), folds = list()),
    class = "page_m0_tuning"
  )
  expect_error(freeze_m0(draft, tuning = bad_tuning), "best_params|evaluable")
})

test_that("freeze_m1 with valid tuning succeeds", {
  m0 <- make_frozen_m0()
  draft <- make_draft_m1(m0)
  sel <- season_selection(m0)
  good_tuning <- structure(
    list(
      scores = data.frame(spec_id = "s001", mae_weibull = 1.5, n_seasons = 2L),
      best = data.frame(
        spec_id = "s001", mae_weibull = 1.5,
        k_ref = 25L, ref_method = "fs", temperature = 0.25,
        slope_weight = 8, slope_window = 6L
      ),
      selection = sel
    ),
    class = c("page_m1_tuning", "list")
  )
  frozen <- freeze_m1(draft, tuning = good_tuning)
  expect_identical(frozen$status, "frozen")
})

test_that("freeze rejects tuning from a different selection", {
  draft <- make_draft_m1()
  other_selection <- validate_season_selection(
    make_canonical_data(),
    training_seasons = c("2017-18", "2019-20")
  )
  unrelated_tuning <- structure(
    list(
      scores = data.frame(
        spec_id = "s001", mae_weibull = 1.5, n_seasons = 2L
      ),
      best = data.frame(
        spec_id = "s001", mae_weibull = 1.5,
        k_ref = 25L, ref_method = "fs", temperature = 0.25,
        slope_weight = 8, slope_window = 6L
      ),
      selection = other_selection
    ),
    class = c("page_m1_tuning", "list")
  )
  expect_error(freeze_m1(draft, unrelated_tuning), "selection.*mismatch")
})

test_that("frozen-stage guard detects artifact tampering", {
  frozen <- make_frozen_m0()
  frozen$config$cls_thr <- 0.99
  expect_error(
    PAGe:::.require_frozen_stage(frozen, "m0"),
    "identity|tamper|integrity"
  )
})

# ============================================================
# .require_frozen_stage guard
# ============================================================

test_that(".require_frozen_stage rejects draft artifacts", {
  draft <- make_draft_m0()
  expect_error(
    PAGe:::.require_frozen_stage(draft, "m0"),
    "frozen"
  )
})

test_that(".require_frozen_stage accepts frozen artifacts", {
  frozen <- make_frozen_m0()
  expect_silent(PAGe:::.require_frozen_stage(frozen, "m0"))
})

test_that(".require_frozen_stage rejects non-stage objects", {
  expect_error(
    PAGe:::.require_frozen_stage(list(), "m0"),
    "frozen|stage|governed"
  )
})

# ============================================================
# Integration: kit assembly rejects unfrozen components
# ============================================================

test_that("assemble_kit with governed artifacts rejects unfrozen M0", {
  sel <- validate_season_selection(
    make_canonical_data(), training_seasons = c("2017-18", "2018-19")
  )
  draft_m0 <- make_draft_m0(sel)
  m1 <- list(ref = list(anchorWeek = 20L, pred_df = data.frame(newWeek = 1:52, fit = 0)),
             hyper = list(), aligned_train = make_canonical_data(),
             m1_params = make_m1_config(), seasons_used = c("2017-18", "2018-19"))
  m2_model <- list(fit = structure(list(model = data.frame(
    logit_f_eff = 0, z_ema = 0, lead = factor("h1")
  )), class = "gam"),
  spec = make_m2_config(), feature_ranges = list(),
  m1_train_preds = data.frame(), training_seasons = "2017-18")

  expect_error(
    assemble_kit(draft_m0, m1, m2_model),
    "frozen"
  )
})

test_that("assemble_kit accepts a complete frozen governed chain", {
  m0 <- make_frozen_m0()
  m1 <- make_frozen_m1(m0)
  m2 <- freeze_m2(make_draft_m2(m0, m1))

  kit <- assemble_kit(m0, m1, m2)

  expect_true(is.list(kit))
  expect_identical(kit$m0_params, m0$best_params)
  expect_s3_class(kit$season_selection, "page_season_selection")
  expect_named(kit$stage_artifact_ids, c("m0", "m1", "m2"))
  expect_identical(season_selection(kit), m0$selection)
  expect_silent(validate_page_kit(kit))

  kit$stage_artifact_ids[["m1"]] <- "tampered"
  expect_error(validate_page_kit(kit), "governance|identity|integrity")
})

# ============================================================
# Legacy compatibility: existing kit path still works
# ============================================================

test_that("legacy assemble_kit with plain lists still works", {
  m0_legacy <- list(
    best_params = make_m0_config(),
    manual_labels = c("2017-18" = 20L),
    flag_args = list(p_thresh = 0.01)
  )
  m1_legacy <- list(
    ref = list(anchorWeek = 20L, pred_df = data.frame(newWeek = 1:52, fit = 0)),
    hyper = list(scale = 1),
    aligned_train = make_canonical_data(),
    m1_params = list(
      temperature = 0.25, rise_weight = 1, trough_weight = 0.1,
      peak_decay = 0.3, slope_weight = 8, slope_window = 6L,
      dynamic_temp = FALSE, dynamic_temp_pivot = 10L
    ),
    seasons_used = c("2017-18", "2018-19")
  )
  m2_legacy <- list(
    fit = structure(list(model = data.frame(
      logit_f_eff = 0, z_ema = 0, lead = factor("h1")
    )), class = "gam"),
    spec = list(k_f = 4L, k_n = 0L, k_de = 0L, k_r = 0L, k_sp = 0L,
                bias_alpha = 0.05, bias_beta = 0),
    feature_ranges = list(),
    m1_train_preds = data.frame(),
    training_seasons = c("2017-18", "2018-19")
  )
  kit <- assemble_kit(m0_legacy, m1_legacy, m2_legacy)
  expect_true(is.list(kit))
  expect_true("m0_params" %in% names(kit))
})
