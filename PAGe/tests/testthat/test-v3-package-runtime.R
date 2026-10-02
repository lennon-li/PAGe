.v3_fixture <- function(name) {
  p <- system.file("extdata", "v3-week12", name, package = "PAGe")
  if (nzchar(p) && file.exists(p)) return(p)
  candidates <- c(
    file.path("PAGe", "inst", "extdata", "v3-week12", name),
    file.path("inst", "extdata", "v3-week12", name),
    file.path("..", "..", "inst", "extdata", "v3-week12", name)
  )
  hit <- candidates[file.exists(candidates)]
  if (!length(hit)) stop("v3 test fixture not found: ", name)
  hit[[1L]]
}

.v3_model_dir_test <- function() {
  p <- system.file("models", "v3-week12", package = "PAGe")
  if (nzchar(p) && dir.exists(p)) return(p)
  candidates <- c(
    file.path("PAGe", "inst", "models", "v3-week12"),
    file.path("inst", "models", "v3-week12"),
    file.path("..", "..", "inst", "models", "v3-week12")
  )
  hit <- candidates[dir.exists(candidates)]
  if (!length(hit)) stop("v3 model bundle not found")
  hit[[1L]]
}

.v3_expected <- function(name) jsonlite::fromJSON(.v3_fixture(name), simplifyVector = FALSE)

.v3_internal <- function(name) {
  if (exists(name, mode = "function", inherits = TRUE)) return(get(name, mode = "function", inherits = TRUE))
  getFromNamespace(name, "PAGe")
}

.v3_internal_object <- function(name) {
  if (exists(name, inherits = TRUE)) return(get(name, inherits = TRUE))
  getFromNamespace(name, "PAGe")
}

.v3_clear_cache <- function() {
  cache <- .v3_internal_object(".page_v3_cache")
  if (exists("models", envir = cache, inherits = FALSE)) rm("models", envir = cache)
}

test_that("bundled v3 runtime projections bind exact source and runtime identities", {
  .v3_clear_cache()
  models <- .v3_internal(".page_v3_validate_bundle")(.v3_model_dir_test())
  expect_identical(attr(models, "release_id"), "5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b")
  manifest <- attr(models, "manifest")
  expect_equal(nrow(manifest), 5L)
  source_expected <- c(
    m0_a = "9598486e78eedd8e322da77b0d990db60ca07224c3c6ea6ac61cea9cc6fb611d",
    m1_a = "cfeb370305c5b81d66d7eafd7e45ee7e946836ba9f841854f2ec068cf3d43b09",
    m2_a = "1efe590c5222f6061af7bef46b0ea19657ec37e070549898569a62ccd4ac65bb",
    m1_b = "a98629fc313388487e9b3471ae9934cfae8cbc35cdb707ba371f680162691694",
    m2_b = "cae89144c461636662380c19880bf6c5780ce76347edf6b3e30617a614af7226"
  )
  runtime_expected <- c(
    m0_a = source_expected[["m0_a"]],
    m1_a = source_expected[["m1_a"]],
    m2_a = "718a7b67f0c264ff5cdad5989cfe198052bcf997af06b5acabf83b35c299aa4a",
    m1_b = source_expected[["m1_b"]],
    m2_b = "a56333f64dcf30bffcfbfe3c03dc66a5c3507b10d7b404114308a301d977d4e6"
  )
  expect_equal(stats::setNames(manifest$source_sha256, manifest$model)[names(source_expected)], source_expected)
  expect_equal(stats::setNames(manifest$runtime_sha256, manifest$model)[names(runtime_expected)], runtime_expected)
  expect_identical(manifest$projection[manifest$model == "m2_a"], "runtime_projection_v1")
  expect_identical(manifest$projection[manifest$model == "m2_b"], "runtime_projection_v1")
})

test_that("packaged M2 runtime projections contain no raw target count frames", {
  models <- page_models()
  expect_s3_class(models$m2_a, "page_v3_m2a_runtime")
  expect_s3_class(models$m2_b, "page_v3_m2b_runtime")
  expect_false("fit" %in% names(models$m2_a))
  expect_false("model" %in% names(models$m2_b$state))
  expect_false(any(c("y_target", "N_target") %in% names(models$m2_b$shape$grid)))
  expect_identical(names(models$m2_b$shape$grid), c("season", "type", "tau", "p_norm"))
})


test_that("v3 package runtime has no repo source dependency", {
  bodies <- c(
    deparse(body(page_forecast)),
    deparse(body(.v3_internal(".page_v3_m2b_forecast"))),
    deparse(body(.v3_internal(".page_v3_validate_bundle")))
  )
  expect_false(any(grepl("source\\(|scripts/|artifacts/", bodies)))
})

test_that("pre-weekF12 returns a governed not-issued result", {
  panel <- read.csv(.v3_fixture("ignition-panel.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  out <- page_forecast(panel[panel$weekF <= 11, ], season = "2026-27")
  expect_s3_class(out, "page_forecast_result")
  expect_false(out$issued)
  expect_identical(out$origin_weekF, 11L)
  expect_true(all(out$forecasts$route == "not_issued"))
  expect_true(all(is.na(out$forecasts$forecast)))
  expect_false(out$monitoring$A$m0$eligible)
  expect_false(out$production_eligible)
})

test_that("weekF12 ignition result equals retained audited v4 output", {
  .v3_clear_cache()
  panel <- read.csv(.v3_fixture("ignition-panel.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  out <- page_forecast(panel, season = "2026-27", origin_weekF = 12)
  expected <- .v3_expected("ignition-expected.json")
  expect_true(out$issued)
  expect_equal(out$forecasts$forecast_pct, vapply(expected$forecasts, `[[`, numeric(1), "v3_pct"), tolerance = 1e-12)
  expect_equal(out$forecasts$route, vapply(expected$forecasts, `[[`, character(1), "v3_route"))
  expect_true(out$monitoring$A$m0$ignited)
  expect_equal(out$monitoring$A$m0$ignition_weekF, expected$monitoring$A$m0$ignition_weekF, tolerance = 1e-12)
  expect_equal(out$monitoring$A$m1$peak_mean_weekF, expected$monitoring$A$m1$peak_mean_weekF, tolerance = 1e-12)
  expect_equal(out$monitoring$A$m1$peak_q05_weekF, expected$monitoring$A$m1$peak_q05_weekF, tolerance = 1e-12)
  expect_equal(out$monitoring$A$m1$peak_q95_weekF, expected$monitoring$A$m1$peak_q95_weekF, tolerance = 1e-12)
  expect_equal(out$monitoring$A$m1$prob_peak_passed, expected$monitoring$A$m1$prob_peak_passed, tolerance = 1e-12)
  expect_identical(out$monitoring$B$m1$available, expected$monitoring$B$m1$available)
  expect_identical(out$monitoring$B$m1$route, expected$monitoring$B$m1$route)
})

test_that("weekF12 no-ignition result equals retained audited v4 output", {
  panel <- read.csv(.v3_fixture("no-ignition-panel.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  out <- page_forecast(panel, season = "2026-27", origin_weekF = 12)
  expected <- .v3_expected("no-ignition-expected.json")
  expect_true(out$issued)
  expect_equal(out$forecasts$forecast_pct, vapply(expected$forecasts, `[[`, numeric(1), "v3_pct"), tolerance = 1e-12)
  expect_false(out$monitoring$A$m0$ignited)
  expect_false(out$monitoring$A$m1$available)
  expect_identical(out$monitoring$A$m1$state, "inactive_pre_ignition")
})

test_that("OLIS and typed panel inputs are numerically identical", {
  panel <- read.csv(.v3_fixture("ignition-panel.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  from_panel <- page_forecast(panel, season = "2026-27", origin_weekF = 12)
  from_olis <- page_forecast(.v3_fixture("ignition.RData"), season = "2026-27", origin_weekF = 12)
  expect_equal(from_olis$forecasts$forecast, from_panel$forecasts$forecast, tolerance = 1e-14)
  expect_equal(from_olis$monitoring$A$m1$peak_mean_weekF, from_panel$monitoring$A$m1$peak_mean_weekF, tolerance = 1e-14)
  expect_identical(from_olis$provenance$input_kind, "olis_rdata")
})

test_that("strict typed panels fail on positivity/count disagreement", {
  panel <- read.csv(.v3_fixture("ignition-panel.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  panel$p_A[[12L]] <- panel$p_A[[12L]] + 0.01
  expect_error(page_forecast(panel, season = "2026-27"), "p_A disagrees")
})

test_that("tampered bundled model bytes fail closed", {
  src <- .v3_model_dir_test()
  tmp <- tempfile("page-v3-bundle-")
  dir.create(tmp)
  files <- list.files(src, full.names = TRUE)
  file.copy(files, tmp)
  cat("tamper", file = file.path(tmp, "m0_a.rds"), append = TRUE)
  expect_error(.v3_internal(".page_v3_validate_bundle")(tmp), "hash mismatch")
})

test_that("v3 print method reports ignition peak and routes", {
  panel <- read.csv(.v3_fixture("ignition-panel.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  out <- page_forecast(panel, season = "2026-27", origin_weekF = 12)
  expect_output(print(out), "A ignition: yes")
  expect_output(print(out), "A peak: weekF")
  expect_output(print(out), "exact_B1_fallback")
})


test_that("package-native active B posterior-C2 equals governed v5 helper fixture", {
  input <- read.csv(.v3_fixture("b-active-input.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  expected <- read.csv(.v3_fixture("b-active-expected.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  models <- page_models()
  runtime <- if (exists(".page_v3_m2b_forecast", inherits = TRUE)) {
    get(".page_v3_m2b_forecast", inherits = TRUE)
  } else {
    getFromNamespace(".page_v3_m2b_forecast", "PAGe")
  }
  got <- runtime(models$m2_b, models$m1_b, input, 45L, 2L)
  fields_num <- c("forecast","B1_forecast","activity_week","prob_peak_passed","posterior_mean_peak","supported_mass","lower_bound_mass")
  for (nm in fields_num) expect_equal(got[[nm]], expected[[nm]], tolerance = 1e-14)
  fields_exact <- c("timing_available","timing_reason","lower_bound_saturated","m1_b_version","m2_b_version","m2_b_artifact_id")
  for (nm in fields_exact) expect_identical(got[[nm]], expected[[nm]])
  expect_true(got$timing_available[[1L]])
  expect_identical(got$route[[1L]], "posterior_C2")
})


test_that("OLIS rows outside requested season do not alter current-season runtime", {
  src <- .v3_fixture("ignition.RData")
  env <- new.env(parent = emptyenv())
  load(src, envir = env)
  extra <- data.frame(date = as.Date("2025-01-01"), pos = 0, tests = 1000)
  env$r$fluA <- rbind(env$r$fluA, extra)
  env$r$fluB <- rbind(env$r$fluB, extra)
  tmp <- tempfile(fileext = ".RData")
  r <- env$r
  save(r, file = tmp)
  base <- page_forecast(src, season = "2026-27", origin_weekF = 12)
  got <- page_forecast(tmp, season = "2026-27", origin_weekF = 12)
  expect_equal(got$forecasts$forecast, base$forecasts$forecast, tolerance = 1e-14)
  expect_equal(got$monitoring$A$m1$peak_mean_weekF, base$monitoring$A$m1$peak_mean_weekF, tolerance = 1e-14)
})


test_that("OLIS input fails closed on invalid counts", {
  src <- .v3_fixture("ignition.RData")
  env <- new.env(parent = emptyenv())
  load(src, envir = env)
  env$r$fluA$pos[[1L]] <- env$r$fluA$tests[[1L]] + 1
  tmp <- tempfile(fileext = ".RData")
  r <- env$r
  save(r, file = tmp)
  expect_error(page_forecast(tmp, season = "2026-27", origin_weekF = 12), "invalid positive/test counts")
})
