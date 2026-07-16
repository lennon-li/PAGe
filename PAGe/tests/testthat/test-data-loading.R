test_that("historical data loading requires an explicit safe source", {
  csv <- tempfile(fileext = ".csv")
  on.exit(unlink(csv))
  write.csv(data.frame(season = "2024-25", weekF = 1L, y = 1L, N = 10L),
    csv, row.names = FALSE
  )

  explicit <- PAGe::load_flu_hist(csv)
  expect_identical(as.character(explicit$season), "2024-25")

  withr::local_envvar(PAGE_FLU_HIST_FILE = csv)
  from_env <- PAGe::load_flu_hist()
  expect_identical(from_env$weekF, 1L)
})

test_that("missing historical data gives an actionable error", {
  withr::local_envvar(PAGE_FLU_HIST_FILE = "")
  expect_error(
    PAGe::load_flu_hist(tempfile()),
    "Supply `path` or set PAGE_FLU_HIST_FILE"
  )
})
