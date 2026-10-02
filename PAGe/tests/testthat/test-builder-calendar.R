test_that("ORVT builder revision checks are keyed by dates", {
  builder <- new.env(parent = globalenv())
  builder_path <- testthat::test_path(
    "..", "..", "..", "scripts", "build_flu_hist_orvt.R"
  )
  sys.source(builder_path, envir = builder)

  dates <- seq(as.Date("2025-01-05"), by = "7 days", length.out = 52L)
  existing <- data.frame(
    pho_season = rep("2024-25", 52L),
    week_start_date = as.character(dates),
    pos_flua = rep(10, 52L), test_flu = rep(100, 52L)
  )
  source_rows <- data.frame(
    week_start_date = as.character(dates),
    y = c(rep(10, 40L), rep(11, 12L)),
    N = rep(100, 52L)
  )

  result <- builder$compare_revisions_by_date(existing, source_rows, "2024-25")
  expect_identical(result$status, "ok")
  expect_identical(result$n_settled, 40L)
  expect_identical(result$n_trailing, 12L)
  expect_identical(result$n_exact, 40L)
  expect_identical(result$n_tolerated, 12L)
  expect_identical(result$n_rejected, 0L)

  source_rows$y[[1L]] <- 11
  rejected <- builder$compare_revisions_by_date(existing, source_rows, "2024-25")
  expect_identical(rejected$status, "rejected")
  expect_identical(rejected$n_rejected, 1L)
})

test_that("ORVT builder preserves source provenance on replacement rows", {
  builder <- new.env(parent = globalenv())
  builder_path <- testthat::test_path(
    "..", "..", "..", "scripts", "build_flu_hist_orvt.R"
  )
  sys.source(builder_path, envir = builder)
  source_rows <- data.frame(
    pho_season = "2025-26", week = 27L, mmwr_year = 2025L,
    week_start_date = "2025-07-06", week_end_date = "2025-07-12",
    p = 0.1, y = 10, N = 100, weekF = 1L,
    source_feed = "feed.csv", source_sha256 = "sha", stringsAsFactors = FALSE
  )
  template <- data.frame(
    season = "old", pho_season = "old", week = 1L, year = 2024L,
    seasonstart = 2024L, seasonend = 2025L, week_start_date = "old",
    week_end_date = "old", test_flu = 1, pos_flua = 1,
    fluAPercentPositive = 100, total_flu_percent_pos = 100,
    charyrsw = "old", weeksort = 1L, datasource = "old",
    weekF = 10L, weekS = 2L, pos_flub = 7,
    stringsAsFactors = FALSE
  )
  source_rows <- rbind(source_rows, transform(source_rows,
    week = 28L, week_start_date = "2025-07-13", week_end_date = "2025-07-19", weekF = 2L
  ))
  source_rows$weekS <- c(46L, 47L)
  out <- builder$make_source_rows(
    source_rows, "2025-26",
    partial = FALSE, template, "orvt_replacement"
  )
  expect_equal(out$season, rep("2025-26", 2))
  expect_equal(out$seasonstart, rep(2025L, 2))
  expect_equal(out$season_partial, rep(FALSE, 2))
  expect_equal(out$source_feed, rep("feed.csv", 2))
  expect_equal(out$source_sha256, rep("sha", 2))
  # Nothing is inherited from the historical template row.
  expect_equal(out$weekF, c(1L, 2L))
  expect_equal(out$weekS, c(46L, 47L))
  expect_true(all(is.na(out$pos_flub)))
})
