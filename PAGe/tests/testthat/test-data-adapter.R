test_that("prepare_page_data maps arbitrary within-season data to the canonical contract", {
  raw <- data.frame(
    disease = c("x", "x", "x"),
    season_id = c("A", "A", "B"),
    epi_week = c(1L, 2L, 1L),
    positives = c(2L, 3L, 0L),
    tested = c(10L, 12L, 8L),
    site = c("one", "one", "two")
  )

  out <- PAGe::prepare_page_data(
    raw,
    outcome_col = "positives",
    week_col = "epi_week",
    season_col = "season_id",
    total_col = "tested"
  )

  expect_s3_class(out, "data.frame")
  expect_equal(out$season, c("A", "A", "B"))
  expect_equal(out$weekF, c(1, 2, 1))
  expect_equal(out$y, c(2, 3, 0))
  expect_equal(out$N, c(10, 12, 8))
  expect_equal(out$neg, c(8, 9, 8))
  expect_equal(out$p, c(0.2, 0.25, 0))
  expect_equal(out$site, raw$site)
})

test_that("prepare_page_data derives weekF from MMWR weeks and season years", {
  raw <- data.frame(
    season_id = c("2024-25", "2024-25", "2025-26"),
    mmwr_week = c(27L, 28L, 27L),
    positives = c(1L, 2L, 3L),
    tested = c(10L, 10L, 10L)
  )

  out <- PAGe::prepare_page_data(
    raw,
    outcome_col = "positives",
    week_col = "mmwr_week",
    season_col = "season_id",
    total_col = "tested",
    week_type = "mmwr",
    start_week = 27L
  )

  expect_equal(out$weekF, c(1, 2, 1))
  expect_equal(out$season, raw$season_id)
})

test_that("prepare_page_data supports negatives and explicit start years", {
  raw <- data.frame(
    season_id = c("spring", "spring"),
    week = c(35L, 36L),
    positives = c(2L, 1L),
    negatives = c(8L, 9L),
    year0 = c(2025L, 2025L)
  )

  out <- PAGe::prepare_page_data(
    raw,
    outcome_col = "positives",
    week_col = "week",
    season_col = "season_id",
    negative_col = "negatives",
    week_type = "mmwr",
    start_year_col = "year0"
  )

  expect_equal(out$N, c(10, 10))
  expect_equal(out$weekF, c(9, 10))
})

test_that("prepare_page_data rejects ambiguous or invalid mappings", {
  raw <- data.frame(season = "A", week = 1L, positive = 1L, total = 2L)

  expect_error(
    PAGe::prepare_page_data(raw, "positive", "week", "season"),
    "total_col|negative_col"
  )
  expect_error(
    PAGe::prepare_page_data(raw, "positive", "week", "season", "total", "total"),
    "distinct"
  )
  expect_error(
    PAGe::prepare_page_data(
      raw, "positive", "week", "season", "total",
      week_type = "mmwr"
    ),
    "start_year_col"
  )
  expect_error(
    PAGe::prepare_page_data(
      transform(raw, positive = 3L), "positive", "week", "season", "total"
    ),
    "y.*cannot exceed|Positive counts"
  )
})

test_that("prepare_page_data matches the canonical Ontario multi-season data", {
  candidate_paths <- c(
    Sys.getenv("PAGE_ONTARIO_TEST_FILE", unset = ""),
    file.path(testthat::test_path(), "../../../data/flu_testing_data.csv")
  )
  candidate_paths <- candidate_paths[nzchar(candidate_paths)]
  source_path <- candidate_paths[file.exists(candidate_paths)][1L]
  if (is.na(source_path)) {
    skip("Ontario source data are private and not available in this checkout.")
  }

  ontario_raw <- utils::read.csv(source_path, stringsAsFactors = FALSE)
  required <- c("season", "week", "seasonstart", "pos_flua", "test_flu")
  expect_true(all(required %in% names(ontario_raw)))

  # Keep the source schema intentionally different from PAGe's canonical names.
  ontario <- data.frame(
    season_id = ontario_raw$season,
    mmwr_week = ontario_raw$week,
    start_year = ontario_raw$seasonstart,
    positive_tests = ontario_raw$pos_flua,
    total_tests = ontario_raw$test_flu,
    stringsAsFactors = FALSE
  )
  n_weeks <- vapply(
    ontario$start_year,
    PAGe:::n_weeks_in_start_year,
    integer(1)
  )
  expected_weekF <- ((ontario$mmwr_week - 27L) %% n_weeks) + 1L

  mapped <- PAGe::prepare_page_data(
    ontario,
    outcome_col = "positive_tests",
    week_col = "mmwr_week",
    season_col = "season_id",
    total_col = "total_tests",
    week_type = "mmwr",
    start_week = 27L,
    start_year_col = "start_year"
  )

  expect_equal(mapped$season, as.character(ontario_raw$season))
  expect_equal(mapped$weekF, expected_weekF)
  expect_equal(mapped$y, as.numeric(ontario_raw$pos_flua))
  expect_equal(mapped$N, as.numeric(ontario_raw$test_flu))
  expect_equal(mapped$neg, mapped$N - mapped$y)
  expect_equal(mapped$p, mapped$y / mapped$N)
  expect_no_error(PAGe::validate_surveillance_data(mapped))
})
