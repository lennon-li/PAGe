# Regression coverage for stable governed M1 identities with real reference
# functions. This deliberately exercises estimateRef(), not a mocked payload.

make_real_m1_identity_fixture <- function() {
  raw <- simulate_flu_seasons(S = 3L, weeks = 1:52, seed = 20260909)
  raw$season <- paste0("syn-", as.integer(raw$season))
  aligned <- transform(
    raw,
    fit = y / (y + neg),
    phase = 1L,
    iWeek = 1L,
    weekF = newWeek
  )
  aligned$newWeek <- as.integer(aligned$newWeek)
  data <- data.frame(
    season = aligned$season,
    weekF = aligned$weekF,
    y = aligned$y,
    N = aligned$y + aligned$neg,
    p = aligned$y / (aligned$y + aligned$neg),
    neg = aligned$neg,
    stringsAsFactors = FALSE
  )
  selection <- validate_season_selection(
    data,
    training_seasons = sort(unique(data$season))
  )
  m0 <- PAGe:::.new_stage_fit(
    stage = "m0",
    selection = selection,
    config = list(cls_thr = 0.2),
    payload = list(
      aligned = aligned,
      seasons_used = selection$training_seasons,
      best_params = list(cls_thr = 0.2)
    ),
    data_id = PAGe:::.stage_training_data_id(data)
  )
  m0 <- freeze_m0(m0)
  m1_config <- list(
    k_ref = 6L,
    ref_method = "fs",
    temperature = 0.25,
    slope_weight = 8,
    slope_window = 6L
  )
  m1 <- PAGe:::.new_stage_fit(
    stage = "m1",
    selection = selection,
    config = m1_config,
    payload = list(
      ref = estimateRef(alignedD = aligned, k = 6L, method = "fs"),
      hyper = list(scale = 1),
      aligned_train = aligned,
      m1_params = m1_config,
      seasons_used = selection$training_seasons
    ),
    upstream_ids = list(m0 = m0$artifact_id),
    data_id = PAGe:::.stage_training_data_id(data)
  )
  freeze_m1(m1)
}

test_that("real M1 reference identity survives use and serialization", {
  m1 <- make_real_m1_identity_fixture()
  artifact_id <- m1$artifact_id
  u <- c(10, 20, 30)

  expect_match(artifact_id, "^m1_[0-9a-f]{64}$")
  expect_silent(PAGe:::.require_frozen_stage(m1, "m1"))
  expect_true(all(is.finite(m1$ref$g_ref_fun(u))))
  expect_true(all(is.finite(m1$ref$g_ref_safe(u))))
  predictions <- m1$ref$g_ref_mu_se(u)
  expect_true(all(is.finite(predictions$mu)))
  expect_true(all(is.finite(predictions$se)))
  expect_identical(m1$artifact_id, artifact_id)
  expect_silent(PAGe:::.require_frozen_stage(m1, "m1"))

  path <- tempfile(fileext = ".rds")
  saveRDS(m1, path)
  restored <- readRDS(path)
  expect_identical(restored$artifact_id, artifact_id)
  expect_equal(restored$ref$g_ref_mu_se(u), predictions)
  expect_silent(PAGe:::.require_frozen_stage(restored, "m1"))
})

test_that("real reference mean/SE factories predict across M1 methods", {
  raw <- simulate_flu_seasons(S = 3L, weeks = 1:52, seed = 20260909)
  raw$season <- paste0("syn-", as.integer(raw$season))
  aligned <- transform(
    raw,
    fit = y / (y + neg),
    phase = 1L,
    iWeek = 1L,
    weekF = newWeek
  )
  aligned$newWeek <- as.integer(aligned$newWeek)
  u <- c(10, 20, 30)

  for (method in c("fs", "gaussian_logit", "gaussian_logit_fs")) {
    ref <- estimateRef(alignedD = aligned, k = 6L, method = method)
    before <- digest::digest(ref, algo = "sha256")
    predictions <- ref$g_ref_mu_se(u)
    expect_true(all(is.finite(predictions$mu)), info = method)
    expect_true(all(is.finite(predictions$se)), info = method)
    expect_identical(digest::digest(ref, algo = "sha256"), before)
  }
})

test_that("stage identity retains captured closure values and functions", {
  selection <- structure(
    list(
      training_seasons = "syn-1",
      exclude_seasons = character(),
      holdout_seasons = character(),
      application_seasons = character(),
      data_seasons = "syn-1"
    ),
    class = "page_season_selection"
  )
  factory_env <- new.env(parent = baseenv())
  factory_env$make_closure <- evalq(
    function(offset) {
      helper <- function(x) x + offset
      function(x) helper(x)
    },
    envir = factory_env
  )
  make_closure <- factory_env$make_closure
  closure <- make_closure(1)
  identity <- function(x) {
    PAGe:::.stage_artifact_id(
      stage = "m1", selection = selection, config = list(k_ref = 6L),
      data_id = "synthetic", payload = list(reference = x)
    )
  }

  initial <- identity(closure)
  path <- tempfile(fileext = ".rds")
  saveRDS(closure, path)
  expect_identical(identity(readRDS(path)), initial)

  closure_env <- environment(closure)
  assign("offset", 2, envir = closure_env)
  expect_false(identical(identity(closure), initial))

  closure <- make_closure(1)
  initial <- identity(closure)
  assign("helper", function(x) x + 2, envir = environment(closure))
  expect_false(identical(identity(closure), initial))
})

test_that("stage identity hashes ordinary named captured environments", {
  selection <- structure(
    list(
      training_seasons = "syn-1",
      exclude_seasons = character(),
      holdout_seasons = character(),
      application_seasons = character(),
      data_seasons = "syn-1"
    ),
    class = "page_season_selection"
  )
  captured <- new.env(parent = baseenv())
  attr(captured, "name") <- "captured_model"
  captured$offset <- 1
  reference <- evalq(function(x) x + offset, envir = captured)
  identity <- function() {
    PAGe:::.stage_artifact_id(
      stage = "m1", selection = selection, config = list(k_ref = 6L),
      data_id = "synthetic", payload = list(reference = reference)
    )
  }

  initial <- identity()
  assign("offset", 2, envir = captured)
  expect_false(identical(identity(), initial))
})

test_that("M0 and M2 retain their raw-payload identity format", {
  selection <- structure(
    list(
      training_seasons = "syn-1",
      exclude_seasons = character(),
      holdout_seasons = character(),
      application_seasons = character(),
      data_seasons = "syn-1"
    ),
    class = "page_season_selection"
  )
  payload <- list(value = 1)
  legacy_id <- function(stage) {
    paste0(stage, "_", digest::digest(list(
      stage = stage,
      selection = unclass(selection),
      config = list(example = TRUE),
      upstream = NULL,
      data_id = "synthetic",
      fitted_payload = payload
    ), algo = "sha256"))
  }

  for (stage in c("m0", "m2")) {
    expect_identical(
      PAGe:::.stage_artifact_id(
        stage = stage, selection = selection, config = list(example = TRUE),
        data_id = "synthetic", payload = payload
      ),
      legacy_id(stage)
    )
  }
})

test_that("legacy M1 identity artifacts fail closed without resealing", {
  m1 <- make_real_m1_identity_fixture()
  legacy <- m1
  legacy$identity_format <- NULL
  original_id <- legacy$artifact_id

  expect_error(
    PAGe:::.require_frozen_stage(legacy, "m1"),
    "legacy raw|superseded semantic|not verifiable"
  )
  expect_identical(legacy$artifact_id, original_id)
})

test_that("M1 identity still detects reference, fit, and data tampering", {
  m1 <- make_real_m1_identity_fixture()

  reference_tampered <- m1
  reference_tampered$ref$g_ref_fun <- function(u) rep(0, length(u))
  expect_error(
    PAGe:::.require_frozen_stage(reference_tampered, "m1"),
    "identity|tamper|integrity"
  )

  fit_tampered <- m1
  fit_tampered$ref$mod2$gam$coefficients[1L] <-
    fit_tampered$ref$mod2$gam$coefficients[1L] + 0.01
  expect_error(
    PAGe:::.require_frozen_stage(fit_tampered, "m1"),
    "identity|tamper|integrity"
  )

  data_tampered <- m1
  data_tampered$ref$dat$fit_ref[1L] <-
    data_tampered$ref$dat$fit_ref[1L] + 0.01
  expect_error(
    PAGe:::.require_frozen_stage(data_tampered, "m1"),
    "identity|tamper|integrity"
  )
})
