#!/usr/bin/env Rscript

# Governed 2016-17 holdout cycle for the BCC installed-package run.
# The maintained cycle runner supplies the M0 -> M1 -> M2 gates; this wrapper
# changes only the labeled holdout season.

script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
if (is.null(script_file) || !nzchar(script_file)) {
  script_file <- "2016/run_2016_cycle.R"
}
repo_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
setwd(repo_root)

runner <- readLines(file.path(repo_root, "2018", "run_2018_cycle.R"), warn = FALSE)
needle <- 'holdout_season <- "2018-19"'
if (!any(grepl(needle, runner, fixed = TRUE))) {
  stop("The maintained 2018 cycle runner no longer exposes its holdout label.")
}
runner <- sub(needle, 'holdout_season <- "2016-17"', runner, fixed = TRUE)
runner <- sub(
  'suppressPackageStartupMessages(devtools::load_all("PAGe", quiet = TRUE))',
  'suppressPackageStartupMessages(library(PAGe))',
  runner,
  fixed = TRUE
)
if (identical(Sys.getenv("PAGE_M1_GRID_PROFILE"), "expanded")) {
  m1_grid_line <- 'm1_grid <- data.table::CJ(k_ref = c(20L, 25L, 30L, 40L, 50L, 60L), multi_temperature = 0.25, template_shift = 0L, align_rise_weight = 1.0, slope_window = 6L, slope_weight = c(4.0, 8.0, 12.0, 16.0, 20.0, 30.0), sorted = FALSE)'
  runner <- sub(
    'm0_grid <- data.table::CJ(',
    paste0(m1_grid_line, '\n', 'm0_grid <- data.table::CJ('),
    runner,
    fixed = TRUE
  )
  runner <- sub(
    'm0_grid = m0_grid,\n  selection_method',
    'm0_grid = m0_grid, m1_grid = m1_grid,\n  selection_method',
    runner,
    fixed = TRUE
  )
}
eval(parse(text = runner), envir = .GlobalEnv)
