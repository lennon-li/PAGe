test_that("old ORVT layout aggregates PHUs and maps dates to PAGe weeks", {
  path <- testthat::test_path("fixtures", "orvt_old.txt")
  result <- PAGe::getCurrentD(path, season = "2025-26", include_predecessor = FALSE)

  expect_identical(attr(result, "pho_layout"), "surveillance_period")
  expect_equal(result$week, c(27L, 28L, 53L, 1L))
  expect_equal(result$weekF, c(1L, 2L, 27L, 28L))
  expect_equal(result$N, c(50, 10, 40, 50))
  expect_equal(result$y, c(5, 1, 4, 5))
  expect_equal(result$source_n_phu[1L], 2L)
  expect_equal(result$pho_season[1L], "2025-26;mislabel-1")
})

test_that("the exact Ontario row supplies the provincial value", {
  path <- testthat::test_path("fixtures", "orvt_ontario_present.txt")
  result <- PAGe::getCurrentD(path, season = "2025-26", include_predecessor = FALSE)

  expect_equal(result$N, c(50, 100))
  expect_equal(result$y, c(5, 10))
  expect_equal(result$phu_N, c(50, 100))
  expect_equal(result$phu_y, c(5, 10))
  expect_true(all(result$source_has_ontario))
  expect_true(all(result$source_ontario_consistent))
  expect_identical(unique(result$provincial_value_source), "Ontario")
})

test_that("missing Ontario rows fall back to the PHU sum with provenance", {
  path <- testthat::test_path("fixtures", "orvt_no_ontario.txt")
  result <- NULL
  expect_warning(
    result <- PAGe::getCurrentD(path, season = "2025-26", include_predecessor = FALSE),
    "no exact `Ontario` row"
  )

  expect_equal(result$N, 50)
  expect_equal(result$y, 5)
  expect_false(result$source_has_ontario)
  expect_true(is.na(result$source_ontario_consistent))
  expect_identical(result$provincial_value_source, "PHU sum")
})

test_that("Eastern Ontario Health Unit remains a PHU, not the provincial row", {
  path <- testthat::test_path("fixtures", "orvt_ontario_substring.txt")
  result <- PAGe::getCurrentD(path, season = "2025-26", include_predecessor = FALSE)

  expect_equal(result$N, 20)
  expect_equal(result$y, 2)
  expect_equal(result$phu_N, 20)
  expect_equal(result$source_n_phu, 1L)
  expect_identical(result$provincial_value_source, "Ontario")
})

test_that("inconsistent Ontario totals fail closed", {
  path <- testthat::test_path("fixtures", "orvt_ontario_present.txt")
  bad <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
  bad$`Total # of tests`[bad$`Public health unit` == "Ontario"] <- 51
  bad_path <- tempfile(fileext = ".csv")
  on.exit(unlink(bad_path), add = TRUE)
  utils::write.csv(bad, bad_path, row.names = FALSE)

  expect_error(
    PAGe::getCurrentD(bad_path, season = "2025-26", include_predecessor = FALSE),
    "Ontario.*disagree"
  )
})

test_that("new ORVT layout handles non-ISO dates and the 53-week calendar", {
  path <- testthat::test_path("fixtures", "orvt_new.txt")
  result <- PAGe::getCurrentD(path, season = "2025-26", include_predecessor = FALSE)

  expect_identical(attr(result, "pho_layout"), "respiratory_season")
  expect_equal(attr(result, "n_weeks"), 4L)
  expect_equal(result$weekF, c(1L, 9L, 27L, 28L))
  expect_true(all(c("date", "week_start_date", "week_end_date", "pho_season") %in% names(result)))
  expect_equal(as.character(result$week_start_date[1L]), "2025-06-29")
})

test_that("predecessor selection and provenance are explicit", {
  path <- testthat::test_path("fixtures", "orvt_new.txt")
  only_current <- PAGe::getCurrentD(path, season = "2026-27", include_predecessor = FALSE)
  with_previous <- PAGe::getCurrentD(path, season = "2026-27", include_predecessor = TRUE)

  expect_setequal(unique(only_current$season), "2026-27")
  expect_setequal(unique(with_previous$season), c("2025-26", "2026-27"))
  expect_true(is.character(attr(with_previous, "sha256")))
  expect_true(is.character(attr(with_previous, "retrieved_utc")))
  expect_true(is.character(attr(with_previous, "last_week_end_date")))
  expect_identical(attr(with_previous, "source_url_or_path"), path)
})

test_that("conflicting PHU-week duplicates fail closed", {
  path <- testthat::test_path("fixtures", "orvt_new.txt")
  bad <- readLines(path)
  bad <- c(bad, sub(",6,60,10$", ",8,60,13.3", bad[2L]))
  bad_path <- tempfile(fileext = ".csv")
  on.exit(unlink(bad_path), add = TRUE)
  writeLines(bad, bad_path)
  expect_error(
    PAGe::getCurrentD(bad_path, season = "2025-26", include_predecessor = FALSE),
    "Conflicting duplicate"
  )
})

test_that("default URL resolution falls back to the second candidate", {
  path <- testthat::test_path("fixtures", "orvt_new.txt")
  bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  withr::local_options(PAGe.orvt_reader = function(url) {
    if (grepl("2026-27_2027-28", url, fixed = TRUE)) bytes else stop("not readable")
  })
  result <- PAGe::getCurrentD(
    season = "2026-27", base_url = "https://example.test/orvt/",
    include_predecessor = FALSE
  )
  expect_match(attr(result, "source_url_or_path"), "ORVT_Lab_Testing_Data_2026-27_2027-28\\.csv$")
})

test_that("download cache stores the raw bytes under timestamp and digest", {
  path <- testthat::test_path("fixtures", "orvt_new.txt")
  bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  cache <- tempfile("orvt-cache-")
  withr::local_options(PAGe.orvt_reader = function(url) bytes)
  PAGe::getCurrentD(
    data = "https://example.test/orvt.csv", season = "2025-26",
    include_predecessor = FALSE, cache_dir = cache
  )
  cached <- list.files(cache, pattern = "^orvt_.*_[0-9a-f]{64}\\.csv$")
  expect_length(cached, 1L)
  expect_identical(readBin(file.path(cache, cached), "raw", file.info(file.path(cache, cached))$size), bytes)
})
