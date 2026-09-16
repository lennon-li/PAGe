test_that("page_season_calendar derives July seasons across a year boundary", {
  dates <- as.Date(c("2025-06-29", "2025-12-28", "2026-01-04", "2026-06-28"))
  out <- PAGe::page_season_calendar(dates = dates)
  expect_equal(out$season, rep("2025-26", 4L))
  expect_equal(out$week, c(27L, 53L, 1L, 26L))
  expect_equal(out$nW_true, rep(53L, 4L))
  expect_equal(out$weekF, c(1L, 27L, 28L, 53L))
  expect_equal(out$weekS, c(46L, 19L, 20L, 45L))
})

test_that("page_season_calendar accepts explicit MMWR year/week and rejects bad pairs", {
  out <- PAGe::page_season_calendar(mmwr_year = c(2025L, 2026L), week = c(53L, 1L))
  expect_equal(out$season, c("2025-26", "2025-26"))
  expect_equal(out$weekF, c(27L, 28L))
  expect_error(
    PAGe::page_season_calendar(mmwr_year = 2024L, week = 53L),
    "invalid MMWR"
  )
})

test_that("alignment shift is plain and flags the fixed template domain", {
  expect_equal(PAGe:::.page_shift_week(1:3, iWeek = 10, anchorWeek = 20), 11:13)
  outs <- list(
    list(
      data = data.frame(season = "2025-26", weekF = c(1L, 52L)),
      ignition = data.frame(season = "2025-26", weekF = 20L)
    )
  )
  aligned <- PAGe:::alignIgnition(outs)
  expect_equal(aligned$newWeek, c(1 - 20 + 20, 52 - 20 + 20))
  expect_false(any(aligned$alignment_out_of_domain))

  shifted <- list(
    list(
      data = data.frame(season = "2024-25", weekF = c(1L, 41L)),
      ignition = data.frame(season = "2024-25", weekF = 10L)
    ),
    list(
      data = data.frame(season = "2025-26", weekF = c(1L, 52L)),
      ignition = data.frame(season = "2025-26", weekF = 30L)
    )
  )
  out <- PAGe:::alignIgnition(shifted)
  out_b <- out[out$season == "2025-26", , drop = FALSE]
  expect_equal(out_b$newWeek, c(-9, 42))
  expect_true(out_b$alignment_out_of_domain[1L])
  expect_equal(attr(out, "out_of_domain_by_season")$n_out_of_domain, c(0L, 1L))
})

test_that("walk-forward prefix guard rejects future rows", {
  expect_silent(PAGe:::.page_assert_prefix(
    data.frame(season = "s", weekF = 1:3), 3L
  ))
  expect_error(
    PAGe:::.page_assert_prefix(data.frame(season = "s", weekF = 1:4), 3L),
    "weekF > origin"
  )
})

test_that("dated adapter ignores a conflicting source season label", {
  raw <- data.frame(
    source_season = "wrong-label", mmwr_week = c(28L, 1L),
    week_start = as.Date(c("2025-07-06", "2026-01-04")),
    y = c(1L, 2L), N = c(10L, 10L)
  )
  out <- PAGe::prepare_page_data(
    raw,
    outcome_col = "y", week_col = "mmwr_week", season_col = "source_season",
    total_col = "N", week_type = "mmwr", date_col = "week_start"
  )
  expect_equal(out$season, c("2025-26", "2025-26"))
  expect_equal(out$pho_season, c("wrong-label", "wrong-label"))
  expect_equal(out$weekF, c(2L, 28L))
})

test_that("calendar helpers agree on every start year", {
  years <- 2012:2026
  for (year in years) {
    df <- data.frame(season = sprintf("%d-%02d", year, (year + 1) %% 100))
    expected <- PAGe::page_season_calendar(mmwr_year = year, week = 27L)$nW_true
    expect_equal(PAGe:::.season_calendar_weeks(df), expected)
    if (year %in% c(2014, 2020, 2025)) {
      expect_equal(expected, 53L)
    } else {
      expect_equal(expected, 52L)
    }
  }
})

test_that("the template domain is the declared width, not the season length", {
  outs <- list(
    list(
      data = data.frame(season = "2014-15", weekF = 1:53),
      ignition = data.frame(season = "2014-15", weekF = 20L)
    ),
    list(
      data = data.frame(season = "2020-21", weekF = 1:53),
      ignition = data.frame(season = "2020-21", weekF = 20L)
    )
  )
  aligned <- PAGe:::alignIgnition(outs)
  expect_true(all(aligned$alignment_out_of_domain[aligned$weekF == 53L]))
  expect_equal(aligned$nW_true[aligned$season == "2014-15" & aligned$weekF == 53L], 53L)
  expect_equal(aligned$nW_true[aligned$season == "2020-21" & aligned$weekF == 53L], 53L)

  aligned_wide <- PAGe:::alignIgnition(outs, template_weeks = 53L)
  expect_false(any(aligned_wide$alignment_out_of_domain[aligned_wide$weekF == 53L]))
})

test_that("52-week seasons are unchanged", {
  outs <- list(
    list(
      data = data.frame(season = "2015-16", weekF = 1:52),
      ignition = data.frame(season = "2015-16", weekF = 20L)
    ),
    list(
      data = data.frame(season = "2016-17", weekF = 1:52),
      ignition = data.frame(season = "2016-17", weekF = 20L)
    )
  )
  aligned <- PAGe:::alignIgnition(outs)
  expect_false(any(aligned$alignment_out_of_domain))
})

test_that(".page_alignment_domain treats non-finite input as out of domain", {
  expect_equal(
    PAGe:::.page_alignment_domain(c(1, NA, Inf, 30), 52L)$in_domain,
    c(TRUE, FALSE, FALSE, TRUE)
  )
})
