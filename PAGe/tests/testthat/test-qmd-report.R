test_that("page_walkforward_qmd builds and renders the Week 10 Quarto report", {
  hist <- "/home/yeli/repos/IRVRI/OP/hist2026-09-16.RData"
  testthat::skip_if_not(file.exists(hist), "IRVRI OLIS snapshot is unavailable")
  testthat::skip_if(
    !nzchar(Sys.which("quarto")) && !file.exists("/home/yeli/.local/bin/quarto"),
    "Quarto is unavailable"
  )

  res <- page_walkforward_qmd(
    data = hist,
    season = "2026-27",
    output_dir = tempdir(),
    render = TRUE
  )

  expect_true(file.exists(res$qmd_path))
  qmd <- paste(readLines(res$qmd_path, warn = FALSE), collapse = "\n")
  expect_match(qmd, "::: {.panel-tabset}", fixed = TRUE)
  expect_match(qmd, "Week 10", fixed = TRUE)
  expect_match(qmd, "### Week 8", fixed = TRUE)

  expect_true(file.exists(res$html_path))
  expect_gt(file.info(res$html_path)$size, 0)

  expect_true(is.data.frame(res$data))
  expect_identical(max(res$data$weekF), 10L)
})

test_that("page_render_report is an alias for page_walkforward_qmd", {
  hist <- "/home/yeli/repos/IRVRI/OP/hist2026-09-16.RData"
  testthat::skip_if_not(file.exists(hist), "IRVRI OLIS snapshot is unavailable")

  res <- page_render_report(
    data = hist,
    season = "2026-27",
    output_dir = tempdir(),
    render = FALSE
  )
  expect_true(file.exists(res$qmd_path))
  expect_true(is.na(res$html_path))
})
