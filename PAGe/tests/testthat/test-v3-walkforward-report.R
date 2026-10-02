.walkforward_fixture_panel <- function() {
  panel_path <- system.file(
    "extdata", "v3-week12", "report-support", "week12_panel_fixture.csv",
    package = "PAGe"
  )
  utils::read.csv(panel_path, stringsAsFactors = FALSE, check.names = FALSE)
}

.walkforward_mock_orvt_bytes <- function(panel) {
  week_start <- as.Date(panel$week_start_date)
  week_end <- as.Date(panel$week_end_date)
  mmwr_week <- as.integer(MMWRweek::MMWRweek(week_start)$MMWRweek)
  build <- function(virus, y, N) {
    data.frame(
      "Public health unit" = "Toronto",
      Virus = virus,
      "Week start date" = format(week_start, "%d%b%Y"),
      "Week end date" = format(week_end, "%d%b%Y"),
      "Respiratory season" = panel$season,
      "Surveillance week" = mmwr_week,
      "# of positive tests" = y,
      "Total # of tests" = N,
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  }
  mock <- rbind(
    build("Influenza A", panel$y_A, panel$N_A),
    build("Influenza B", panel$y_B, panel$N_B)
  )
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path), add = TRUE)
  utils::write.csv(mock, path, row.names = FALSE, quote = FALSE)
  readBin(path, what = "raw", n = file.info(path)$size)
}

test_that("page_walkforward_report reproduces the governed Week-12 report", {
  panel_path <- system.file(
    "extdata", "v3-week12", "report-support", "week12_panel_fixture.csv",
    package = "PAGe"
  )
  expect_true(nzchar(panel_path))
  panel <- utils::read.csv(panel_path, stringsAsFactors = FALSE, check.names = FALSE)

  out <- tempfile(fileext = ".html")
  path <- page_walkforward_report(
    panel,
    season = "2026-27",
    output_file = out,
    self_contained = TRUE
  )
  expect_true(file.exists(path))
  html <- paste(readLines(path, warn = FALSE), collapse = "\n")

  expect_match(
    html,
    "PAGe 2026-27 Flu Season Walk-Forward Report -- Week 12",
    fixed = TRUE
  )
  expect_match(html, "3.517 / 3.498%", fixed = TRUE)
  expect_match(html, "0.0379 / 0.0394%", fixed = TRUE)
  expect_match(html, "Not available yet", fixed = TRUE)

  # Exact governed Week-12 point forecasts remain in the embedded report data.
  expect_match(html, "3.51705404452420", fixed = TRUE)
  expect_match(html, "3.49768310318725", fixed = TRUE)
  expect_match(html, "0.037855165827212", fixed = TRUE)
  expect_match(html, "0.039378396168781", fixed = TRUE)

  # A+B is a single display aggregation and has no joint timing tabs.
  expect_match(html, "name:'A+B forecast'", fixed = TRUE)
  expect_match(
    html,
    "state.type==='A+B'?['Forecast']:timingViews",
    fixed = TRUE
  )

  # M1 shape and uncertainty affordances match the approved report.
  expect_match(html, "Normalized seasonal shape (peak = 1)", fixed = TRUE)
  expect_match(html, "2026-27 observed (shape-scaled)", fixed = TRUE)
  expect_match(html, "forecast (95% CI)", fixed = TRUE)
  expect_match(html, "Approx. 95% retrospective PI", fixed = TRUE)
  expect_match(html, "PI not available yet", fixed = TRUE)

  # Self-contained output must not depend on an external Plotly script URL.
  expect_false(grepl(
    '<script src="https://cdn.plot.ly/', html,
    fixed = TRUE
  ))
})

test_that("page_walkforward_report builds a feed panel when data = NULL", {
  panel <- .walkforward_fixture_panel()
  bytes <- .walkforward_mock_orvt_bytes(panel)
  withr::local_options(PAGe.orvt_reader = function(url) bytes)

  out <- tempfile(fileext = ".html")
  path <- suppressWarnings(page_walkforward_report(
    data = NULL,
    season = "2026-27",
    output_file = out,
    self_contained = TRUE
  ))
  expect_true(file.exists(path))
  html <- paste(readLines(path, warn = FALSE), collapse = "\n")

  expect_match(
    html,
    "PAGe 2026-27 Flu Season Walk-Forward Report -- Week 12",
    fixed = TRUE
  )
  expect_match(html, "3.517 / 3.498%", fixed = TRUE)
  expect_match(html, "0.0379 / 0.0394%", fixed = TRUE)
  expect_match(html, "3.51705404452420", fixed = TRUE)
  expect_false(grepl("NA / NA%", html, fixed = TRUE))
})

test_that("page_walkforward_report runs live from the default ORVT feed", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  out <- tempfile(fileext = ".html")
  path <- tryCatch(
    page_walkforward_report(output_file = out),
    error = function(e) e
  )
  if (inherits(path, "error")) {
    testthat::skip(paste("Live ORVT feed unavailable:", conditionMessage(path)))
  }
  expect_true(file.exists(path))
  html <- paste(readLines(path, warn = FALSE), collapse = "\n")
  expect_match(html, "Flu Season Walk-Forward Report", fixed = TRUE)
  expect_false(grepl("NA / NA%", html, fixed = TRUE))
})

test_that("page_walkforward_report supports pre-window Week 11 panels", {
  panel <- .walkforward_fixture_panel()
  panel <- panel[panel$weekF <= 11L, , drop = FALSE]

  out <- tempfile(fileext = ".html")
  path <- page_walkforward_report(
    panel,
    season = "2026-27",
    output_file = out,
    self_contained = TRUE
  )
  expect_true(file.exists(path))
  html <- paste(readLines(path, warn = FALSE), collapse = "\n")

  expect_match(
    html,
    "PAGe 2026-27 Flu Season Walk-Forward Report -- Week 11",
    fixed = TRUE
  )
  expect_match(html, "Awaiting validated window", fixed = TRUE)
  expect_match(html, "Not available yet", fixed = TRUE)
  # Pre-window forecasts must not leak unformatted NA point forecasts.
  expect_false(grepl("NA / NA%", html, fixed = TRUE))
})
