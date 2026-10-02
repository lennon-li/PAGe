test_that("page_v3_walkforward_report reproduces the governed Week-12 report", {
  panel_path <- system.file(
    "extdata", "v3-week12", "report-support", "week12_panel_fixture.csv",
    package = "PAGe"
  )
  expect_true(nzchar(panel_path))
  panel <- utils::read.csv(panel_path, stringsAsFactors = FALSE, check.names = FALSE)

  out <- tempfile(fileext = ".html")
  path <- page_v3_walkforward_report(
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
